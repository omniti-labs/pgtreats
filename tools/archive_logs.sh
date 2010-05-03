#!/bin/bash

# Function definitions have to be here.
# For actual code ran when you run this script, search for "# MAIN PROGRAM #"

# Function    : show_help_and_exit
# Description : Like the name suggests, it prints help page, and exits script
#             : If given args, treats them as format and arguments for printf
#             : and prints before help page
show_help_and_exit () {
    if (( $# > 0 ))
    then
        FORMAT="ERROR:\n$1\n\n"
        printf "$FORMAT" "${@:2:$#}" >&2
    fi
    cat <<_EO_HELP_
Syntax:
    $0 -d /some/directory [OPTIONS]

Arguments:
    -d       : specifies directory in which logs will be searched for

Options:
    -x       : extended debug. Use when debugging the script itself.
    -v       : show information while processing log files
    -a VALUE : name of directory to put archives in
             : if name of directory starts with / it is treated as full path
             : to archive directory. Otherwise it is treated as subdirectory
             : of log directory (-d)
    -k VALUE : how many days of logs keep uncompressed
    -c VALUE : compression program to use. Supported programs are:
             :   - gzip
             :   - bzip2
             :   - lzma
             : VALUE can be full path to program, but it's name must be one of
             : the supported programs.
    -r       : remove the logfiles instead of archiving them
    -n       : use nice when compressing
    -o       : overwrite pre-existing archive files (otherwise, log files which
             : would archive to files that already exist will get skipped with
             : warning)

Defaults:
    -a archive -k 7 -c gzip

Description:

$0 finds all PostgreSQL log files, named: postgresql-YYYY-MM-DD.log or
postgresql-YYYY-MM-DD_HHMISS.log, skips files that are too new to new
compressed, compressed rest and moves to archive dir.

Archive dir is structured in a way to minimize number of files in single
directory. That is, in archive dir, there will be subdirectories named
"YYYY-MM", where YYYY-MM is year and month taken from log file name.
_EO_HELP_
    exit
}

# Function    : get_compress_extension
# Description : prints name of extension to files compressed with given
#             : compressor (-c option)
get_compress_extension () {
    REAL_NAME=$( basename "$COMPRESS" )
    case "$REAL_NAME" in
        gzip)
            echo "gz"
            ;;
        bzip2)
            echo "bz2"
            ;;
        lzma)
            echo "lzma"
            ;;
    esac
}

# Function    : verbose_msg
# Description : Calls printf on given args, but only if VERBOSE is on.
verbose_msg () {
    if (( $VERBOSE == 1 ))
    then
        printf "$@"
    fi
}

# Function    : read_arguments
# Description : Reads arguments from command line, and validates them
#             : default values are in "MAIN PROGRAM" to simplify finding them
read_arguments () {
    while getopts ':d:xva:k:c:norh' opt "$@"
    do
        case "$opt" in
            d)
                LOG_DIRECTORY="$OPTARG"
                ;;
            x)
                EXTENDED_DEBUG=1
                ;;
            v)
                VERBOSE=1
                ;;
            a)
                ARCHIVE_DIR="$OPTARG"
                ;;
            k)
                KEEP_DAYS="$OPTARG"
                ;;
            c)
                COMPRESS="$OPTARG"
                ;;
            n)
                USE_NICE=1
                ;;
            o)
                OVERWRITE_ARCHIVE=1
                ;;
            r)
                REMOVE_LOGS=1
                ;;
            h)
                show_help_and_exit
                ;;
            :)
                show_help_and_exit "Option -%s requires argument" "$OPTARG"
                ;;
            \?)
                if [[ "$OPTARG" == "?" ]]
                then
                    show_help_and_exit
                fi
                show_help_and_exit "Unknown option -%s" "$OPTARG"
                ;;
        esac
    done

    if [[ "$LOG_DIRECTORY" == "" ]]
    then
        show_help_and_exit "log_directory (-d) was not provided!"
    fi
    if ! [[ -d "$LOG_DIRECTORY" ]]
    then
        show_help_and_exit "Given log_directory (%s) does not exist or is not directory!" "$LOG_DIRECTORY"
    fi
    if ! [[ -r "$LOG_DIRECTORY" ]]
    then
        show_help_and_exit "Given log_directory (%s) is not readable!" "$LOG_DIRECTORY"
    fi
    if ! [[ -w "$LOG_DIRECTORY" ]]
    then
        show_help_and_exit "Given log_directory (%s) is not writable!" "$LOG_DIRECTORY"
    fi
    if ! [[ -x "$LOG_DIRECTORY" ]]
    then
        show_help_and_exit "Given log_directory (%s) is not usable (lack of x in mode)!" "$LOG_DIRECTORY"
    fi

    COMPRESS_EXTENSION=$( get_compress_extension )
    if [[ "$COMPRESS_EXTENSION" == "" ]]
    then
        show_help_and_exit "Given compressor (%s) is not supported!" "$COMPRESS"
    fi

    if [[ ! "$KEEP_DAYS" =~ ^[0-9]+$ ]]
    then
        show_help_and_exit "Number of days to keep uncompressed (%s) is not a valid number (0+, integer)" "$KEEP_DAYS"
    fi

    if [[ "$ARCHIVE_DIR" == "" ]]
    then
        show_help_and_exit "Archive dir (-a) cannot be empty!"
    fi

    # Strip trailing / (normally, it would be s#/+$## or s#/\+$##, but
    # it has to work on Solaris, so we have to use their approximation
    # of regular expressions
    LOG_DIRECTORY=$( echo "$LOG_DIRECTORY" | sed 's#/\{1,\}$##' )
    ARCHIVE_DIR=$( echo "$ARCHIVE_DIR" | sed 's#/\{1,\}$##' )

    # Make archive dir relative to LOG_DIRECTORY, if it's not absolute
    if [[ ! ${ARCHIVE_DIR:0:1} == "/" ]]
    then
        ARCHIVE_DIR="${LOG_DIRECTORY}/${ARCHIVE_DIR}"
    fi

    if (( "$USE_NICE" == 0 ))
    then
        USE_NICE=""
    else
        USE_NICE="nice"
    fi
}

# MAIN PROGAM #

# default values for arguments and options
LOG_DIRECTORY=""
EXTENDED_DEBUG=0
VERBOSE=0
ARCHIVE_DIR=archive
KEEP_DAYS=7
COMPRESS=gzip
USE_NICE=0
OVERWRITE_ARCHIVE=0
REMOVE_LOGS=0

# Set locale to sane one, to speed up comparisons, and be sure that < and > on
# strings work ok.
export LC_ALL=C

# Read arguments from command line
read_arguments "$@"

# Print settings
verbose_msg "$0 Settings:
  - ARCHIVE_DIR       : $ARCHIVE_DIR
  - COMPRESS          : $COMPRESS
  - EXTENDED_DEBUG    : $EXTENDED_DEBUG
  - KEEP_DAYS         : $KEEP_DAYS
  - LOG_DIRECTORY     : $LOG_DIRECTORY
  - OVERWRITE_ARCHIVE : $OVERWRITE_ARCHIVE
  - USE_NICE          : $USE_NICE
  - VERBOSE           : $VERBOSE
  - REMOVE_LOGS       : $REMOVE_LOGS
"

# Make sure every error past this line is critical - this is to avoid having to
# check return codes from all calls to external programs
set -e

# Turn on extended debug
if (( $EXTENDED_DEBUG == 1 ))
then
    set -x
fi

# Border date - any log from this date or newer has to stay uncompressed
# Have to use perl instead of more natural date --date="..." because
# Solaris date doesn't support --date="" option
export KEEP_DAYS
BORDER_DATE=$( perl -MPOSIX=strftime -e 'print strftime(q{%Y-%m-%d}, localtime( time() - $ENV{"KEEP_DAYS"} * 24 * 60 * 60 ))' )
verbose_msg "Border date: %s\n" "$BORDER_DATE"

# Find all log files, sort them (to work on them in order), and process
# Have to use grep, because Solaris find doesn't have -mindepth nor
# -maxdepth options
# Using ls could be an option, but it tends to write messages to STDERR if
# there are no matching files - not something that we would like.
find "$LOG_DIRECTORY"/ -type f \( -name 'postgresql-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].log' -o -name 'postgresql-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].log' \) -print | \
    egrep "^${LOG_DIRECTORY}/postgresql-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9](_[0-9][0-9][0-9][0-9][0-9][0-9])?.log" | \
    sort | \
    while read SOURCE_FILENAME
    do
        FILENAME=$( basename "$SOURCE_FILENAME" )
        # skip files that are not older than $BORDER_DATE
        if [[ ! "$FILENAME" < "postgresql-$BORDER_DATE" ]]
        then
            continue
        fi

        verbose_msg "Archiving file %-32s ... " "$FILENAME"

        if [[ "$REMOVE_LOGS" -eq "1" ]]
        then
            rm "$SOURCE_FILENAME"
            verbose_msg "File removed.\n"
            continue
        fi

        # Extract year and month from log filename - to be used in archive path
        YEAR_MONTH=$( echo "$FILENAME" | cut -d- -f2,3 )
        if [[ ! -d "$ARCHIVE_DIR/$YEAR_MONTH" ]]
        then
            mkdir -p "$ARCHIVE_DIR/$YEAR_MONTH"
        fi

        DESTINATION_FILENAME="${ARCHIVE_DIR}/${YEAR_MONTH}/${FILENAME}.$( get_compress_extension )"

        # Handle overriding
        if [[ -e "${DESTINATION_FILENAME}" ]]
        then
            if (( $OVERWRITE_ARCHIVE == 0 ))
            then
                printf "Destination file %s already exists. Skipping source %s.\n" "${DESTINATION_FILENAME}" "${SOURCE_FILENAME}" >&2
                continue
            fi
            verbose_msg "Destination file %s already exists. Overwriting. ... " "${DESTINATION_FILENAME}"
        fi

        # Have to use perl, because on Solaris, there is no stat command
        export SOURCE_FILENAME
        SIZE_BEFORE=$( perl -e 'print( (stat( $ENV{"SOURCE_FILENAME"} ))[7] )' )

        # Actual archiving - compress to destination file, and remove of source
        # I could also do compress without redirection, (x.log to x.log.gz) and
        # then rename of temporary file, but this requires additional checks
        # for existence of temporary file. Not worth the trouble
        $USE_NICE $COMPRESS -c "$SOURCE_FILENAME" > "$DESTINATION_FILENAME"
        rm -f "$SOURCE_FILENAME"

        # Have to use perl, because on Solaris, there is no stat command
        export DESTINATION_FILENAME
        SIZE_AFTER=$( perl -e 'print( (stat( $ENV{"DESTINATION_FILENAME"} ))[7] )' )

        verbose_msg "done. Size changed from %u to %u.\n" "$SIZE_BEFORE" "$SIZE_AFTER"
    done

verbose_msg "All done.\n"
