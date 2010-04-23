BEGIN;
create schema pgtreats_control;

create function pgtreats_control.variables(name out text, value out text)
returns setof record as 'control.so', 'pg_control_variables'
language C immutable;

create view pgtreats_control.pg_control as
select * from pgtreats_control.variables();

COMMIT;
