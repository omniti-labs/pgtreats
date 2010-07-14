#!/bin/sh

BASESNAP=lastfull
BACKUPCONF=/home/postgres/etc/zbackup.conf
BFILE=/home/postgres/pgshared3-backup.filelist
RUN=true
PGBINDIR=/opt/pgsql/bin
DATABASE_PORT=5432

usage() {
cat <<EOF
$0: [-f] [-n] -p <port_number> [-s] -l <label>
        -n              just describe the process (don't do it).
	-p		port which database runs on (default 5432)
        -s              use ZFS send.
        -f              force a backup even if one is running.
        -l <label>      backup using label: <label>
EOF
}

  set -- `getopt fisnp:l: $*`
  if [ $? != 0 ]
  then
    usage
    exit 2
  fi
  for i in $*
  do
    case $i in
      -f)           FORCE=yes; shift;;
      -s)           SEND=yes; shift;;
      -l)           BACKUPLABEL=$2; shift 2;;
      -p)           DATABASE_PORT=$2; shift 2;;
      -n)           RUN=false; shift;;
      --)           shift; break;;
    esac
  done

if test -z "$BACKUPLABEL"; then
  usage
  exit
fi

echo "$0:"
echo "  backuplabel: $BACKUPLABEL"
SNAPNAME=$BASESNAP
echo "  full"

postgres_start_backup() {
  echo "starting postgres backup on label $BACKUPLABEL"
  $RUN && su - postgres -c "$PGBINDIR/psql -p $DATABASE_PORT -c \"SELECT pg_start_backup('$BACKUPLABEL');\""
}
postgres_stop_backup() {
  echo "stopping postgres backup on label $BACKUPLABEL"
  $RUN && su - postgres -c "$PGBINDIR/psql -p $DATABASE_PORT -c \"SELECT pg_stop_backup();\""
}

snap() {
  for line in `sed -e 's/ /:/g;' < $BACKUPCONF`
  do
    DO=`echo $line | awk -F: '{print $1;}'`
    ZFS=`echo $line | awk -F: '{print $2;}'`
    MOUNT=`echo $line | awk -F: '{print $3;}'`
    if test "$DO" = "Y"; then
      echo "zfs snapshot $ZFS@$SNAPNAME"
      $RUN && /sbin/zfs snapshot $ZFS@$SNAPNAME
    fi
  done
}

clear_full() {
    for line in `sed -e 's/ /:/g;' < $BACKUPCONF`
    do
      DO=`echo $line | awk -F: '{print $1;}'`
      ZFS=`echo $line | awk -F: '{print $2;}'`
      if test "$DO" = "Y"; then
        echo "zfs destroy $ZFS@$SNAPNAME"
        $RUN && /sbin/zfs destroy $ZFS@$SNAPNAME
      fi
    done
}

# This clears the full snapshot only if -i (and -n) isn't specified
clear_full
echo "Backing up as '$BACKUPLABEL'"
postgres_start_backup
snap
postgres_stop_backup

