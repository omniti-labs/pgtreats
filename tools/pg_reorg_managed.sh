#!/bin/bash

pg_reorg=/usr/pgsql-9.0/bin/pg_reorg
dbname=$1
stop_file=/tmp/stop.reorg
completed_list=/tmp/reorg_completed.txt

psql -U postgres -d ${dbname} -A -t -c "select schemaname || '.' || tablename as name from pg_tables where schemaname not in ('pg_catalog','information_schema','reorg') and schemaname not like 'pg_toast%' order by pg_total_relation_size(schemaname || '.' || tablename)" | while read -r table
do
    if [[ -f ${stop_file} ]]
    then
        echo "Exiting on stop file."
        rm -f ${stop_file}
        exit
    fi

    if [[ -f ${completed_list} && $(grep ${table} ${completed_list}) ]]
    then
        echo "Skipping ${table}."
    else
        echo "Cleaning ${table}: ${pg_reorg} -U postgres -t ${table} -T 600 -n -d ${dbname}"
        ${pg_reorg} -U postgres -t ${table} -T 600 -n -d ${dbname}
        echo ${table} >> ${completed_list}
    fi
done
