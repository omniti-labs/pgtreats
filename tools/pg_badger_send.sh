#!/usr/bin/bash

DATABASE="postgres"
LOG_FILE_PATH="/pgdata/pg_log"
DESTINATION="/home/postgres/log_report"
SCP_LOCATION=""
EMAIL_ADDRESS=""
YESTERDAY="$( /usr/gnu/bin/date --date="yesterday" '+%F' )"
LOCAL_SERVER="$(hostname)"

# Help menu
usage() {
    cat <<EOF
$0: [-d <database>] [-l <log_file_directory>] [-o <output_path>] [-s <scp_location>] [-e <email_address>]
        -d <database>				database to generate report for
        -l <log_file_directory>			location of postgres log files
        -o <output_path>			location of generated pgbadger reports
        -s <scp_location>			optional argument for sending generated report to another machine
        -e <email_address>     			emails address to send the report to
EOF

# Read commandline parameters
read_params() {
    while getopts 'd:l:o:s:e:' opt "$@"
    do
        case "$opt" in
            d)
                DATABASE="${OPTARG}"
                ;;
            l)
                LOG_FILE_PATH="${OPTARG}"
                ;;
            o)
                DESTINATION="${OPTARG}"
                ;;
            s)
                SCP_LOCATION="${OPTARG}"
                ;;
            e)
                EMAIL_ADDRESS="${OPTARG}"
                ;;
            h)
                usage
                exit 2
                ;;
            :)
                echo "Option -%s requires argument" "$OPTARG"
                usage
                exit 2
                ;;
            \?)
                if [[ "$OPTARG" == "?" ]]
                then
                    usage
                    exit 2
                fi
                echo "Unknown option -%s" "$OPTARG"
                usage
                exit 2
                ;;
        esac
    done
}

# Generate the report
find "${LOG_FILE_PATH}" -maxdepth 1 -name "postgresql-${YESTERDAY}*" -exec /opt/OMNIperl/bin/perl /opt/pgbadger/pgbadger -q -d "${DATABASE}" -o "${DESTINATION}/${LOCAL_SERVER}_log_report-${YESTERDAY}.html" -p '%t [%r] [%p]: [%l-1] user=%u,db=%d,e=%e ' {} +

# Send report to email address
if [[ -n "${EMAIL_ADDRESS}" ]] 
then

    (
        echo "To: ${EMAIL_ADDRESS}"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html "
        echo "Content-Disposition: inline"
        echo "Subject: Pgbadger Report - ${YESTERDAY}"
        echo
        cat ${DESTINATION}/${LOCAL_SERVER}_log_report-${YESTERDAY}.html| \
            /opt/OMNIperl/bin/perl /opt/pgtreats/tools/pgbadger-report-shrinker.pl
    ) | /usr/sbin/sendmail -t

fi

# scp file to remote web server
if [[ -n "${SCP_LOCATION}" ]]
then

    scp "${DESTINATION}/${LOCAL_SERVER}_log_report-${YESTERDAY}.html" "${SCP_LOCATION}"

fi
