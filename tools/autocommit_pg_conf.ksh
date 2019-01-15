#!/bin/ksh

##############################################################################
# Script to commit postgres conf files into svn
# This assumes that the path for svn to use exists under /export/home/postgres

# Example for crontab:
# 2,7,12,17,22,27,32,37,42,47,52,57 * * * * /export/home/postgres/bin/autocommit_pg_conf.ksh -u asautocommit -d /data/set/allisports/84/pgdata
##############################################################################

#############################################################################
#       Process command line options
#############################################################################

USAGE="Usage: ${0##*/} [-u username for svn checkin] [-d fully qualified path to pg conf files]

-u      username for svn to use for check in
-d      fully qualified path for the postgres conf files
"
while getopts u:d: optc
do
        case $optc in
                u)      CI_USER=$OPTARG ;;
                d)      PG_CONF_DIR=$OPTARG ;;
                *)      echo "$USAGE" >&2
                        exit 1
                        ;;
        esac
done
shift `expr $OPTIND - 1`

if [ -z "$CI_USER" ]
then
        echo "\nUsername for svn checkin is required.\n" >&2
        echo "$USAGE" >&2
        exit 1
fi

if [ -z "$PG_CONF_DIR" ]
then
        echo "\nDirectory location for pg conf files is required.\n" >&2
        echo "$USAGE" >&2
        exit 1
fi

if [ ! -d "$PG_CONF_DIR" ]
then
        echo "\nDirectory location for pg conf files is not a directory.\n" >&2
        echo "$USAGE" >&2
        exit 1
fi

if [ ! -f "$PG_CONF_DIR/postgresql.conf" ]
then
        echo "\nThere is no postgresql.conf in $PG_CONF_DIR - supply valid path.\n" >&2
        echo "$USAGE" >&2
        exit 1
fi

export PATH='/opt/pgsql/bin:/usr/gnu/bin:/opt/omni/bin:/opt/OMNIperl/bin:/opt/pgsql/bin:/usr/openwin/bin:/usr/perl5/5.8.4/bin:/usr/X11/bin:/usr/dt/bin:/usr/sfw/bin:/usr/ccs/bin:/usr/xpg4/bin:/usr/jdk/instances/jdk1.5.0/jre/bin:/usr/jdk/instances/jdk1.5.0/bin:/usr/xpg6/bin:/usr/bin:/usr/proc/bin:/usr/SUNWale/bin:/usr/sadm/sysadm/bin:/usr/sadm/bin:/usr/sadm/install/bin:/opt/nagios/bin'

SVN_LOCAL_DIR="/export/home/postgres/svn/$PG_CONF_DIR/"

if [[ ! -d "$SVN_LOCAL_DIR" ]]
then
    echo "SVN checkout path for $PG_CONF_DIR does not exist ($SVN_LOCAL_DIR)" >&2
    exit 1
fi

cp "$PG_CONF_DIR"/*.conf "$SVN_LOCAL_DIR"

cd "$SVN_LOCAL_DIR"

svn add *.conf > /dev/null 2>&1

DIFF="$( svn diff 2>&1 )"
if [[ -z "$DIFF" ]]
then
    exit 0
fi

COMMIT="$( svn ci --username $CI_USER -m "Autocommit of change" 2>&1 )"

echo "# svn diff
$DIFF

$COMMIT" | mailx -s "PostgreSQL config change on $( uname -n ) in $PG_CONF_DIR" dba@credativ.us
