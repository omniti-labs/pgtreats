create or replace function verify_serial_sequences(out v_tbl regclass, out v_col_said bigint, out v_seq_said bigint)
returns setof record 
stable
as $$
declare
    v_rec RECORD;
    v_sql TEXT;
begin

for v_rec in select 
            n.nspname as schema_name,
            c.relname as table_name,
            c.oid as table_oid,
            a.attname as column_name,
            substring(d.adsrc from E'^nextval\\(''([^'']*)''(?:::text|::regclass)?\\)') as seq_name 
        from 
            pg_class c 
            join pg_attribute a on (c.oid=a.attrelid) 
            join pg_attrdef d on (a.attrelid=d.adrelid and a.attnum=d.adnum) 
            join pg_namespace n on (c.relnamespace=n.oid)
        where 
            has_schema_privilege(n.oid,'USAGE')
            and n.nspname not like 'pg!_%' escape '!'
            and has_table_privilege(c.oid,'SELECT')
            and (not a.attisdropped)
            and d.adsrc ~ 'nextval'
loop

    v_sql := 'select '||quote_literal(v_rec.table_oid::regclass)||', * from '||
             '(select max('||v_rec.column_name||') from '||v_rec.schema_name||'.'||v_rec.table_name||') t, '|| 
             '(select last_value from '||v_rec.schema_name||'.'||v_rec.seq_name||') s';

    execute v_sql into v_tbl, v_col_said, v_seq_said;
    return next;

end loop;

return;

end
$$ language plpgsql;

select * from verify_serial_sequences();

drop function verify_serial_sequences(); 

