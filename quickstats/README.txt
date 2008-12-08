INFO:

Quickstats schema is used to gather DML (insert/update/delete) statistics to find the number of transactions in the database. 

INSTALL:

You should install quickstats_schema.sql into database for which you want to gather the statistics and schedule a postgres cron job to gather the statistics.

Schedule postgres cron job:

#5,10,15,20,25,30,35,40,45,50,55 * * * * [pgsql dir]/bin/psql -U postgres -c "select quickstats.gather()" -d DB_NAME > /dev/null 2>&1
