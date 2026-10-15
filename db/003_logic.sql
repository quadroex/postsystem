CREATE FUNCTION postal.fn_actor() RETURNS uuid
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, postal
AS $$
DECLARE
    actor uuid;
BEGIN
    BEGIN
        actor := nullif(current_setting('postal.actor_id', true), '')::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        RAISE EXCEPTION 'Invalid actor context' USING ERRCODE = '28000';
    END;
    IF actor IS NULL OR NOT EXISTS (SELECT 1 FROM postal.app_users WHERE id = actor AND is_active) THEN
        RAISE EXCEPTION 'Call postal.set_actor with an active user inside the transaction'
            USING ERRCODE = '28000';
    END IF;
    RETURN actor;
END;
$$;

CREATE PROCEDURE postal.set_actor(p_user_id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM postal.app_users WHERE id = p_user_id AND is_active) THEN
        RAISE EXCEPTION 'User is missing or inactive' USING ERRCODE = '28000';
    END IF;
    PERFORM set_config('postal.actor_id', p_user_id::text, true);
END;
$$;

CREATE FUNCTION postal.fn_can_transition(p_old integer, p_new integer) RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, postal
AS $$
    SELECT coalesce((p_old = 1 AND p_new IN (2, 6))
        OR (p_old = 2 AND p_new IN (3, 6))
        OR (p_old = 3 AND p_new = 4)
        OR (p_old = 4 AND p_new = 5), false);
$$;

CREATE FUNCTION postal.fn_shipment_price(p_shipment_id uuid) RETURNS numeric
LANGUAGE plpgsql STABLE
SET search_path = pg_catalog, postal
AS $$
DECLARE
    shipment postal.shipments%ROWTYPE;
    tariff postal.tariffs%ROWTYPE;
    weight numeric;
BEGIN
    SELECT * INTO STRICT shipment FROM postal.shipments WHERE id = p_shipment_id;
    SELECT * INTO STRICT tariff FROM postal.tariffs WHERE service_type_id = shipment.service_type_id;
    SELECT coalesce(sum(weight_kg), 0) INTO weight FROM postal.parcels WHERE shipment_id = p_shipment_id;
    IF weight > tariff.max_weight_kg THEN
        RAISE EXCEPTION 'Weight % exceeds the service limit % kg', weight, tariff.max_weight_kg
            USING ERRCODE = '23514';
    END IF;
    IF weight = 0 THEN RETURN 0; END IF;
    RETURN round(tariff.base_price + ceil(weight) * tariff.price_per_kg
        + shipment.declared_value * tariff.insurance_rate, 2);
END;
$$;

CREATE FUNCTION postal.fn_shipment_balance(p_shipment_id uuid) RETURNS numeric
LANGUAGE sql STABLE
SET search_path = pg_catalog, postal
AS $$
    SELECT s.price - coalesce((SELECT sum(p.amount) FROM postal.payments p WHERE p.shipment_id = s.id), 0)
    FROM postal.shipments s WHERE s.id = p_shipment_id;
$$;

CREATE FUNCTION postal.trg_stamp_audit() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
DECLARE actor uuid := postal.fn_actor();
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.deleted_at IS NOT NULL OR NEW.deleted_by IS NOT NULL THEN
            RAISE EXCEPTION 'New records must be active' USING ERRCODE = '23514';
        END IF;
        NEW.created_at := clock_timestamp();
        NEW.created_by := actor;
    ELSE
        IF NEW.id IS DISTINCT FROM OLD.id THEN
            RAISE EXCEPTION 'The primary key cannot be changed' USING ERRCODE = '23514';
        END IF;
        IF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NOT NULL THEN
            RAISE EXCEPTION 'Restore the record before editing it' USING ERRCODE = '23514';
        END IF;
        NEW.created_at := OLD.created_at;
        NEW.created_by := OLD.created_by;
        IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
            NEW.deleted_at := clock_timestamp();
            NEW.deleted_by := actor;
        END IF;
    END IF;
    IF NEW.deleted_at IS NULL THEN NEW.deleted_by := NULL; END IF;
    NEW.updated_at := clock_timestamp();
    NEW.updated_by := actor;
    RETURN NEW;
END;
$$;

CREATE FUNCTION postal.trg_log_audit() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
DECLARE operation_name text;
BEGIN
    operation_name := CASE
        WHEN TG_OP = 'INSERT' THEN 'insert'
        WHEN OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN 'soft_delete'
        WHEN OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN 'restore'
        ELSE 'update' END;
    INSERT INTO postal.audit_log (entity_name, entity_id, operation, changed_by, old_data, new_data)
    VALUES (TG_TABLE_NAME, NEW.id::text, operation_name, NEW.updated_by,
        CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) END, to_jsonb(NEW));
    RETURN NEW;
END;
$$;

CREATE FUNCTION postal.trg_block_mutation() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
BEGIN
    RAISE EXCEPTION '% on % is prohibited; preserve the history', TG_OP, TG_TABLE_NAME
        USING ERRCODE = '23514';
END;
$$;

CREATE FUNCTION postal.trg_guard_shipment() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND (NEW.status_id <> 1 OR NEW.price <> 0) THEN
        RAISE EXCEPTION 'A shipment must start as an unpriced draft' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'INSERT' OR NEW.status_id = 2
        OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
        OR NEW.recipient_id IS DISTINCT FROM OLD.recipient_id
        OR NEW.origin_branch_id IS DISTINCT FROM OLD.origin_branch_id
        OR NEW.destination_branch_id IS DISTINCT FROM OLD.destination_branch_id
        OR NEW.service_type_id IS DISTINCT FROM OLD.service_type_id THEN
        PERFORM id FROM postal.customers WHERE id IN (NEW.sender_id, NEW.recipient_id)
            ORDER BY id FOR SHARE;
        IF NOT EXISTS (SELECT 1 FROM postal.customers WHERE id = NEW.sender_id AND deleted_at IS NULL)
            OR NOT EXISTS (SELECT 1 FROM postal.customers WHERE id = NEW.recipient_id AND deleted_at IS NULL) THEN
            RAISE EXCEPTION 'Sender and recipient must be active customers' USING ERRCODE = '23514';
        END IF;
        PERFORM b.id FROM postal.branches b JOIN postal.addresses a ON a.id = b.address_id
            WHERE b.id IN (NEW.origin_branch_id, NEW.destination_branch_id)
            ORDER BY b.id FOR SHARE OF b, a;
        IF (SELECT count(*) FROM postal.branches b JOIN postal.addresses a ON a.id = b.address_id
            WHERE b.id IN (NEW.origin_branch_id, NEW.destination_branch_id)
              AND b.deleted_at IS NULL AND b.is_operational AND a.deleted_at IS NULL) <> 2 THEN
            RAISE EXCEPTION 'Origin and destination must be different active branches'
                USING ERRCODE = '23514';
        END IF;
        PERFORM id FROM postal.service_types WHERE id = NEW.service_type_id AND is_active FOR SHARE;
        IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM postal.tariffs WHERE service_type_id = NEW.service_type_id) THEN
            RAISE EXCEPTION 'The service or its tariff is unavailable' USING ERRCODE = '23514';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.deleted_at IS NOT NULL AND NEW.status_id <> OLD.status_id THEN
            RAISE EXCEPTION 'A deleted shipment cannot change status' USING ERRCODE = '23514';
        END IF;
        IF NEW.tracking_number IS DISTINCT FROM OLD.tracking_number THEN
            RAISE EXCEPTION 'Tracking number is immutable' USING ERRCODE = '23514';
        END IF;
        IF OLD.status_id <> 1 AND (
            NEW.sender_id IS DISTINCT FROM OLD.sender_id OR NEW.recipient_id IS DISTINCT FROM OLD.recipient_id
            OR NEW.origin_branch_id IS DISTINCT FROM OLD.origin_branch_id
            OR NEW.destination_branch_id IS DISTINCT FROM OLD.destination_branch_id
            OR NEW.service_type_id IS DISTINCT FROM OLD.service_type_id
            OR NEW.declared_value IS DISTINCT FROM OLD.declared_value OR NEW.price IS DISTINCT FROM OLD.price) THEN
            RAISE EXCEPTION 'Accepted shipment details and price are immutable' USING ERRCODE = '23514';
        END IF;
        IF NEW.status_id IS DISTINCT FROM OLD.status_id THEN
            IF NOT postal.fn_can_transition(OLD.status_id, NEW.status_id) THEN
                RAISE EXCEPTION 'Invalid status transition: % -> %', OLD.status_id, NEW.status_id
                    USING ERRCODE = '23514';
            END IF;
            IF NEW.status_id = 2 THEN
                IF NOT EXISTS (SELECT 1 FROM postal.parcels WHERE shipment_id = OLD.id) THEN
                    RAISE EXCEPTION 'Add at least one parcel before acceptance' USING ERRCODE = '23514';
                END IF;
                NEW.price := postal.fn_shipment_price(OLD.id);
            ELSIF NEW.status_id = 5 AND postal.fn_shipment_balance(OLD.id) <> 0 THEN
                RAISE EXCEPTION 'Pay the shipment before delivery' USING ERRCODE = '23514';
            ELSIF NEW.status_id = 6 AND EXISTS (SELECT 1 FROM postal.payments WHERE shipment_id = OLD.id) THEN
                RAISE EXCEPTION 'A paid shipment cannot be cancelled without a refund' USING ERRCODE = '23514';
            END IF;
        END IF;
        IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
            IF OLD.status_id NOT IN (1, 6) OR EXISTS (SELECT 1 FROM postal.payments WHERE shipment_id = OLD.id) THEN
                RAISE EXCEPTION 'Only unpaid drafts or cancelled shipments may be deleted' USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION postal.trg_shipment_event() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
BEGIN
    IF TG_OP = 'INSERT' OR NEW.status_id IS DISTINCT FROM OLD.status_id THEN
        INSERT INTO postal.shipment_events (id, shipment_id, status_id, branch_id, note, recorded_by)
        VALUES (gen_random_uuid(), NEW.id, NEW.status_id,
            CASE WHEN NEW.status_id IN (4, 5) THEN NEW.destination_branch_id ELSE NEW.origin_branch_id END,
            coalesce(nullif(current_setting('postal.event_note', true), ''),
                CASE WHEN TG_OP = 'INSERT' THEN 'Створено відправлення' ELSE 'Змінено статус' END),
            postal.fn_actor());
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION postal.trg_guard_parcel() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
DECLARE shipment postal.shipments%ROWTYPE;
BEGIN
    SELECT * INTO shipment FROM postal.shipments WHERE id = NEW.shipment_id FOR UPDATE;
    IF NOT FOUND OR shipment.deleted_at IS NOT NULL OR shipment.status_id <> 1 THEN
        RAISE EXCEPTION 'Parcels may be added only to an active draft' USING ERRCODE = '23514';
    END IF;
    NEW.created_at := clock_timestamp();
    NEW.created_by := postal.fn_actor();
    RETURN NEW;
END;
$$;

CREATE FUNCTION postal.trg_reprice_shipment() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
BEGIN
    UPDATE postal.shipments SET price = postal.fn_shipment_price(NEW.shipment_id) WHERE id = NEW.shipment_id;
    RETURN NEW;
END;
$$;

CREATE FUNCTION postal.trg_guard_payment() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
DECLARE
    shipment postal.shipments%ROWTYPE;
    method postal.payment_methods%ROWTYPE;
    paid numeric;
BEGIN
    SELECT * INTO shipment FROM postal.shipments WHERE id = NEW.shipment_id FOR UPDATE;
    IF NOT FOUND OR shipment.deleted_at IS NOT NULL OR shipment.status_id NOT IN (2, 3, 4) THEN
        RAISE EXCEPTION 'Payment requires an active accepted, in-transit or arrived shipment'
            USING ERRCODE = '23514';
    END IF;
    SELECT * INTO method FROM postal.payment_methods WHERE id = NEW.payment_method_id AND is_active FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment method is unavailable' USING ERRCODE = '23514'; END IF;
    NEW.reference := nullif(btrim(NEW.reference), '');
    IF method.requires_reference AND NEW.reference IS NULL THEN
        RAISE EXCEPTION 'The payment method requires a reference' USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(sum(amount), 0) INTO paid FROM postal.payments WHERE shipment_id = NEW.shipment_id;
    IF NEW.amount > shipment.price - paid THEN
        RAISE EXCEPTION 'Payment exceeds the remaining balance %', shipment.price - paid USING ERRCODE = '23514';
    END IF;
    NEW.paid_at := clock_timestamp();
    NEW.recorded_by := postal.fn_actor();
    RETURN NEW;
END;
$$;

CREATE FUNCTION postal.trg_guard_attempt() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
DECLARE shipment postal.shipments%ROWTYPE;
BEGIN
    SELECT * INTO shipment FROM postal.shipments WHERE id = NEW.shipment_id FOR UPDATE;
    IF NOT FOUND OR shipment.deleted_at IS NOT NULL OR shipment.status_id <> 4
        OR NEW.branch_id <> shipment.destination_branch_id THEN
        RAISE EXCEPTION 'Delivery attempts require an arrived shipment at its destination'
            USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(max(attempt_no), 0) + 1 INTO NEW.attempt_no
        FROM postal.delivery_attempts WHERE shipment_id = NEW.shipment_id;
    NEW.attempted_at := clock_timestamp();
    NEW.recorded_by := postal.fn_actor();
    RETURN NEW;
END;
$$;

CREATE FUNCTION postal.trg_complete_delivery() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
BEGIN
    IF NEW.outcome = 'delivered' THEN
        PERFORM set_config('postal.event_note', NEW.note, true);
        UPDATE postal.shipments SET status_id = 5 WHERE id = NEW.shipment_id;
        PERFORM set_config('postal.event_note', '', true);
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION postal.trg_guard_loading() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, postal
AS $$
DECLARE
    run postal.transport_runs%ROWTYPE;
    shipment postal.shipments%ROWTYPE;
    route postal.transport_routes%ROWTYPE;
    capacity numeric;
    current_weight numeric;
    added_weight numeric;
BEGIN
    SELECT * INTO run FROM postal.transport_runs WHERE id = NEW.run_id FOR UPDATE;
    IF NOT FOUND OR run.status <> 'planned' THEN
        RAISE EXCEPTION 'The run must be planned' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO shipment FROM postal.shipments WHERE id = NEW.shipment_id FOR UPDATE;
    SELECT * INTO STRICT route FROM postal.transport_routes WHERE id = run.route_id;
    IF shipment.id IS NULL OR shipment.deleted_at IS NOT NULL OR shipment.status_id <> 2
        OR shipment.origin_branch_id <> route.origin_branch_id
        OR shipment.destination_branch_id <> route.destination_branch_id THEN
        RAISE EXCEPTION 'The accepted shipment must match the route' USING ERRCODE = '23514';
    END IF;
    SELECT max_load_kg INTO capacity FROM postal.vehicles WHERE id = run.vehicle_id AND is_active FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Vehicle is unavailable' USING ERRCODE = '23514'; END IF;
    SELECT coalesce(sum(p.weight_kg), 0) INTO current_weight FROM postal.run_shipments rs
        JOIN postal.parcels p ON p.shipment_id = rs.shipment_id WHERE rs.run_id = NEW.run_id;
    SELECT coalesce(sum(weight_kg), 0) INTO added_weight FROM postal.parcels WHERE shipment_id = NEW.shipment_id;
    IF current_weight + added_weight > capacity THEN
        RAISE EXCEPTION 'Vehicle capacity would be exceeded' USING ERRCODE = '23514';
    END IF;
    NEW.loaded_at := clock_timestamp();
    NEW.loaded_by := postal.fn_actor();
    RETURN NEW;
END;
$$;

CREATE TRIGGER audit_stamp BEFORE INSERT OR UPDATE ON postal.customers FOR EACH ROW EXECUTE FUNCTION postal.trg_stamp_audit();
CREATE TRIGGER audit_stamp BEFORE INSERT OR UPDATE ON postal.addresses FOR EACH ROW EXECUTE FUNCTION postal.trg_stamp_audit();
CREATE TRIGGER audit_stamp BEFORE INSERT OR UPDATE ON postal.branches FOR EACH ROW EXECUTE FUNCTION postal.trg_stamp_audit();
CREATE TRIGGER audit_stamp BEFORE INSERT OR UPDATE ON postal.shipments FOR EACH ROW EXECUTE FUNCTION postal.trg_stamp_audit();
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE ON postal.customers FOR EACH ROW EXECUTE FUNCTION postal.trg_log_audit();
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE ON postal.addresses FOR EACH ROW EXECUTE FUNCTION postal.trg_log_audit();
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE ON postal.branches FOR EACH ROW EXECUTE FUNCTION postal.trg_log_audit();
CREATE TRIGGER audit_log AFTER INSERT OR UPDATE ON postal.shipments FOR EACH ROW EXECUTE FUNCTION postal.trg_log_audit();
CREATE TRIGGER prohibit_delete BEFORE DELETE ON postal.customers FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();
CREATE TRIGGER prohibit_delete BEFORE DELETE ON postal.addresses FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();
CREATE TRIGGER prohibit_delete BEFORE DELETE ON postal.branches FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();
CREATE TRIGGER prohibit_delete BEFORE DELETE ON postal.shipments FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();
CREATE TRIGGER shipment_guard BEFORE INSERT OR UPDATE ON postal.shipments FOR EACH ROW EXECUTE FUNCTION postal.trg_guard_shipment();
CREATE TRIGGER shipment_event AFTER INSERT OR UPDATE ON postal.shipments FOR EACH ROW EXECUTE FUNCTION postal.trg_shipment_event();
CREATE TRIGGER parcel_guard BEFORE INSERT ON postal.parcels FOR EACH ROW EXECUTE FUNCTION postal.trg_guard_parcel();
CREATE TRIGGER parcel_reprice AFTER INSERT ON postal.parcels FOR EACH ROW EXECUTE FUNCTION postal.trg_reprice_shipment();
CREATE TRIGGER parcel_immutable BEFORE UPDATE OR DELETE ON postal.parcels FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();
CREATE TRIGGER payment_guard BEFORE INSERT ON postal.payments FOR EACH ROW EXECUTE FUNCTION postal.trg_guard_payment();
CREATE TRIGGER payment_immutable BEFORE UPDATE OR DELETE ON postal.payments FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();
CREATE TRIGGER event_immutable BEFORE UPDATE OR DELETE ON postal.shipment_events FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();
CREATE TRIGGER audit_immutable BEFORE UPDATE OR DELETE ON postal.audit_log FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();
CREATE TRIGGER attempt_guard BEFORE INSERT ON postal.delivery_attempts FOR EACH ROW EXECUTE FUNCTION postal.trg_guard_attempt();
CREATE TRIGGER attempt_complete AFTER INSERT ON postal.delivery_attempts FOR EACH ROW EXECUTE FUNCTION postal.trg_complete_delivery();
CREATE TRIGGER attempt_immutable BEFORE UPDATE OR DELETE ON postal.delivery_attempts FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();
CREATE TRIGGER loading_guard BEFORE INSERT ON postal.run_shipments FOR EACH ROW EXECUTE FUNCTION postal.trg_guard_loading();
CREATE TRIGGER loading_immutable BEFORE UPDATE OR DELETE ON postal.run_shipments FOR EACH ROW EXECUTE FUNCTION postal.trg_block_mutation();

CREATE PROCEDURE postal.create_customer(p_id uuid, p_full_name text, p_email text, p_phone text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    INSERT INTO postal.customers (id, full_name, email, phone)
        VALUES (p_id, btrim(p_full_name), lower(btrim(p_email)), btrim(p_phone));
END;
$$;

CREATE PROCEDURE postal.update_customer(p_id uuid, p_full_name text, p_email text, p_phone text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    UPDATE postal.customers SET full_name = btrim(p_full_name), email = lower(btrim(p_email)), phone = btrim(p_phone)
        WHERE id = p_id AND deleted_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active customer not found' USING ERRCODE = 'P0002'; END IF;
END;
$$;

CREATE PROCEDURE postal.delete_customer(p_id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    UPDATE postal.customers SET deleted_at = clock_timestamp() WHERE id = p_id AND deleted_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active customer not found' USING ERRCODE = 'P0002'; END IF;
END;
$$;

CREATE PROCEDURE postal.restore_customer(p_id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    UPDATE postal.customers SET deleted_at = NULL, deleted_by = NULL WHERE id = p_id AND deleted_at IS NOT NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deleted customer not found' USING ERRCODE = 'P0002'; END IF;
END;
$$;

CREATE PROCEDURE postal.create_shipment(
    p_id uuid, p_tracking_number text, p_sender_id uuid, p_recipient_id uuid,
    p_origin_branch_id integer, p_destination_branch_id integer,
    p_service_type_id integer, p_declared_value numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    INSERT INTO postal.shipments (id, tracking_number, sender_id, recipient_id, origin_branch_id,
        destination_branch_id, service_type_id, declared_value)
    VALUES (p_id, upper(btrim(p_tracking_number)), p_sender_id, p_recipient_id, p_origin_branch_id,
        p_destination_branch_id, p_service_type_id, p_declared_value);
END;
$$;

CREATE PROCEDURE postal.delete_address(p_id integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    PERFORM id FROM postal.addresses WHERE id = p_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active address not found' USING ERRCODE = 'P0002'; END IF;
    IF EXISTS (SELECT 1 FROM postal.branches WHERE address_id = p_id AND deleted_at IS NULL) THEN
        RAISE EXCEPTION 'Delete the active branch before its address' USING ERRCODE = '23514';
    END IF;
    UPDATE postal.addresses SET deleted_at = clock_timestamp() WHERE id = p_id;
END;
$$;

CREATE PROCEDURE postal.restore_address(p_id integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    UPDATE postal.addresses SET deleted_at = NULL, deleted_by = NULL WHERE id = p_id AND deleted_at IS NOT NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deleted address not found' USING ERRCODE = 'P0002'; END IF;
END;
$$;

CREATE PROCEDURE postal.delete_branch(p_id integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    PERFORM id FROM postal.branches WHERE id = p_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active branch not found' USING ERRCODE = 'P0002'; END IF;
    IF EXISTS (SELECT 1 FROM postal.shipments WHERE deleted_at IS NULL AND status_id NOT IN (5, 6)
        AND (origin_branch_id = p_id OR destination_branch_id = p_id)) THEN
        RAISE EXCEPTION 'The branch still has unfinished shipments' USING ERRCODE = '23514';
    END IF;
    UPDATE postal.branches SET deleted_at = clock_timestamp() WHERE id = p_id;
END;
$$;

CREATE PROCEDURE postal.restore_branch(p_id integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    PERFORM a.id FROM postal.addresses a JOIN postal.branches b ON b.address_id = a.id
        WHERE b.id = p_id AND b.deleted_at IS NOT NULL AND a.deleted_at IS NULL FOR SHARE OF a;
    IF NOT FOUND THEN
        IF EXISTS (SELECT 1 FROM postal.branches WHERE id = p_id AND deleted_at IS NOT NULL) THEN
            RAISE EXCEPTION 'Restore the branch address first' USING ERRCODE = '23514';
        END IF;
        RAISE EXCEPTION 'Deleted branch not found' USING ERRCODE = 'P0002';
    END IF;
    UPDATE postal.branches SET deleted_at = NULL, deleted_by = NULL WHERE id = p_id AND deleted_at IS NOT NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deleted branch not found' USING ERRCODE = 'P0002'; END IF;
END;
$$;

CREATE PROCEDURE postal.add_parcel(
    p_id uuid, p_shipment_id uuid, p_description text, p_weight_kg numeric,
    p_length_cm numeric, p_width_cm numeric, p_height_cm numeric)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    INSERT INTO postal.parcels (id, shipment_id, description, weight_kg, length_cm, width_cm, height_cm)
    VALUES (p_id, p_shipment_id, btrim(p_description), p_weight_kg, p_length_cm, p_width_cm, p_height_cm);
END;
$$;

CREATE PROCEDURE postal.change_status(p_shipment_id uuid, p_status_id integer, p_note text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    PERFORM set_config('postal.event_note', coalesce(btrim(p_note), ''), true);
    UPDATE postal.shipments SET status_id = p_status_id WHERE id = p_shipment_id AND deleted_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active shipment not found' USING ERRCODE = 'P0002'; END IF;
    PERFORM set_config('postal.event_note', '', true);
END;
$$;

CREATE PROCEDURE postal.delete_shipment(p_id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    UPDATE postal.shipments SET deleted_at = clock_timestamp() WHERE id = p_id AND deleted_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active shipment not found' USING ERRCODE = 'P0002'; END IF;
END;
$$;

CREATE PROCEDURE postal.restore_shipment(p_id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    PERFORM postal.fn_actor();
    UPDATE postal.shipments SET deleted_at = NULL, deleted_by = NULL WHERE id = p_id AND deleted_at IS NOT NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Deleted shipment not found' USING ERRCODE = 'P0002'; END IF;
END;
$$;

CREATE PROCEDURE postal.record_payment(
    p_id uuid, p_shipment_id uuid, p_amount numeric, p_payment_method_id integer, p_reference text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    INSERT INTO postal.payments (id, shipment_id, amount, payment_method_id, reference)
    VALUES (p_id, p_shipment_id, p_amount, p_payment_method_id, p_reference);
END;
$$;

CREATE PROCEDURE postal.record_delivery_attempt(
    p_id uuid, p_shipment_id uuid, p_branch_id integer, p_outcome text, p_note text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    INSERT INTO postal.delivery_attempts (id, shipment_id, branch_id, attempt_no, outcome, note)
    VALUES (p_id, p_shipment_id, p_branch_id, 1, p_outcome, btrim(p_note));
END;
$$;

CREATE PROCEDURE postal.assign_to_run(p_run_id uuid, p_shipment_id uuid)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, postal
AS $$
BEGIN
    INSERT INTO postal.run_shipments (run_id, shipment_id) VALUES (p_run_id, p_shipment_id);
END;
$$;

CREATE VIEW postal.v_customers_all AS
SELECT id, full_name, email, phone, created_at, updated_at, updated_by, deleted_at, deleted_by
FROM postal.customers;

CREATE VIEW postal.v_customers AS
SELECT id, full_name, email, phone, created_at, updated_at, updated_by
FROM postal.v_customers_all WHERE deleted_at IS NULL;

CREATE VIEW postal.v_shipments_all AS
SELECT s.id, s.tracking_number, s.sender_id, sender.full_name AS sender_name,
    s.recipient_id, recipient.full_name AS recipient_name,
    s.origin_branch_id, origin.name AS origin_branch_name,
    s.destination_branch_id, destination.name AS destination_branch_name,
    s.service_type_id, service.name AS service_name, s.status_id, status.code AS status_code,
    s.declared_value, s.price, coalesce(pc.parcel_count, 0::bigint) AS parcel_count,
    coalesce(pc.total_weight_kg, 0::numeric) AS total_weight_kg,
    coalesce(pm.paid_amount, 0::numeric) AS paid_amount,
    s.price - coalesce(pm.paid_amount, 0::numeric) AS balance,
    s.created_at, s.updated_at, s.updated_by, s.deleted_at, s.deleted_by
FROM postal.shipments s
JOIN postal.customers sender ON sender.id = s.sender_id
JOIN postal.customers recipient ON recipient.id = s.recipient_id
JOIN postal.branches origin ON origin.id = s.origin_branch_id
JOIN postal.branches destination ON destination.id = s.destination_branch_id
JOIN postal.service_types service ON service.id = s.service_type_id
JOIN postal.shipment_statuses status ON status.id = s.status_id
LEFT JOIN (SELECT shipment_id, count(*) AS parcel_count, sum(weight_kg) AS total_weight_kg
    FROM postal.parcels GROUP BY shipment_id) pc ON pc.shipment_id = s.id
LEFT JOIN (SELECT shipment_id, sum(amount) AS paid_amount FROM postal.payments GROUP BY shipment_id) pm
    ON pm.shipment_id = s.id;

CREATE VIEW postal.v_shipments AS
SELECT id, tracking_number, sender_id, sender_name, recipient_id, recipient_name,
    origin_branch_id, origin_branch_name, destination_branch_id, destination_branch_name,
    service_type_id, service_name, status_id, status_code, declared_value, price,
    parcel_count, total_weight_kg, paid_amount, balance, created_at, updated_at, updated_by
FROM postal.v_shipments_all WHERE deleted_at IS NULL;

CREATE VIEW postal.v_parcels AS
SELECT p.id, p.shipment_id, p.description, p.weight_kg, p.length_cm, p.width_cm, p.height_cm
FROM postal.parcels p JOIN postal.shipments s ON s.id = p.shipment_id WHERE s.deleted_at IS NULL;

CREATE VIEW postal.v_payments AS
SELECT p.id, p.shipment_id, p.amount, p.payment_method_id, m.name AS method_name,
    p.reference, p.paid_at, p.recorded_by
FROM postal.payments p JOIN postal.payment_methods m ON m.id = p.payment_method_id
JOIN postal.shipments s ON s.id = p.shipment_id WHERE s.deleted_at IS NULL;

CREATE VIEW postal.v_tracking_history AS
SELECT e.id AS event_id, e.shipment_id, s.tracking_number, e.status_id, st.code AS status_code,
    e.branch_id, b.name AS branch_name, e.note, e.occurred_at, e.recorded_by
FROM postal.shipment_events e JOIN postal.shipments s ON s.id = e.shipment_id
JOIN postal.shipment_statuses st ON st.id = e.status_id
JOIN postal.branches b ON b.id = e.branch_id WHERE s.deleted_at IS NULL;

CREATE VIEW postal.v_audit_log AS
SELECT id, entity_name, entity_id, operation, changed_at, changed_by, old_data, new_data FROM postal.audit_log;

CREATE VIEW postal.v_options AS
SELECT 'branch'::text AS option_type, b.id, b.code, b.name FROM postal.branches b
    JOIN postal.addresses a ON a.id = b.address_id
    WHERE b.deleted_at IS NULL AND b.is_operational AND a.deleted_at IS NULL
UNION ALL SELECT 'service', id, code, name FROM postal.service_types WHERE is_active
UNION ALL SELECT 'status', id, code, name FROM postal.shipment_statuses
UNION ALL SELECT 'payment_method', id, code, name FROM postal.payment_methods WHERE is_active;

CREATE VIEW postal.v_branch_directory AS
SELECT b.id, b.code, b.name, c.name AS city, a.street, a.building, a.postal_code
FROM postal.branches b JOIN postal.addresses a ON a.id = b.address_id
JOIN postal.cities c ON c.id = a.city_id
WHERE b.deleted_at IS NULL AND b.is_operational AND a.deleted_at IS NULL;

CREATE VIEW postal.v_transport_manifest AS
SELECT r.id AS run_id, rt.name AS route_name, v.registration_number, r.departure_at, r.status,
    s.id AS shipment_id, s.tracking_number, sum(p.weight_kg) AS weight_kg
FROM postal.transport_runs r JOIN postal.transport_routes rt ON rt.id = r.route_id
JOIN postal.vehicles v ON v.id = r.vehicle_id JOIN postal.run_shipments rs ON rs.run_id = r.id
JOIN postal.shipments s ON s.id = rs.shipment_id JOIN postal.parcels p ON p.shipment_id = s.id
WHERE s.deleted_at IS NULL
GROUP BY r.id, rt.name, v.registration_number, s.id;

CREATE VIEW postal.v_tariffs AS
SELECT t.id, t.service_type_id, s.name AS service_name, t.base_price, t.price_per_kg,
    t.insurance_rate, t.max_weight_kg
FROM postal.tariffs t JOIN postal.service_types s ON s.id = t.service_type_id WHERE s.is_active;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA postal FROM PUBLIC;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA postal FROM PUBLIC;
