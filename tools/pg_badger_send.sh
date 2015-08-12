# $1 database to report on
# $2 log file directory
# $3 output directory for generated report
# $4 send location for scp

yesterday="$( /usr/gnu/bin/date --date="yesterday" '+%F' )"
local_server="$(hostname)"

find "$2" -maxdepth 1 -name "postgresql-${yesterday}*" -exec /opt/OMNIperl/bin/perl /opt/pgbadger/pgbadger -q -d "$1" -o "$3/${local_server}_log_report-$yesterday.html" -p '%t [%r] [%p]: [%l-1] user=%u,db=%d,e=%e ' {} +

#export MAILTO="user@example.com"
#export CONTENT="$3/${local_server}_log_report-$yesterday.html"
#yesterday="$( /usr/gnu/bin/date --date="yesterday" '+%A, %b %d %Y' )"
#export SUBJECT="Pgbadger Report - $yesterday"
#(
# echo "Subject: $SUBJECT"
# echo "MIME-Version: 1.0"
# echo "Content-Type: text/html"
# echo "Content-Disposition: inline"
# cat $CONTENT
#) | /usr/sbin/sendmail $MAILTO
(
    echo "To: user@example.com"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html "
    echo "Content-Disposition: inline"
    echo "Subject: Pgbadger Report - $yesterday"
    echo
    cat $3/${local_server}_log_report-$yesterday.html| \
        /home/postgres/bin/pgbadger-report-shrinker.pl
) | /usr/sbin/sendmail -t

# scp file to remote web server
#scp "$3/${local_server}_log_report-$yesterday.html" "$4"
