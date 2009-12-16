#!/bin/bash

export PATH=/home/pgdba/work-8.4.1/bin:/usr/local/bin:/usr/bin:/bin
# DB Connection details, using PG* environment variables, as described http://www.postgresql.org/docs/current/interactive/libpq-envars.html
PGUSER=depesz
PGHOST=localhost
PGPORT=5840
PGDATABASE=depesz
# DB Connection details, using PG* environment variables, as described http://www.postgresql.org/docs/current/interactive/libpq-envars.html

# Make it stop on error, and print all commands before running

set -e
set -x

# Prepare test environment
psql -qAtX -f 00-prepare.sql

# Run the tests themselves
pg_prove plperl/*.sql

# Clean test environment
psql -qAtX -f 99-cleanup.sql
