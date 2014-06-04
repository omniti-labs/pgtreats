#!/usr/bin/env bash

set -e
#set -x

## CONFIG ##

HOSTNAME=`hostname`
ZONE="/zones/${HOSTNAME}/root"
BACKUPCONF="/root/etc/${HOSTNAME}_zbackup.conf"
LOCKFILEPATH="/var/tmp"
PSQLCMD="/opt/pgsql/bin/psql"
ZFSCMD="/usr/sbin/zfs"
SSHCMD="/usr/bin/ssh"
OFFSITEDIR="/data/zbackup/${HOSTNAME}"
COMPRESSCMD="/usr/bin/gzip"
DECOMPRESSCMD="/usr/bin/gunzip"
TEECMD="/usr/gnu/bin/tee"
ZSTREAMDUMPCMD="/usr/sbin/zstreamdump"
EXT=".gz"
PGPORT="5432"

## END CONFIG ##

## DO NOT EDIT BELOW THIS LINE ##

SERIAL=$(date +%Y%m%d%H%M%S)

usage() {
    cat <<EOF
$0: [-ofi] [-p <port_number>] [-z <target>] [-t <path>] [-l <label>] [-c <conf_file>]
        -o              specify offline mode otherwise online
        -f              force a backup even if one is running.
        -i              perform only an incremental if possible
        -p <port>       port which database runs on (default 5432)
        -z <target>     use zfs send. using <target>
        -t <path>       use tar. create file in <path>
        -l <label>      backup using label: <label>
        -c <conf_file>  use alternate config file path
        -g <zone_name>  If runningfrom global zone, provide the local zone name
EOF
    rm ${LOCKFILE}
}

read_params() {
    while getopts 'ofip:z:t:l:c:g:' opt "$@"
    do
        case "$opt" in
            o)
                OFFLINE="yes"
                ;;
            f)
                FORCE="yes"
                ;;
            i)
                INCREMENTAL="yes"
                ;;
            p)
                PGPORT="${OPTARG}"
                ;;
            z)
                ZFSSENDTARGET="${OPTARG}"
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
            g)
                HOSTNAME="${OPTARG}"
                ZONE="/zones/${HOSTNAME}/root"
                BACKUPCONF="/root/etc/${HOSTNAME}_zbackup.conf"
                OFFSITEDIR="/data/zbackup/${HOSTNAME}"
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

config_file_check() {
    if [ ! -f ${BACKUPCONF} ]; then
	echo "Config file for ${HOSTNAME} does not exist. Do you wish to create one? (Y/n) "
	read createfile
	if [ ${createfile} = "Y" ]; then
	    touch ${BACKUPCONF}
	    while [ ${createfile} = "Y" ]
	    do
		echo "Enter full path of dataset to backup (E.g. data/set/<hostname>/postgres/pgdata) = "
		read set_name
		echo "${set_name}" >> ${BACKUPCONF}
		echo "Do you wish to add another dataset? (Y/n): "
		read createfile
	    done
	else
	    echo "Config file created"
	fi
    fi 
}

pg_backup_child_script_check() {
    if [ ! -f ${ZONE}/export/home/postgres/bin/pg_start_backup.sh ]; then
	touch ${ZONE}/export/home/postgres/bin/pg_start_backup.sh
	echo "#!/usr/bin/env bash
	      read_params() {
		  while getopts 'p:l:g:s:' opt \"\$@\"
		  do
		      case \"\$opt\" in
			  p)
			      PSQLCMD=\"\${OPTARG}\"
			      ;;
			  l)
			      BACKUPLABEL=\"\${OPTARG}\"
			      ;;
			  g)
			      HOSTNAME=\"\${OPTARG}\"
			      ;;
			  s)
			      SERIAL=\"\${OPTARG}\"
			      ;;
			  h)
			      exit 2
			      ;;
			  :)
			      echo \"Option \-\%s requires argument\" \"\$OPTARG\"
			      exit 2
			      ;;
			  \\?)
			      if [[ \"\$OPTARG\" == \"?\" ]]
			      then
				  exit 2
			      fi
			      echo \"Unknown option -%s\" \"$\OPTARG\"
			      exit 2
			      ;;
		      esac
		  done
	      }

	      read_params \"\$@\"

	      /opt/pgsql/bin/psql -c \"SELECT pg_start_backup('${BACKUPLABEL}_${SERIAL}');\"

	      exit
	      " >> ${ZONE}/export/home/postgres/bin/pg_start_backup.sh
	      
	      zlogin ${HOSTNAME} chown postgres:postgres /home/postgres/bin/pg_start_backup.sh
	      zlogin ${HOSTNAME} chmod 744 /home/postgres/bin/pg_start_backup.sh
	      
	      echo "Script created, required permissions granted."
    fi
}

sanity_check() {
    echo "backuplabel: ${BACKUPLABEL:=zbackup}"
    LOCKFILE="${ZONE}${LOCKFILEPATH}/zbackup-${HOSTNAME}-${BACKUPLABEL}.lock"
    if [[ -f ${LOCKFILE} ]] && [[ -z ${FORCE} ]]
    then
        echo "backup in progress (${LOCKFILE} exists)."
        exit
    else
        touch ${LOCKFILE}
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
    zlogin -l postgres ${HOSTNAME} ${PSQLCMD} -c "CHECKPOINT;"
    zlogin -l postgres ${HOSTNAME} bin/pg_start_backup.sh -g ${HOSTNAME} -s ${SERIAL} -l ${BACKUPLABEL} -p ${PSQLCMD}
}

postgres_stop_backup() {
    echo "stopping postgres backup on label ${BACKUPLABEL}_${SERIAL}"
    zlogin -l postgres ${HOSTNAME} "${PSQLCMD} -c 'SELECT pg_stop_backup();'"
}

zfs_snap() {
    while read -r dset
    do
        [[ ${dset} = \#* ]] && continue
        ${ZFSCMD} snapshot ${dset}@${BACKUPLABEL}_${SERIAL}
        ${ZFSCMD} hold zbackup ${dset}@${BACKUPLABEL}_${SERIAL}
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
        DESTFILE=${1//\//\.}.incr.zfs
        ${ZFSCMD} send -i ${OLDSNAP} $1 | ${COMPRESSCMD} | ${SSHCMD} ${ZFSSENDTARGET} "${TEECMD} ${OFFSITEDIR}/${DESTFILE}${EXT} | ${DECOMPRESSCMD} | ${ZSTREAMDUMPCMD}"
    fi

    if [[ -z ${INCREMENTAL} ]] || [[ -z ${OLDSNAP} ]]
    then
        DESTFILE=${1//\//\.}.full.zfs
        ${ZFSCMD} send $1 | ${COMPRESSCMD} | ${SSHCMD} ${ZFSSENDTARGET} "${TEECMD} ${OFFSITEDIR}/${DESTFILE}${EXT} | ${DECOMPRESSCMD} | ${ZSTREAMDUMPCMD}"
    fi
}

backup() {
    while read -r dset
    do  
        [[ ${dset} = \#* ]] && continue
        ${ZFSCMD} list -H -t snapshot -o name | grep "^${dset}@${BACKUPLABEL}_" | grep "${SERIAL}$" | while read -r snap

        do
                if [[ ${ZFSSENDTARGET} ]]
                then
                        zfs_send ${snap}
                fi

                if [[ ${TARPATH} ]]
                then
                        tar_filesystem ${snap}
                fi
        done
    done < "${BACKUPCONF}"
}

zfs_clear_snaps() {
    while read -r dset
    do
        [[ ${dset} = \#* ]] && continue
        ${ZFSCMD} list -H -t snapshot -o name | grep "^${dset}@${BACKUPLABEL}_" | grep -v "${SERIAL}$" | while read -r snap
        do
            ${ZFSCMD} release zbackup ${snap}
            ${ZFSCMD} destroy ${snap}
        done
    done < "${BACKUPCONF}"
}

read_params "$@"
config_file_check
sanity_check
pg_backup_child_script_check

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
rm ${LOCKFILE}

