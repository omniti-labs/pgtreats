INFO:

Table growth is a simple set of schema/functions used for monitoring table
growth on your database. 

INSTALL:

You should install the .sql files into database for which you want to 
gather growth information and schedule a postgres cron job to gather 
the information.

45 6 1 * * /var/lib/pgsql/scripts/table_growth_report.sh 1>/dev/null
