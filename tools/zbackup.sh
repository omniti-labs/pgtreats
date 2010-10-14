#!/bin/sh

BASESNAP=lastfull
INCREMENTAL=no
BACKUPCONF=/export/home/postgres/etc/zbackup.conf
BFILE=/var/log/pgods-backup.filelist
BPCMD=/usr/openv/netbackup/bin/bpbackup
BPLOG=/var/log/netbackup_backup.log
BPCLASS=PGods
BPSCHED=PGODS.UserBackup
RUN=true
INCDUMPDIR=/tmp
BMODE=ONLINE
DATAPREFIX=''
#DATAPREFIX=data/zfs_backups/userscape/
SEND=''
TARGET=''
PATH=$PATH:/usr/sbin
PGBINDIR=/opt/pgsql8311/bin
DATABASE_PORT=5432

Usage() {
cat <<EOF
$0: [-f] [-i] [-n] -p <port_number> -m <online> <offline> -s <netbackup> <zfs> -t <zfs send target> -l <label>
        -m              backup mode <online> or <offline>  (default online)
        -n              just describe the process (don't do it).
        -p              port which database runs on (default 5432)
        -s              use Netbackup or ZFS send.
        -t              target for ZFS send.
        -f              force a backup even if one is running.
        -i              perform an incremental since the last full (implies -s).
        -l <label>      backup using label: <label>
EOF
}

  set -- `getopt fis:t:m:np:l: $*`
  if [ $? != 0 ]
  then
    Usage
    exit 2
  fi
  for i in $*
  do
    case $i in
      -f)           FORCE=yes; shift;;
      -s)           SEND=`echo $2 | tr '[:lower:]' '[:upper:]'`; shift 2;;
      -t)           TARGET=$2; shift 2;;
      -i)           INCREMENTAL=yes; shift;;
      -l)           BACKUPLABEL=$2; shift 2;;
      -p)           DATABASE_PORT=$2; shift 2;;
      -m)           BMODE=`echo $2 | tr '[:lower:]' '[:upper:]'`; shift 2;;
      -n)           RUN=false; shift;;
      --)           shift; break;;
    esac
  done

if test "$SEND" = "ZFS" -a -z "$TARGET"; then
        echo "\nZFS send requires -t TARGET\n"
        Usage
        exit 1
fi

if test -z "$BACKUPLABEL"; then
  BACKUPLABEL=`date +%Y%m%d`
fi

echo "$0:"
echo "  backuplabel: $BACKUPLABEL"
if test "$INCREMENTAL" = "yes"; then
  SNAPNAME="incremental"_$BACKUPLABEL
  HISNAP=`zfs list -t snapshot -o name | egrep -i 'lastfull|incremental' | cut -f2 -d"@" | cut -f2 -d'_' | uniq | sort | tail -1`
  BASESNAP=`zfs list -t snapshot -o name | grep $HISNAP | cut -f2 -d"@" | tail -1`
  BFILE="$BFILE.i"
  echo "  incremental"
else
  SNAPNAME=${BASESNAP}_${BACKUPLABEL}
  echo "  full"
fi

sanity() {
  if test -f $BFILE -a "x$FORCE" != "xyes" ; then
    echo "backup in progress ($BFILE exists)."
    exit
  fi

  for ZPOOL in `zfs list -o name,mountpoint | sed '/^NAME/d;s/  */:/g' | grep -v '@'`
        do
            REPORT_POOL=`echo ${ZPOOL} | cut -f1 -d':'`
            REPORT_MOUNT=`echo ${ZPOOL} | cut -f2 -d':'`
            FOUND=`grep "${REPORT_POOL} ${REPORT_MOUNT}" $BACKUPCONF` 
            if test -z "$FOUND"; then
                echo "WARNING: ${REPORT_POOL} on ${REPORT_MOUNT} is not present in $BACKUPCONF"
            fi
        done


  for LINE in `grep "^Y" $BACKUPCONF | sed 's/ /:/'g | cut -f2 -d':'`
  do
        FULL_EXISTS=`zfs list -t snapshot -o name | grep -i lastfull | grep ${LINE}`
        if test "$INCREMENTAL" != "yes" -a "$FULL_EXISTS"  ; then
        echo "Base snapshot for "${LINE}" already exists."
        exit
        fi
        if test "$INCREMENTAL" = "yes" -a -z "$FULL_EXISTS"; then
        echo "We don't have a base snap for "${LINE}" for incremental backups."
        exit
        fi
  done
}

postgres_start_backup() {
  echo "starting postgres backup on label $BACKUPLABEL"
  $RUN && su - postgres -c "${PGBINDIR}/psql -p $DATABASE_PORT -c \"CHECKPOINT;\""
  $RUN && su - postgres -c "${PGBINDIR}/psql -p $DATABASE_PORT -c \"SELECT pg_start_backup('$BACKUPLABEL');\""
}
postgres_stop_backup() {
  echo "stopping postgres backup on label $BACKUPLABEL"
  $RUN && su - postgres -c "${PGBINDIR}/psql -p $DATABASE_PORT -c \"SELECT pg_stop_backup();\""
}

snap() {
  for line in `sed -e 's/ /:/g;' < $BACKUPCONF`
  do
    DO=`echo $line | awk -F: '{print $1;}'`
    ZFS=`echo $line | awk -F: '{print $2;}'`
#    MOUNT=`echo $line | awk -F: '{print $3;}'`
    if test "$DO" = "Y"; then
      echo "zfs snapshot $ZFS@$SNAPNAME"
      $RUN && /sbin/zfs snapshot $ZFS@$SNAPNAME
    fi
  done
}

clear_full() {
  if test "$INCREMENTAL" != "yes"; then
    FULL_DATE=`date +%Y%m%d`
    for line in `sed -e 's/ /:/g;' < $BACKUPCONF | grep "^Y"`
        do
          ZFS=`echo $line | awk -F: '{print $2;}'`
          for OLD_SNAPNAME in `zfs list -t snapshot -o name | grep -i lastfull | grep -i ${ZFS} |  grep -v ${FULL_DATE}`
        do
          echo "zfs destroy $OLD_SNAPNAME"
          $RUN && /sbin/zfs destroy $OLD_SNAPNAME
        done
        done
  fi
}

clear_incrementals() {
  zfs list -t snapshot -o name,creation | grep "incremental_" | cut -f1 -d' ' | grep -v $BACKUPLABEL |
   while read SNAPLABEL 
       do
             echo "zfs destroy $SNAPLABEL";
             $RUN && /sbin/zfs destroy $SNAPLABEL
       done
}

backup() {
  BACKEDUP="no"
  $RUN && touch $BFILE
  for line in `sed -e 's/ /:/g;' < $BACKUPCONF`
  do
    DO=`echo $line | awk -F: '{print $1;}'`
    ZFS=`echo $line | awk -F: '{print $2;}'`
    MOUNT=`echo $line | awk -F: '{print $3;}'`
    if test "$DO" = "Y"; then
      if test "$INCREMENTAL" = "yes"; then
        FILE=`echo $ZFS | sed -e 's/\//:/g;'`
        echo "/sbin/zfs send -i $ZFS@$BASESNAP $ZFS@$SNAPNAME  >> $INCDUMPDIR/$FILE.$SNAPNAME.incremental"
        $RUN && mkfifo $INCDUMPDIR/$FILE.$SNAPNAME.incremental
        $RUN && /sbin/zfs send -i $ZFS@$BASESNAP $ZFS@$SNAPNAME  >> $INCDUMPDIR/$FILE.$SNAPNAME.incremental &
        $RUN && $BPCMD -w -c $BPCLASS -s $BPSCHED -k "INCREMENTAL" -L $BPLOG $INCDUMPDIR/$FILE.$SNAPNAME.incremental &
        elif test "$INCREMENTAL" != "yes"; then
#elif test "$SEND" = "NETBACKUP"; then
        FILE=`echo $ZFS | sed -e 's/\//:/g;'`
        echo "/sbin/zfs send $ZFS@$SNAPNAME  >> $INCDUMPDIR/$FILE.$SNAPNAME.full"
        $RUN && mkfifo $INCDUMPDIR/$FILE.$SNAPNAME.full
        $RUN && /sbin/zfs send $ZFS@$SNAPNAME  >> $INCDUMPDIR/$FILE.$SNAPNAME.full &
        $RUN && $BPCMD -w -c $BPCLASS -s $BPSCHED -k "FULL" -L $BPLOG $INCDUMPDIR/$FILE.$SNAPNAME.full &
      else
        # Normal tar-like backups happen "on the spot" and in parallel
        echo $MOUNT/.zfs/snapshot/$SNAPNAME
        $RUN && $BPCMD -w -c $BPCLASS -s $BPSCHED -k "FULL" -L $BPLOG $MOUNT/.zfs/snapshot/$SNAPNAME &
      fi
    fi
  done

  # Wait for our ZFS send commands to finish (they should be done already)
  wait
  $RUN && rm $BFILE
}

zfs_send() {
    for line in `sed -e 's/ /:/g;' < $BACKUPCONF`
    do
      DO=`echo $line | awk -F: '{print $1;}'`
      ZFS=`echo $line | awk -F: '{print $2;}'`
      if test "$DO" = "Y"; then
        if test "$SEND" = "ZFS"; then
        if test "$INCREMENTAL" = "yes"; then
          echo "ssh $TARGET zfs rollback -r $DATAPREFIX$ZFS@$BASESNAP"
          echo "zfs send -i $ZFS@$BASESNAP $ZFS@$SNAPNAME | ssh $TARGET zfs receive -F $DATAPREFIX$ZFS@$SNAPNAME"
          $RUN && ssh $TARGET zfs rollback -r $DATAPREFIX$ZFS@$BASESNAP
          $RUN && /sbin/zfs send -i $ZFS@$BASESNAP $ZFS@$SNAPNAME | ssh $TARGET zfs receive -F $DATAPREFIX$ZFS@$SNAPNAME
        else
          echo "zfs send $ZFS@$SNAPNAME | ssh $TARGET zfs receive -F $DATAPREFIX$ZFS@$SNAPNAME"
          $RUN && /sbin/zfs send $ZFS@$SNAPNAME | ssh $TARGET zfs receive -F $DATAPREFIX$ZFS@$SNAPNAME
        fi
        fi
      fi
    done
}


# This clears the full snapshot only if -i (and -n) isn't specified

clear_full
sanity
echo "Backing up as '$BACKUPLABEL'"

if test "$BMODE" = "ONLINE" ; then
        postgres_start_backup
        snap
        postgres_stop_backup
else
        snap
fi

if test "$SEND" = "NETBACKUP" -a -f $BPCMD; then
backup
fi

if test "$SEND" = "ZFS"; then
zfs_send
fi

clear_incrementals
