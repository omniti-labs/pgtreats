# $1 database name
# $2 number of tables to vacuum
# $3 relfrozenxid threshold value


/opt/pgsql/bin/psql -d $1 -t -o /tmp/manual_vacuum_$1.sql -c "/*manual vacuum runs from cron*/ select 'vacuum analyze verbose ' || oid::regclass || ';' from pg_class where relkind in ('r', 't') and age(relfrozenxid) > $3 order by age(relfrozenxid) desc limit $2"

/opt/pgsql/bin/psql -d $1 -t -a -f /tmp/manual_vacuum_$1.sql > $HOME/logs/manual_vacuum_$1.log 2>&1
