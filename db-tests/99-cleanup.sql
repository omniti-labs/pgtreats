BEGIN;

    SELECT execute('ALTER DATABASE ' || quote_ident( current_database() ) || ' RESET search_path');

    SET client_min_messages = WARNING;
    DROP SCHEMA pgtap cascade;

COMMIT;
