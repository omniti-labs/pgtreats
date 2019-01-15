#!/bin/bash

############################################################################
# Module Name   : table_growth                                             # 
# Module Type   : Shell script                                             #
# Synopsis      : This script will send table growth monitor report.       #
# Copyright     : 2008, OmniTI Inc.                                        #
#                                                                          # 
############################################################################

LOGFILE=/home/postgres/logs/table_growth.rpt
DNAME=your_real_postgres_db_name

psql -d ${DNAME} -c "select 'Top 10 Tables Growth For:-  '||to_char(current_date - '1 month'::interval,'Mon-YYYY') as Month; select table_owner, schema_name, table_name, pg_size_pretty(growth_size::bigint) as Growth_size_MB from otools.table_growth where sum_flag = 2 and to_char(capture_time,'mm/yyyy')=to_char((current_date - '1 month'::interval),'mm/yyyy') order by growth_size desc limit 10;" > $LOGFILE

if [ -s "$LOGFILE" ]; then
  M_HOSTNAME=$(hostname)'.'$(cat /etc/resolv.conf | grep domain | cut -f2 -d' ')
  mailx -s "Tablegrowth Monitor Report for ${DNAME} on ${M_HOSTNAME}" dba@credativ.us < $LOGFILE
fi
rm $LOGFILE
exit

