SELECT table_name FROM information_schema.tables
WHERE table_schema = 'postal' AND table_type = 'BASE TABLE' ORDER BY table_name;

SELECT CASE p.prokind WHEN 'p' THEN 'procedure' ELSE 'function' END AS object_type,
    p.proname AS object_name, pg_get_function_identity_arguments(p.oid) AS arguments
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'postal' ORDER BY object_type, object_name;

SELECT event_object_table AS table_name, trigger_name, event_manipulation
FROM information_schema.triggers WHERE trigger_schema = 'postal'
ORDER BY table_name, trigger_name, event_manipulation;

SELECT table_name AS view_name FROM information_schema.views
WHERE table_schema = 'postal' ORDER BY table_name;

SELECT tracking_number, sender_name, recipient_name, status_code, price, paid_amount, balance
FROM postal.v_shipments ORDER BY tracking_number;
