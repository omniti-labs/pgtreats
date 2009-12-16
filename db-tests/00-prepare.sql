BEGIN;

-- This is basically CREATE LANGUAGE IF NOT EXISTS - vide http://andreas.scherbaum.la/blog/archives/346-create-language-if-not-exist.html
    CREATE OR REPLACE FUNCTION public.create_plpgsql_language () RETURNS setof TEXT AS $$ CREATE LANGUAGE plpgsql; SELECT 'x'::TEXT WHERE 1=0;$$ LANGUAGE 'sql';
    SELECT public.create_plpgsql_language () WHERE NOT exists (SELECT * FROM pg_language WHERE lanname='plpgsql');
    DROP FUNCTION public.create_plpgsql_language ();
-- This is basically CREATE LANGUAGE IF NOT EXISTS - vide http://andreas.scherbaum.la/blog/archives/346-create-language-if-not-exist.html

    CREATE SCHEMA pgtap;
    SET search_path TO pgtap, public;
    \i /home/pgdba/work-8.4.1/share/postgresql/contrib/pgtap.sql

    CREATE OR REPLACE FUNCTION execute(TEXT) RETURNS void as $$BEGIN execute $1; END;$$ language plpgsql;
    SELECT execute('ALTER DATABASE ' || quote_ident( current_database() ) || ' SET search_path = pgtap, public');

COMMIT;
