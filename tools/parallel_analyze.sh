#!/bin/bash
# Parallel Vacuum-Analyze script Version 1.1
#

if [ $# -ne 2 ];
	then echo "Usage: `basename $0` <dbname> <jobs> "
	exit 0
fi


my_psql=/opt/postgresql/pgsql/bin/psql
db=$1
jobs=5
port=5432

function get_list_of_objects {
	echo $db
$my_psql -d $db -t -p $port -o /tmp/all_objects.sql -c "select 'Vacuum analyze ' || c.oid::regclass ||' /* manual vacuum-analyze */ ;' \
	FROM pg_class c LEFT JOIN pg_class t \
	ON c.reltoastrelid = t.oid  WHERE c.relkind = ANY (ARRAY['r'::"char", 't'::"char", 'm'::"char"]) "
}

function split_to_jobs {
number_of_rows=`wc -l < /tmp/all_objects.sql`
number_per_file=`expr $number_of_rows / $jobs`
number_per_file_round_up=`expr $number_per_file + 1`
split -l $number_per_file /tmp/all_objects.sql /tmp/objects_
}


function fix_files {
for a in `ls -1 /tmp/objects_*` ;
		do echo "set timezone TO 'America/New_York'; select '$a ended at : '||now();">> $a
done
}

function run_vacuum {
ls -l /tmp/objects_*
for a in `ls -1 /tmp/objects_*` ;
	do $my_psql -q -X -f $a -d $db -p $port  2>&1 &
done
}

function cleanup {
rm /tmp/objects_* /tmp/all_objects.sql || true
}
cleanup
get_list_of_objects;
split_to_jobs;
fix_files
run_vacuum 
#|grep -v "WARNING"
