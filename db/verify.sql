BEGIN;

DO $$
DECLARE
    actor_one uuid := '00000000-0000-0000-0000-000000000001';
    actor_two uuid := '00000000-0000-0000-0000-000000000002';
    sender uuid := gen_random_uuid();
    recipient uuid := gen_random_uuid();
    replacement uuid := gen_random_uuid();
    shipment uuid := gen_random_uuid();
    empty_shipment uuid := gen_random_uuid();
    rolled_back_customer uuid := gen_random_uuid();
    email text := 'verify.' || gen_random_uuid()::text || '@example.com';
    tracking text := 'TEST' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 20));
    initial_created timestamptz;
    initial_updated timestamptz;
    events_before bigint;
    entity_count integer;
    routine_count integer;
    index_type_count integer;
    test_address integer;
    test_branch integer;
BEGIN
    SELECT count(*) INTO entity_count FROM information_schema.tables
        WHERE table_schema = 'postal' AND table_type = 'BASE TABLE';
    SELECT count(*) INTO routine_count FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'postal';
    SELECT count(DISTINCT am.amname) INTO index_type_count FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_am am ON am.oid = c.relam WHERE n.nspname = 'postal';
    IF entity_count < 15 OR routine_count < 10 OR index_type_count < 2 THEN
        RAISE EXCEPTION 'Catalog check failed: tables %, routines %, index types %',
            entity_count, routine_count, index_type_count;
    END IF;

    PERFORM set_config('postal.actor_id', '', true);
    BEGIN
        CALL postal.create_customer(gen_random_uuid(), 'Без оператора', 'no.actor@example.com', '+380501234567');
        RAISE EXCEPTION 'An actor must be required';
    EXCEPTION WHEN invalid_authorization_specification THEN NULL;
    END;
    BEGIN
        CALL postal.set_actor(gen_random_uuid());
        RAISE EXCEPTION 'An unknown actor must be rejected';
    EXCEPTION WHEN invalid_authorization_specification THEN NULL;
    END;
    CALL postal.set_actor(actor_one);
    CALL postal.create_customer(sender, 'Перевірка Відправник', email, '+380501234567');
    CALL postal.create_customer(recipient, 'Перевірка Отримувач', 'recipient.' || email, '+380671234567');
    SELECT created_at, updated_at INTO initial_created, initial_updated FROM postal.v_customers WHERE id = sender;
    CALL postal.set_actor(actor_two);
    CALL postal.update_customer(sender, 'Змінений Відправник', email, '+380931234567');
    IF NOT EXISTS (SELECT 1 FROM postal.v_customers WHERE id = sender AND updated_by = actor_two
        AND created_at = initial_created AND updated_at > initial_updated) THEN
        RAISE EXCEPTION 'Audit actor, timestamps or creation stamp are incorrect';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM postal.v_audit_log WHERE entity_name = 'customers'
        AND entity_id = sender::text AND operation = 'update' AND changed_by = actor_two
        AND old_data ->> 'full_name' = 'Перевірка Відправник'
        AND new_data ->> 'full_name' = 'Змінений Відправник') THEN
        RAISE EXCEPTION 'Audit history must contain both versions';
    END IF;
    RAISE NOTICE 'PASS actor context and audit';

    CALL postal.create_shipment(shipment, tracking, sender, recipient, 1, 2, 1, 500);
    CALL postal.create_shipment(empty_shipment, tracking || 'E', sender, recipient, 1, 2, 1, 0);
    BEGIN
        CALL postal.change_status(empty_shipment, 2, 'Порожнє відправлення');
        RAISE EXCEPTION 'An empty shipment must not be accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        CALL postal.record_payment(gen_random_uuid(), shipment, 1, 1, NULL);
        RAISE EXCEPTION 'A draft must not accept payments';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    CALL postal.add_parcel(gen_random_uuid(), shipment, 'Перше місце', 1.2, 30, 20, 10);
    CALL postal.add_parcel(gen_random_uuid(), shipment, 'Друге місце', 0.8, 20, 15, 10);
    IF NOT EXISTS (SELECT 1 FROM postal.v_shipments WHERE id = shipment AND parcel_count = 2
        AND total_weight_kg = 2 AND price = 95) THEN
        RAISE EXCEPTION 'The tariff must use total weight and charge the base fee only once';
    END IF;
    BEGIN
        CALL postal.add_parcel(gen_random_uuid(), shipment, 'Зайва вага', 100, 10, 10, 10);
        RAISE EXCEPTION 'The tariff weight limit must be enforced';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        CALL postal.add_parcel(gen_random_uuid(), shipment, 'Нульова вага', 0, 10, 10, 10);
        RAISE EXCEPTION 'Zero weight must be rejected';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    IF (SELECT parcel_count FROM postal.v_shipments WHERE id = shipment) <> 2 THEN
        RAISE EXCEPTION 'A failed parcel write must leave the aggregate unchanged';
    END IF;

    SELECT count(*) INTO events_before FROM postal.v_tracking_history WHERE shipment_id = shipment;
    BEGIN
        CALL postal.change_status(shipment, 5, 'Пропущено етапи');
        RAISE EXCEPTION 'A draft must not become delivered';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    IF (SELECT count(*) FROM postal.v_tracking_history WHERE shipment_id = shipment) <> events_before THEN
        RAISE EXCEPTION 'A rejected transition must not append an event';
    END IF;
    CALL postal.change_status(shipment, 2, 'Прийнято два місця');
    BEGIN
        CALL postal.add_parcel(gen_random_uuid(), shipment, 'Після приймання', 1, 10, 10, 10);
        RAISE EXCEPTION 'Accepted shipment parcels must be frozen';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    CALL postal.assign_to_run('00000000-0000-0000-0000-000000000601', shipment);
    IF NOT EXISTS (SELECT 1 FROM postal.v_transport_manifest WHERE shipment_id = shipment AND weight_kg = 2) THEN
        RAISE EXCEPTION 'The run manifest is incomplete';
    END IF;
    RAISE NOTICE 'PASS shipment aggregate, tariff, transitions and manifest';

    CALL postal.record_payment(gen_random_uuid(), shipment, 94, 1, NULL);
    BEGIN
        CALL postal.record_payment(gen_random_uuid(), shipment, 2, 1, NULL);
        RAISE EXCEPTION 'Overpayment must be rejected';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    IF postal.fn_shipment_balance(shipment) <> 1 THEN RAISE EXCEPTION 'Partial payment balance is incorrect'; END IF;
    BEGIN
        CALL postal.change_status(shipment, 6, 'Скасування оплаченої посилки');
        RAISE EXCEPTION 'A paid shipment must not be cancelled';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        CALL postal.delete_shipment(shipment);
        RAISE EXCEPTION 'A paid shipment must not be deleted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    CALL postal.change_status(shipment, 3, 'Відправлено');
    CALL postal.change_status(shipment, 4, 'Прибуло');
    BEGIN
        CALL postal.change_status(shipment, 5, 'Не оплачено повністю');
        RAISE EXCEPTION 'Delivery with an unpaid balance must be rejected';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    CALL postal.record_payment(gen_random_uuid(), shipment, 1, 2, 'VERIFY-' || shipment::text);
    CALL postal.record_delivery_attempt(gen_random_uuid(), shipment, 2, 'failed', 'Отримувач не прийшов');
    CALL postal.record_delivery_attempt(gen_random_uuid(), shipment, 2, 'delivered', 'Видано отримувачу');
    IF NOT EXISTS (SELECT 1 FROM postal.v_shipments WHERE id = shipment AND status_id = 5 AND balance = 0)
        OR (SELECT max(attempt_no) FROM postal.delivery_attempts WHERE shipment_id = shipment) <> 2 THEN
        RAISE EXCEPTION 'Delivery attempts must be numbered and completion must change the status';
    END IF;
    IF (SELECT count(*) FROM postal.v_tracking_history WHERE shipment_id = shipment) <> 5 THEN
        RAISE EXCEPTION 'Every status change must create exactly one history event';
    END IF;
    RAISE NOTICE 'PASS payments and delivery';

    CALL postal.delete_customer(sender);
    IF EXISTS (SELECT 1 FROM postal.v_customers WHERE id = sender)
        OR NOT EXISTS (SELECT 1 FROM postal.v_customers_all WHERE id = sender AND deleted_by = actor_two)
        OR NOT EXISTS (SELECT 1 FROM postal.v_shipments WHERE id = shipment AND sender_id = sender) THEN
        RAISE EXCEPTION 'Soft deletion must hide the customer while preserving shipment history';
    END IF;
    BEGIN
        CALL postal.create_shipment(gen_random_uuid(), tracking || 'D', sender, recipient, 1, 2, 1, 0);
        RAISE EXCEPTION 'A deleted customer must not create new shipments';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    CALL postal.create_customer(replacement, 'Новий власник адреси', email, '+380501234500');
    BEGIN
        CALL postal.restore_customer(sender);
        RAISE EXCEPTION 'Restoring a duplicate active email must be rejected';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    CALL postal.delete_customer(replacement);
    CALL postal.restore_customer(sender);
    CALL postal.delete_shipment(empty_shipment);
    IF EXISTS (SELECT 1 FROM postal.v_shipments WHERE id = empty_shipment)
        OR EXISTS (SELECT 1 FROM postal.v_tracking_history WHERE shipment_id = empty_shipment)
        OR NOT EXISTS (SELECT 1 FROM postal.shipment_events WHERE shipment_id = empty_shipment) THEN
        RAISE EXCEPTION 'Shipment deletion must filter views and preserve stored history';
    END IF;
    CALL postal.restore_shipment(empty_shipment);
    IF NOT EXISTS (SELECT 1 FROM postal.v_shipments WHERE id = empty_shipment) THEN
        RAISE EXCEPTION 'Shipment restoration failed';
    END IF;
    RAISE NOTICE 'PASS soft deletion, restoration and active email uniqueness';

    INSERT INTO postal.addresses (city_id, street, building, postal_code)
        VALUES (1, 'Тестова вулиця', '1', '01001') RETURNING id INTO test_address;
    INSERT INTO postal.branches (code, name, address_id)
        VALUES (tracking, 'Тестове відділення', test_address) RETURNING id INTO test_branch;
    BEGIN
        CALL postal.delete_address(test_address);
        RAISE EXCEPTION 'An active branch address must not be deleted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        CALL postal.delete_branch(1);
        RAISE EXCEPTION 'A branch with unfinished shipments must not be deleted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    CALL postal.delete_branch(test_branch);
    CALL postal.delete_address(test_address);
    IF EXISTS (SELECT 1 FROM postal.v_branch_directory WHERE id = test_branch) THEN
        RAISE EXCEPTION 'A deleted branch must be hidden from the directory';
    END IF;
    BEGIN
        CALL postal.restore_branch(test_branch);
        RAISE EXCEPTION 'A branch with a deleted address must not be restored';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    CALL postal.restore_address(test_address);
    CALL postal.restore_branch(test_branch);
    IF NOT EXISTS (SELECT 1 FROM postal.v_branch_directory WHERE id = test_branch)
        OR NOT EXISTS (SELECT 1 FROM postal.audit_log WHERE entity_name = 'branches'
            AND entity_id = test_branch::text AND operation = 'restore' AND changed_by = actor_two) THEN
        RAISE EXCEPTION 'Address and branch restoration must preserve audit metadata';
    END IF;
    RAISE NOTICE 'PASS address and branch lifecycle';

    BEGIN
        CALL postal.create_customer(rolled_back_customer, 'Незавершена операція', 'rollback.' || email, '+380501234599');
        CALL postal.create_shipment(gen_random_uuid(), tracking || 'R', rolled_back_customer, recipient, 1, 1, 1, 0);
        RAISE EXCEPTION 'The second aggregate write must fail';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    IF EXISTS (SELECT 1 FROM postal.v_customers_all WHERE id = rolled_back_customer)
        OR EXISTS (SELECT 1 FROM postal.v_audit_log WHERE entity_id = rolled_back_customer::text) THEN
        RAISE EXCEPTION 'A failed unit must roll back the first write and its audit entry';
    END IF;
    BEGIN
        DELETE FROM postal.customers WHERE id = sender;
        RAISE EXCEPTION 'Physical customer deletion must be prohibited';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE postal.payments SET amount = amount + 1 WHERE shipment_id = shipment;
        RAISE EXCEPTION 'Payment history must be immutable';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        DELETE FROM postal.shipment_events WHERE shipment_id = shipment;
        RAISE EXCEPTION 'Tracking history must be immutable';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        DELETE FROM postal.audit_log WHERE entity_id = sender::text;
        RAISE EXCEPTION 'Audit history must be immutable';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    RAISE NOTICE 'PASS atomic rollback and immutable history';
END;
$$;

SELECT 'tables' AS object_type, count(*) AS object_count FROM information_schema.tables
WHERE table_schema = 'postal' AND table_type = 'BASE TABLE'
UNION ALL SELECT 'routines', count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'postal'
UNION ALL SELECT 'views', count(*) FROM information_schema.views WHERE table_schema = 'postal'
UNION ALL SELECT 'triggers', count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'postal' AND NOT t.tgisinternal;

ROLLBACK;
SELECT 'Усі перевірки пройдено; тестові зміни відкочено.' AS result;
