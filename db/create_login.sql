\set ON_ERROR_STOP on
\getenv app_password POSTSYSTEM_APP_PASSWORD
DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'postsystem_local') THEN
        RAISE EXCEPTION 'Login postsystem_local already exists; its password was preserved';
    END IF;
END;
$$;
CREATE ROLE postsystem_local LOGIN PASSWORD :'app_password';
GRANT postsystem_app TO postsystem_local;
