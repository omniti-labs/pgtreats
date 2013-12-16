CREATE OR replace function test_correct_relfrozenxid(
    IN   p_table        regclass,
    IN   p_results      TEXT   DEFAULT  NULL,
    OUT  table_name     TEXT,
    OUT  scanned_pages  INT8,
    OUT  bad_pages      INT8,
    OUT  scanned_rows   INT8,
    OUT  bad_rows       INT8
) RETURNS record as $$
DECLARE
    r_class        record;
    page_no        INT4;
    temprec        record;
    max_age        INT4;
    v_current_xid  xid;
BEGIN

    -- verify that results table exists, if we should use it
    IF p_results IS NOT NULL THEN
        BEGIN
            SELECT oid INTO temprec FROM pg_class WHERE oid = p_results::regclass;
        EXCEPTION WHEN undefined_table THEN
            execute 'CREATE TABLE ' || p_results || ' as
                SELECT ''pg_class''::regclass as table_name, 0::INT8 as page_no, ''0''::xid as relfrozenxid, ''0''::xid as current_xid, i.*, 0::INT4 as check_status, h.*
                FROM heap_page_items(get_raw_page(''pg_catalog.pg_class'', 0)) as i,
                page_header(get_raw_page(''pg_catalog.pg_class'', 0)) as h
                LIMIT 0';
        END;
    END IF;

    -- get base relation data
    SELECT n.nspname, c.relname, pg_relation_size(c.oid) / current_setting('block_size')::INT4 as relpages, c.relfrozenxid INTO r_class
        FROM pg_class c join pg_namespace n on c.relnamespace = n.oid
        WHERE c.relkind = 'r' AND c.oid = p_table;
    IF NOT FOUND THEN raise exception 'No such table: %', p_table; END IF;

    table_name := format('%I.%I', r_class.nspname, r_class.relname);

    -- 5 million is just some cutoff value to accomodate rows that are currently being inserted/updated/deleted.
    -- this value was suggested to me BY Andres Freund, and since he originally found the bug, I tend to trust him
    v_current_xid := (txid_current() + 5000000)::TEXT::xid;

    scanned_pages := r_class.relpages;
    bad_pages := 0;
    scanned_rows := 0;
    bad_rows := 0;

    -- Iterate over all pages of relation...
    for page_no in SELECT generate_series(0, r_class.relpages - 1) loop

        -- check how many *bad* rows are there in this page

        IF p_results IS NULL THEN
            -- we're not collecting bad rows
            SELECT count(*) as all_rows,
                sum(
                    case when xmin_xmax_status( t_xmin, t_xmax, r_class.relfrozenxid, v_current_xid ) > 0 THEN 1 ELSE 0 END
                ) as bad_rows
                INTO temprec
                FROM heap_page_items(get_raw_page(table_name, page_no));
        ELSE
            -- we are collecting bad rows, so we should get them, and some stats ...
            EXECUTE '
                with page as (
                    SELECT get_raw_page( $1, $2 ) as p
                ), all_rows_in_page as (
                    SELECT *, xmin_xmax_status( t_xmin, t_xmax, $3, $4 ) as check_status
                    FROM heap_page_items((SELECT p FROM page))
                ), insert_bad_rows as (
                    INSERT INTO ' || p_results || ' SELECT $1, $2, $3, $4, r.*, h.* FROM all_rows_in_page r, (SELECT page_header( p ) FROM page ) as h WHERE r.check_status > 0
                )
                SELECT
                    count(*) as all_rows,
                    sum( case when check_status > 0 THEN 1 ELSE 0 END) as bad_rows
                FROM all_rows_in_page
            ' INTO temprec USING table_name, page_no, r_class.relfrozenxid, v_current_xid;
        END IF;

        -- update statistics based on data fetched from check query above
        scanned_rows := scanned_rows + temprec.all_rows;

        IF temprec.bad_rows > 0 THEN
            raise notice 'Found bad rows (%) in TABLE (%) page (%)', temprec.bad_rows, table_name, page_no;
            bad_rows  := bad_rows + temprec.bad_rows;
            bad_pages := bad_pages + 1;
        END IF;

    END LOOP;
    RETURN;
END;
$$ language plpgsql;


