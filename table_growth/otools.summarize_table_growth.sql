create or replace function otools.summarize_table_growth()  
returns void 
as $$
declare
    v_sql text;
begin

-- Daily summarization
IF to_char(current_date,'dd') <> '01' THEN
    insert into otools.table_growth (table_owner, schema_name, table_name, actual_size, growth_size, sum_flag, capture_time)
    select a.table_owner, a.schema_name, a.table_name, a.actual_size, a.actual_size-coalesce(b.actual_size,a.actual_size) AS table_growth, 1, a.capture_time
    from otools.table_growth a 
        left join otools.table_growth b 
            on (a.table_owner=b.table_owner and a.table_name=b.table_name and a.schema_name=b.schema_name and b.capture_time = current_date -1) 
    where 
        a.sum_flag=0 and a.capture_time = current_date;
    -- now remove older rows
    delete from otools.table_growth where sum_flag = 0;
END IF;

-- Monthly summarization
IF to_char(current_date,'dd') = '01' THEN
    insert into otools.table_growth (table_owner, schema_name, table_name, actual_size, growth_size, sum_flag, capture_time)
    select a.table_owner, a.schema_name, a.table_name, max(actual_size), sum(growth_size), 2, (current_date - '1 month'::interval) 
    from otools.table_growth a 
    where sum_flag=1 and capture_time between (current_date - '1 month'::interval) and current_date 
    group by table_owner, schema_name, table_name;
    -- now remove older rows
    delete from otools.table_growth where sum_flag = 1;
END IF;

end 
$$ language plpgsql;
