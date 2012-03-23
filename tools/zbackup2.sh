#!/usr/bin/env bash

## CONFIG ##

HOSTNAME="hostname.domain"
BACKUPCONF="/home/postgres/etc/zbackup2.conf"
LOCKFILEPATH="/var/tmp"
#BACULACMD=/opt/bacula/sbin/bconsole
#BLOG=/var/bacula/log
#INCDUMPDIR=/var/tmp
PSQLCMD="/opt/pgsql/bin/psql"
ZFSCMD="/usr/sbin/zfs"
SSHCMD="/usr/bin/ssh"
OFFSITEDIR="/data/zfs_offsite/${HOSTNAME}"
COMPRESSCMD="/usr/bin/gzip"
DECOMPRESSCMD="/usr/bin/gunzip -c"
TEECMD="/usr/bin/tee"
ZSTREAMDUMPCMD="/usr/sbin/zstreamdump"
EXT=".gz"
PGPORT="5432"

## END CONFIG ##

## DO NOT EDIT BELOW THIS LINE ##

RUN=true
DEBUG=true
SERIAL=$(date +%Y%m%d%H%M%S)

debug_run() {
    ${DEBUG} && echo "$@"
    ${RUN} && "$@"
}

usage() {
    cat <<EOF
$0: [-odfin] [-p <port_number>] [-z <target>] [-b <job>] [-t <path>] [-l <label>] [-c <conf_file>]
        -o              specify offline mode otherwise online
        -d              just describe the process (don't do it).
        -f              force a backup even if one is running.
        -i              perform only an incremental if possible
        -n              use Netbackup
        -p <port>       port which database runs on (default 5432)
        -z <target>     use zfs send. using <target>
        -b <job>        use bacula. using job=<job>
        -t <path>       use tar. create file in <path>
        -l <label>      backup using label: <label>
        -c <conf_file>  use alternate config file path
EOF

    rm ${LOCKFILE}
}

read_params() {
    while getopts 'odfinp:z:b:t:l:' opt "$@"
    do
        case "$opt" in
            o)
                OFFLINE="yes"
                ;;
            d)
                RUN=false
                ;;
            f)
                FORCE="yes"
                ;;
            i)
                INCREMENTAL="yes"
                ;;
            n)
                NETBACKUP="yes"
                ;;
            p)
                PGPORT="${OPTARG}"
                ;;
            z)
                ZFSSENDTARGET="${OPTARG}"
                ;;
            b)
                BACULAJOB="${OPTARG}"
                ;;
            t)
                TARPATH="${OPTARG}"
                ;;
            l)
                BACKUPLABEL="${OPTARG}"
                ;;
            c)
                BACKUPCONF="${OPTARG}"
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

sanity_check() {
    echo "backuplabel: ${BACKUPLABEL:=zbackup}"

    LOCKFILE="${LOCKFILEPATH}/zbackup-${HOSTNAME}-${BACKUPLABEL}.lock"
    if [[ -f ${LOCKFILE} ]] && [[ -z ${FORCE} ]]
    then
        echo "backup in progress (${LOCKFILE} exists)."
        exit
    else
        ${RUN} && touch ${LOCKFILE}
    fi

    if [[ -z ${NETBACKUP} ]] && [[ -z ${ZFSSENDTARGET} ]] && [[ -z ${BACULAJOB} ]] && [[ -z ${TARPATH} ]]
    then
        echo "No backup method selected!"
        usage
        exit
    fi
}

postgres_start_backup() {
    echo "starting postgres backup on label ${BACKUPLABEL}_${SERIAL}"
    debug_run su - postgres -c "${PSQLCMD} -c \"CHECKPOINT;\""
    debug_run su - postgres -c "${PSQLCMD} -c \"SELECT pg_start_backup('${BACKUPLABEL}_${SERIAL}');\""
}

postgres_stop_backup() {
    echo "stopping postgres backup on label ${BACKUPLABEL}_${SERIAL}"
    debug_run su - postgres -c "${PSQLCMD} -c \"SELECT pg_stop_backup();\""
}

zfs_snap() {
    while read -r dset
    do
        [[ ${dset} = \#* ]] && continue
        debug_run ${ZFSCMD} snapshot ${dset}@${BACKUPLABEL}_${SERIAL}
        debug_run ${ZFSCMD} hold zbackup ${dset}@${BACKUPLABEL}_${SERIAL}
    done < "${BACKUPCONF}"
}

tar_filesystem() {
    MPT=$(${ZFSCMD} list -H -t filesystem -o mountpoint $1)
    echo "tar not implemented"
    sleep 1
}

zfs_send() {
    ${SSHCMD} ${ZFSSENDTARGET} "mkdir -p ${OFFSITEDIR}"

    DSET=${1%%@*}
    OLDSNAP=$(${ZFSCMD} list -H -t snapshot -o name -s creation | grep "^${DSET}@${BACKUPLABEL}_" | grep -v "${SERIAL}$" | tail -1)

    if [[ -n ${OLDSNAP} ]]
    then
        DESTFILE=${1/\//\.}.incr.zfs
        debug_run ${ZFSCMD} send -i ${OLDSNAP} $1 | ${COMPRESSCMD} | ${SSHCMD} ${ZFSSENDTARGET} "${TEECMD} ${OFFSITEDIR}/${DESTFILE}${EXT} | ${DECOMPRESSCMD} | ${ZSTREAMDUMPCMD}"
    fi

    if [[ -z ${INCREMENTAL} ]] || [[ -z ${OLDSNAP} ]]
    then
        DESTFILE=${1/\//\.}.full.zfs
        debug_run ${ZFSCMD} send $1 | ${COMPRESSCMD} | ${SSHCMD} ${ZFSSENDTARGET} "${TEECMD} ${OFFSITEDIR}/${DESTFILE}${EXT} | ${DECOMPRESSCMD} | ${ZSTREAMDUMPCMD}"
    fi
}

netbackup() {
    echo "netbackup not implemented"
    sleep 1
}

bacula() {
    echo "bacula not implemented"
    sleep 1
}

backup() {
    ${ZFSCMD} list -H -t snapshot -o name | grep "@${BACKUPLABEL}_${SERIAL}$" | while read -r snap
    do
        if [[ ${ZFSSENDTARGET} ]]
        then
            zfs_send ${snap} &
        fi

        if [[ ${NETBACKUP} ]]
        then
            netbackup ${snap} &
        fi

        if [[ ${BACULAJOB} ]]
        then
            bacula ${snap} &
        fi

        if [[ ${TARPATH} ]]
        then
            tar_filesystem ${snap} &
        fi
    done

    wait
}

zfs_clear_snaps() {
    while read -r dset
    do
        [[ ${dset} = \#* ]] && continue
        ${ZFSCMD} list -H -t snapshot -o name | grep "^${dset}@${BACKUPLABEL}_" | grep -v "${SERIAL}$" | while read -r snap
        do
            debug_run ${ZFSCMD} release zbackup ${snap}
            debug_run ${ZFSCMD} destroy ${snap}
        done
    done < "${BACKUPCONF}"
}

read_params "$@"
sanity_check

if [[ -z ${OFFLINE} ]]
then
    postgres_start_backup
    zfs_snap
    postgres_stop_backup
else
    zfs_snap
fi

backup
zfs_clear_snaps
${RUN} && rm ${LOCKFILE}
