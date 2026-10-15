INSERT INTO postal.app_users (id, username, full_name) VALUES
('00000000-0000-0000-0000-000000000001', 'operator', 'Оператор відділення'),
('00000000-0000-0000-0000-000000000002', 'supervisor', 'Керівник зміни');

INSERT INTO postal.countries (id, code, name) VALUES (1, 'UA', 'Україна');
INSERT INTO postal.cities (id, country_id, name) VALUES
(1, 1, 'Київ'), (2, 1, 'Львів'), (3, 1, 'Дніпро');

INSERT INTO postal.addresses (id, city_id, street, building, postal_code, created_by, updated_by) VALUES
(1, 1, 'вул. Хрещатик', '22', '01001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
(2, 2, 'вул. Городоцька', '15', '79007', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
(3, 3, 'просп. Дмитра Яворницького', '45', '49000', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001');

INSERT INTO postal.branches (id, code, name, address_id, created_by, updated_by) VALUES
(1, 'KYIV01', 'Київ, відділення №1', 1, '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
(2, 'LVIV01', 'Львів, відділення №1', 2, '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
(3, 'DNIPRO01', 'Дніпро, відділення №1', 3, '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001');

INSERT INTO postal.customers (id, full_name, email, phone, created_by, updated_by) VALUES
('00000000-0000-0000-0000-000000000101', 'Олена Коваль', 'olena.koval@example.com', '+380501110101', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000102', 'Андрій Мельник', 'andrii.melnyk@example.com', '+380671110102', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000103', 'Марія Бондар', 'mariia.bondar@example.com', '+380931110103', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001');

INSERT INTO postal.service_types (id, code, name) VALUES
(1, 'standard', 'Стандарт'), (2, 'express', 'Експрес');
INSERT INTO postal.shipment_statuses (id, code, name, is_terminal) VALUES
(1, 'draft', 'Чернетка', false), (2, 'accepted', 'Прийнято', false),
(3, 'in_transit', 'У дорозі', false), (4, 'arrived', 'Прибуло у відділення', false),
(5, 'delivered', 'Видано одержувачу', true), (6, 'cancelled', 'Скасовано', true);
INSERT INTO postal.tariffs (id, service_type_id, base_price, price_per_kg, insurance_rate, max_weight_kg) VALUES
(1, 1, 50, 20, 0.01, 100), (2, 2, 80, 30, 0.01, 50);
INSERT INTO postal.payment_methods (id, code, name, requires_reference) VALUES
(1, 'cash', 'Готівка', false), (2, 'card', 'Банківська картка', true);

INSERT INTO postal.shipments
    (id, tracking_number, sender_id, recipient_id, origin_branch_id, destination_branch_id,
     service_type_id, status_id, declared_value, price, created_by, updated_by)
VALUES
('00000000-0000-0000-0000-000000000201', 'PS0000000001', '00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000102', 1, 2, 1, 2, 500, 95, '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000202', 'PS0000000002', '00000000-0000-0000-0000-000000000102', '00000000-0000-0000-0000-000000000101', 2, 1, 1, 5, 0, 70, '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000203', 'PS0000000003', '00000000-0000-0000-0000-000000000103', '00000000-0000-0000-0000-000000000102', 1, 3, 2, 1, 1000, 210, '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001');

INSERT INTO postal.parcels (id, shipment_id, description, weight_kg, length_cm, width_cm, height_cm, created_by) VALUES
('00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000201', 'Книжки', 1.2, 30, 20, 10, '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000201', 'Канцелярське приладдя', 0.8, 20, 15, 10, '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000303', '00000000-0000-0000-0000-000000000202', 'Документи', 0.5, 30, 22, 2, '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000304', '00000000-0000-0000-0000-000000000203', 'Побутові речі', 3.4, 40, 30, 25, '00000000-0000-0000-0000-000000000001');

INSERT INTO postal.shipment_events (id, shipment_id, status_id, branch_id, note, occurred_at, recorded_by) VALUES
('00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000201', 1, 1, 'Створено відправлення', now() - interval '2 hours', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000201', 2, 1, 'Прийнято два місця', now() - interval '1 hour', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000403', '00000000-0000-0000-0000-000000000202', 1, 2, 'Створено відправлення', now() - interval '3 days', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000404', '00000000-0000-0000-0000-000000000202', 2, 2, 'Прийнято у Львові', now() - interval '3 days' + interval '1 hour', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000405', '00000000-0000-0000-0000-000000000202', 3, 2, 'Відправлено до Києва', now() - interval '2 days', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000406', '00000000-0000-0000-0000-000000000202', 4, 1, 'Прибуло до Києва', now() - interval '1 day', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000407', '00000000-0000-0000-0000-000000000202', 5, 1, 'Видано одержувачу', now() - interval '20 hours', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000408', '00000000-0000-0000-0000-000000000203', 1, 1, 'Чернетка для оформлення', now(), '00000000-0000-0000-0000-000000000001');

INSERT INTO postal.payments (id, shipment_id, amount, payment_method_id, reference, recorded_by) VALUES
('00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000201', 95, 2, 'DEMO-CARD-0001', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000502', '00000000-0000-0000-0000-000000000202', 70, 1, NULL, '00000000-0000-0000-0000-000000000001');
INSERT INTO postal.delivery_attempts (id, shipment_id, branch_id, attempt_no, outcome, note, recorded_by) VALUES
('00000000-0000-0000-0000-000000000701', '00000000-0000-0000-0000-000000000202', 1, 1, 'delivered', 'Отримувач забрав документи у відділенні', '00000000-0000-0000-0000-000000000001');

INSERT INTO postal.vehicles (id, registration_number, max_load_kg) VALUES
(1, 'AA1234KA', 1500), (2, 'BC5678HC', 1000);
INSERT INTO postal.transport_routes (id, name, origin_branch_id, destination_branch_id) VALUES
(1, 'Київ — Львів', 1, 2), (2, 'Львів — Київ', 2, 1), (3, 'Київ — Дніпро', 1, 3);
INSERT INTO postal.route_stops (id, route_id, branch_id, stop_order) VALUES
(1, 1, 1, 1), (2, 1, 2, 2), (3, 2, 2, 1), (4, 2, 1, 2), (5, 3, 1, 1), (6, 3, 3, 2);
INSERT INTO postal.transport_runs (id, route_id, vehicle_id, departure_at, arrival_at, status, created_by) VALUES
('00000000-0000-0000-0000-000000000601', 1, 1, now() + interval '2 hours', NULL, 'planned', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000602', 2, 2, now() - interval '2 days', now() - interval '1 day', 'completed', '00000000-0000-0000-0000-000000000001');
INSERT INTO postal.run_shipments (run_id, shipment_id, loaded_by) VALUES
('00000000-0000-0000-0000-000000000601', '00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000001'),
('00000000-0000-0000-0000-000000000602', '00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000001');

INSERT INTO postal.audit_log (entity_name, entity_id, operation, changed_at, changed_by, new_data)
SELECT 'addresses', id::text, 'insert', created_at, created_by, to_jsonb(a) FROM postal.addresses a
UNION ALL SELECT 'branches', id::text, 'insert', created_at, created_by, to_jsonb(b) FROM postal.branches b
UNION ALL SELECT 'customers', id::text, 'insert', created_at, created_by, to_jsonb(c) FROM postal.customers c
UNION ALL SELECT 'shipments', id::text, 'insert', created_at, created_by, to_jsonb(s) FROM postal.shipments s;

SELECT setval(pg_get_serial_sequence('postal.countries', 'id'), (SELECT max(id) FROM postal.countries));
SELECT setval(pg_get_serial_sequence('postal.cities', 'id'), (SELECT max(id) FROM postal.cities));
SELECT setval(pg_get_serial_sequence('postal.addresses', 'id'), (SELECT max(id) FROM postal.addresses));
SELECT setval(pg_get_serial_sequence('postal.branches', 'id'), (SELECT max(id) FROM postal.branches));
SELECT setval(pg_get_serial_sequence('postal.service_types', 'id'), (SELECT max(id) FROM postal.service_types));
SELECT setval(pg_get_serial_sequence('postal.tariffs', 'id'), (SELECT max(id) FROM postal.tariffs));
SELECT setval(pg_get_serial_sequence('postal.payment_methods', 'id'), (SELECT max(id) FROM postal.payment_methods));
SELECT setval(pg_get_serial_sequence('postal.vehicles', 'id'), (SELECT max(id) FROM postal.vehicles));
SELECT setval(pg_get_serial_sequence('postal.transport_routes', 'id'), (SELECT max(id) FROM postal.transport_routes));
SELECT setval(pg_get_serial_sequence('postal.route_stops', 'id'), (SELECT max(id) FROM postal.route_stops));
