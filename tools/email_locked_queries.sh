#!/bin/bash

############################################################################
# Module Name   : email_locked_queries                                    # 
# Module Type   : Shell script                                             #
# Synopsis      : This script will send queries those are locked for more  # 
                 than 10 minutes with the blocking query details           #
# Copyright     : 2010, OmniTI Inc.                                        #
#                                                                          # 
############################################################################

LOGFILE=/home/postgres/logs/email_locked_queries.rpt
DNAME=your_real_postgres_db_name

psql  -d ${DNAME} -x -t -q  -c  " 
select
    bl.relation as locked_relation,
    bl.mode as locked_mode,
    bl.pid as blocked_pid,
    a.usename as blocked_user,
    a.current_query as blocked_statement,
    a.client_addr as blocked_client_addr,
    age(now(),a.query_start) as blocked_query_age,
    kl.pid as blocking_pid,
    ka.usename as blocking_user,
    ka.current_query as blocking_statement,
    ka.client_addr as blocking_client_addr,
    now() - ka.query_start as blocking_query_age,
    now() - ka.xact_start as blocking_xact_age
from pg_catalog.pg_locks bl
     join pg_catalog.pg_stat_activity a
     on bl.pid = a.procpid
     join pg_catalog.pg_locks kl
          join pg_catalog.pg_stat_activity ka
          on kl.pid = ka.procpid
     on bl.transactionid = kl.transactionid and bl.pid != kl.pid
where not bl.granted  and (now() - ka.query_start) > interval '10 minutes' order by blocking_xact_age desc ;"  > $LOGFILE

FILESIZE=`ls -l $LOGFILE | awk '{print $5}'`
M_HOSTNAME=$(hostname)'.'$(cat /etc/resolv.conf | grep domain | cut -f2 -d' ')

if [ $FILESIZE -ge 11 ]; then
        mailx -s "DB locked queries for ${DNAME} on ${M_HOSTNAME}" dba@omniti.com < $LOGFILE 
fi

rm $LOGFILE
exit
