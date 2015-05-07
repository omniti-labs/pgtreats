CREATE OR REPLACE FUNCTION pgcozy_init () RETURNS void AS $$
BEGIN
IF (select count(*) from pg_extension where extname in ('pg_buffercache','pg_prewarm')) = 2
	THEN
	RAISE NOTICE 'pg_buffercache and pg_prewarm exists continuing...';
	drop schema IF EXISTS pgcozy cascade;
	create schema pgcozy;
	create table pgcozy.snapshots (id serial,snapshot_date date, snapshot jsonb);
	create unique index snapshots_uniq_idx on pgcozy.snapshots (id, snapshot_date);
	drop type if exists cozy_type;
	create type cozy_type as (table_name text,block_no int, popularity int);
	RAISE NOTICE 'Everything is done, check pgcozy schema for more details.';
ELSE    
	RAISE EXCEPTION 'pgcozy needs pg_buffercache and pg_prewarm extensions , install them and run pgcozy_init again.';
END IF;
END
$$ LANGUAGE 'plpgsql' ;


CREATE OR REPLACE FUNCTION pgcozy_snapshot (a_pop int) RETURNS void AS $$
BEGIN
IF      a_pop >= 1 and a_pop <= 5 
        THEN
        RAISE NOTICE 'Getting a new snapshot...';
        insert into pgcozy.snapshots (snapshot_date,snapshot)
                select now()::date, array_to_json(array_agg(row_to_json(r)))::jsonb FROM (
                SELECT n.nspname||'.'|| c.relname as table_name ,b.relblocknumber as block_no,b.usagecount as popularity
                FROM pg_class c, pg_buffercache b , pg_database d , pg_namespace n
                where b.relfilenode = c.relfilenode
                and b.reldatabase=d.oid
                and n.oid = c.relnamespace
                and c.relkind in ('i','r')
                and b.isdirty='f'
                and b.usagecount >= a_pop
                and n.nspname !='pg_catalog' ) r ;
ELSIF   a_pop=0
        THEN
	RAISE NOTICE 'Getting a new snapshot of all contents of pg_buffercache...';
        insert into pgcozy.snapshots (snapshot_date,snapshot)
                select now()::date, array_to_json(array_agg(row_to_json(r)))::jsonb FROM (
                SELECT n.nspname||'.'|| c.relname as table_name ,b.relblocknumber as block_no,b.usagecount as popularity
                FROM pg_class c, pg_buffercache b , pg_database d , pg_namespace n
                where b.relfilenode = c.relfilenode
                and b.reldatabase=d.oid
                and n.oid = c.relnamespace
                and c.relkind in ('i','r')
                and b.isdirty='f'
                and n.nspname !='pg_catalog' ) r ;
RAISE NOTICE 'Snapshot Taken..';
ELSE    RAISE EXCEPTION 'popularity should be between 0 and 5 --> %', a_pop
      USING HINT = 'Usage pgcozy_snapshot popularity 0-5, 0 snapshots all contents of pg_buffercache';
END IF;

END
$$ LANGUAGE 'plpgsql' ;



CREATE OR REPLACE FUNCTION pgcozy_warm (snapshot_id int) RETURNS void AS $$
DECLARE
        v_rec record;
BEGIN
IF      snapshot_id >0 
        THEN
		RAISE NOTICE 'warming up according to the snapshot... --> %', snapshot_id;
        FOR v_rec IN
                select table_name,block_no,popularity
                from jsonb_populate_recordset( NULL::cozy_type,(select snapshot from pgcozy.snapshots where pgcozy.snapshots.id = snapshot_id))
        LOOP
	RAISE NOTICE 'Warming up % ...', quote_literal(v_rec.table_name) ||' block '|| v_rec.block_no ;
	EXECUTE 'select pg_prewarm ('|| quote_literal(v_rec.table_name)||','||quote_literal('buffer')||','||quote_literal('main') ||','||v_rec.block_no||','||v_rec.block_no||')';
	end LOOP;
	RAISE NOTICE 'Done Warming up snapshot_id -->%', snapshot_id;
ELSIF   snapshot_id = 0
        THEN
		RAISE NOTICE 'warming up acording to the latest pgcozy snapshot...';
        FOR v_rec IN
                select table_name,block_no,popularity
                from jsonb_populate_recordset( NULL::cozy_type,
                (select snapshot from pgcozy.snapshots where pgcozy.snapshots.id = (select max(id) from pgcozy.snapshots)
                )), pgcozy.snapshots where id = (select max(id) from pgcozy.snapshots)
        LOOP
RAISE NOTICE 'Warming up % ...', quote_literal(v_rec.table_name) ||' block '|| v_rec.block_no ;
EXECUTE 'select pg_prewarm ('|| quote_literal(v_rec.table_name)||','||quote_literal('buffer')||','||quote_literal('main') ||','||v_rec.block_no||','||v_rec.block_no||')';
end LOOP;
RAISE NOTICE 'Done Warming up according to the latest snapshot...';
ELSE    RAISE EXCEPTION 'Nonexistent snapshot_id --> %', snapshot_id
      USING HINT = 'Usage pgcozy_warm (snapshot_id , 0 if you want to warm according to the latest snapshot';
END IF;
END
$$ LANGUAGE 'plpgsql' ;
































