CREATE TYPE _sol_map_data AS (
  addr numeric,
  size bigint,
  resident bigint,
  anon bigint,
  locked bigint,
  is_readable boolean,
  is_writable boolean,
  is_executable boolean,
  is_shared boolean,
  is_noreserve boolean,
  is_reserve1 boolean,
  map_type varchar,
  file varchar
);

CREATE OR REPLACE FUNCTION sol_pmap_pid(integer)
    RETURNS SETOF _sol_map_data
--    AS '$libdir/pgsol10', 'sol_pmap_pid'
    AS '/home/jesus/pgsoltools/libpgsol10', 'sol_pmap_pid'
    LANGUAGE C IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION sol_memsizes_pid(in integer,
	out file_mem bigint, out shared_mem bigint, out anon_mem bigint,
	out stack_mem bigint, out heap_mem bigint) LANGUAGE 'SQL' AS $$
select 
  sum(CASE WHEN map_type = 'file' THEN size ELSE 0 END)::bigint as file_mem,
  sum(CASE WHEN map_type = 'shared' THEN size ELSE 0 END)::bigint as shared_mem,
  sum(CASE WHEN map_type = 'anon' THEN size ELSE 0 END)::bigint as anon_mem,
  sum(CASE WHEN map_type = 'stack' THEN size ELSE 0 END)::bigint as stack_mem,
  sum(CASE WHEN map_type = 'heap' THEN size ELSE 0 END)::bigint as heap_mem
from sol_pmap_pid($1)
$$;

CREATE OR REPLACE VIEW pg_stat_mem AS
	SELECT procpid,
		(a).file_mem, (a).shared_mem, (a).anon_mem,
		(a).stack_mem, (a).heap_mem
	FROM (SELECT procpid, sol_memsizes_pid(procpid) as a
		FROM pg_stat_activity) as foo;
