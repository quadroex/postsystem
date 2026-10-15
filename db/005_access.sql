DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'postsystem_app') THEN
        CREATE ROLE postsystem_app NOLOGIN;
    END IF;
END;
$$;

REVOKE ALL ON SCHEMA postal FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA postal FROM PUBLIC, postsystem_app;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA postal FROM PUBLIC, postsystem_app;
REVOKE ALL ON ALL ROUTINES IN SCHEMA postal FROM PUBLIC, postsystem_app;
GRANT USAGE ON SCHEMA postal TO postsystem_app;

DO $$
DECLARE item record;
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO postsystem_app', current_database());
    FOR item IN SELECT schemaname, viewname FROM pg_views WHERE schemaname = 'postal'
    LOOP
        EXECUTE format('GRANT SELECT ON %I.%I TO postsystem_app', item.schemaname, item.viewname);
    END LOOP;
    FOR item IN
        SELECT p.oid::regprocedure AS signature
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'postal' AND p.prokind = 'p'
    LOOP
        EXECUTE format('GRANT EXECUTE ON PROCEDURE %s TO postsystem_app', item.signature);
    END LOOP;
END;
$$;
