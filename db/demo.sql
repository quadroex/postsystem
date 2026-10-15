BEGIN;
CALL postal.set_actor('00000000-0000-0000-0000-000000000001');
CALL postal.create_customer('d0000000-0000-0000-0000-000000000101', 'Ірина Савчук', 'iryna.savchuk@example.com', '+380501230101');
CALL postal.create_customer('d0000000-0000-0000-0000-000000000102', 'Тарас Шевчук', 'taras.shevchuk@example.com', '+380671230102');
CALL postal.create_shipment('d0000000-0000-0000-0000-000000000201', 'PSDEMO000001',
    'd0000000-0000-0000-0000-000000000101', 'd0000000-0000-0000-0000-000000000102', 1, 2, 1, 1500);
CALL postal.add_parcel('d0000000-0000-0000-0000-000000000301', 'd0000000-0000-0000-0000-000000000201', 'Книжки', 1.5, 30, 20, 12);
CALL postal.add_parcel('d0000000-0000-0000-0000-000000000302', 'd0000000-0000-0000-0000-000000000201', 'Настільна гра', 1, 25, 25, 8);
CALL postal.change_status('d0000000-0000-0000-0000-000000000201', 2, 'Прийнято два місця');
CALL postal.record_payment('d0000000-0000-0000-0000-000000000501', 'd0000000-0000-0000-0000-000000000201', 125, 2, 'DEMO-CARD-0003');
CALL postal.change_status('d0000000-0000-0000-0000-000000000201', 3, 'Відправлено до Львова');
CALL postal.change_status('d0000000-0000-0000-0000-000000000201', 4, 'Прибуло у відділення №1');
CALL postal.record_delivery_attempt('d0000000-0000-0000-0000-000000000701', 'd0000000-0000-0000-0000-000000000201', 2, 'delivered', 'Видано Тарасу Шевчуку');

CALL postal.set_actor('00000000-0000-0000-0000-000000000002');
CALL postal.update_customer('d0000000-0000-0000-0000-000000000101', 'Ірина Савчук', 'iryna.savchuk@example.com', '+380931230101');
CALL postal.delete_customer('d0000000-0000-0000-0000-000000000101');
CALL postal.restore_customer('d0000000-0000-0000-0000-000000000101');
CALL postal.create_customer('d0000000-0000-0000-0000-000000000103', 'Архівний клієнт', 'archived.customer@example.com', '+380501230103');
CALL postal.delete_customer('d0000000-0000-0000-0000-000000000103');
COMMIT;

SELECT tracking_number, status_code, parcel_count, total_weight_kg, price, paid_amount, balance
FROM postal.v_shipments WHERE tracking_number = 'PSDEMO000001';
SELECT status_code, branch_name, note, occurred_at FROM postal.v_tracking_history
WHERE tracking_number = 'PSDEMO000001' ORDER BY occurred_at;
SELECT operation, changed_at, changed_by FROM postal.v_audit_log
WHERE entity_name = 'customers' AND entity_id = 'd0000000-0000-0000-0000-000000000101' ORDER BY id;
