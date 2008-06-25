#!/bin/bash

############################################################################
# Module Name   : table_growth                                             # 
# Module Type   : Shell script                                             #
# Synopsis      : This script will send table growth monitor report.       #
# Copyright     : 2008, OmniTI Inc.                                        #
#                                                                          # 
############################################################################

LOGFILE=/home/postgres/logs/table_growth.rpt
psql -d pagila -c "select 'Top 10 Tables Growth For:-  '||to_char(current_date - '1 month'::interval,'Mon-YYYY') as Month; select table_owner, schema_name, table_name, pg_size_pretty(growth_size::bigint) as Growth_size_MB from otools.table_growth where sum_flag = 2 and to_char(capture_time,'mm')=to_char((current_date - '1 month'::interval),'mm') order by growth_size desc limit 10;" > $LOGFILE

if [ -s "$LOGFILE" ]; then
  mailx -s "Tablegrowth Monitor Report" dba@example.com < $LOGFILE
fi
rm $LOGFILE
exit

