create or replace function otools.collect_table_growth() 
returns void   
as $$
    insert into otools.table_growth (table_owner, schema_name, table_name, actual_size, growth_size, sum_flag, capture_time) 
    select pg_get_userbyid(c.relowner) AS table_owner, n.nspname AS schema_name, c.relname AS table_name, pg_total_relation_size(c.oid), 0, 0, current_date 
    from pg_class c JOIN pg_namespace n ON (c.relnamespace=n.oid) where relkind = 'r' and reltuples > 25000;
$$ language sql;
