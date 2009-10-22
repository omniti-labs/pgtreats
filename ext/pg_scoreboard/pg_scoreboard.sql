BEGIN;
create schema scoreboard;

create function scoreboard.__process_register(varchar, integer, varchar)
returns void as 'pg_scoreboard.so', 'process_register'
language C immutable;

create function scoreboard.process_register(varchar) returns integer as $$
  select scoreboard.__process_register(inet_client_addr() ::varchar,
                                       inet_client_port(), $1);
  select pg_backend_pid();
$$ language sql;

create function scoreboard.process_status(varchar)
returns void as 'pg_scoreboard.so', 'process_status'
language C immutable strict;

create function scoreboard.process_deregister()
returns void as 'pg_scoreboard.so', 'process_deregister'
language C immutable strict;

create function scoreboard.process_scoreboard(
  out procpid integer,
  out client_addr varchar,
  out client_port varchar,
  out create_time timestamp without time zone,
  out last_update timestamp without time zone,
  out description varchar,
  out status varchar
)
returns setof record
as 'pg_scoreboard.so', 'process_scoreboard'
language C immutable strict;

create view scoreboard.scoreboard as
select * from scoreboard.process_scoreboard();
COMMIT;
