SELECT c.relname AS index_name, am.amname AS index_type
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_am am ON am.oid = c.relam
WHERE n.nspname = 'postal'
ORDER BY am.amname, c.relname;

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM postal.v_shipments WHERE tracking_number = 'PS0000000001';

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, full_name FROM postal.v_customers
WHERE to_tsvector('simple', full_name || ' ' || email)
    @@ plainto_tsquery('simple', 'Коваль');

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, entity_id, operation FROM postal.v_audit_log
WHERE new_data @> '{"status_id": 2}'::jsonb;
