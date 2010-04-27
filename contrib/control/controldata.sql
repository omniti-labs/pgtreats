BEGIN;
create schema controldata;

create function controldata.variables(name out text, value out text)
returns setof record as 'controldata.so', 'pg_control_variables'
language C immutable;

create view controldata.pg_controldata as
select * from controldata.variables();

COMMIT;
