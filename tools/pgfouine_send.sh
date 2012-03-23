#!/usr/bin/bash

PGFOUINEPATH="/opt/php53/bin/php /opt/pgfouine-1.2/pgfouine.php"

TIME1=$(/usr/gnu/bin/date --date="yesterday" +%Y-%m-%d)
TIME2=$(/usr/gnu/bin/date --date="yesterday" +%Y/%m/%d)

DESTHOST="workingequity2"
DESTPATH="/www/opt/pgfouine/$HOSTNAME/$TIME2"
LOGS="/data/postgres/pgdata/91/pg_log/postgresql-${TIME1}_??????.log"

REPORTS1="overall,bytype,slowest,n-mosttime,n-mostfrequent,n-slowestaverage,n-mostfrequenterrors"
REPORTS2="hourly"

cat $LOGS | ssh $DESTHOST mkdir -p $DESTPATH \; cd $DESTPATH \; $PGFOUINEPATH - -quiet -logtype stderr -report report.html=$REPORTS1 -report graphs.html=$REPORTS2 -format html-with-graphs