select 'Top 10 Tables Growth For:-  '||to_char(current_date - '1 month'::interval,'Mon-YYYY') as Month ;

select 
    table_owner, schema_name, table_name, growth_size as Growth_size_MB 
from 
    otools.table_growth 
where 
    sum_flag = 2 
    and 
    to_char(capture_time,'mm')=to_char((current_date - '1 month'::interval),'mm') 
order by 
    growth_size desc 
limit 
    10;
