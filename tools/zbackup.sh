#!/bin/sh

BASESNAP=lastfull
INCREMENTAL=no
BACKUPCONF=/etc/zbackup.conf
BFILE=/var/log/pgods-backup.filelist
BPCMD=/usr/openv/netbackup/bin/bpbackup
BPLOG=/var/log/netbackup_backup.log
BPCLASS=PGods
BPSCHED=PGODS.UserBackup
RUN=true
INCDUMPDIR=/tmp

usage() {
cat <<EOF
$0: [-f] [-i] [-n] [-s] -l <label>
        -n              just describe the process (don't do it).
        -s              use ZFS send.
        -f              force a backup even if one is running.
        -i              perform an incremental since the last full (implies -s).
        -l <label>      backup using label: <label>
EOF
}

  set -- `getopt fisnl: $*`
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
      -i)           INCREMENTAL=yes; shift;;
      -l)           BACKUPLABEL=$2; shift 2;;
      -n)           RUN=false; shift;;
      --)           shift; break;;
    esac
  done

if test -z "$BACKUPLABEL"; then
  BACKUPLABEL=`date +%Y%m%d`
fi

echo "$0:"
echo "  backuplabel: $BACKUPLABEL"
if test "$INCREMENTAL" = "yes"; then
  SNAPNAME=$BACKUPLABEL
  BFILE="$BFILE.i"
  echo "  incremental"
else
  SNAPNAME=$BASESNAP
  echo "  full"
fi

sanity() {
  MATCHCNT=0
  SNAPCNT=0
  if test -f $BFILE -a "x$FORCE" != "xyes" ; then
    echo "backup in progress ($BFILE exists)."
    exit
  fi
  for line in `zfs list -H | awk '{print $1":"$5;}'`
  do
    ZFS=`echo $line | awk -F: '{print $1;}'`
    MOUNT=`echo $line | awk -F: '{print $2;}'`
    MATCH=`grep '^[YN] '$ZFS' '$MOUNT'$' $BACKUPCONF`
    USE=`echo $MATCH | awk '{print $1;}'`
    SNAP=`echo $ZFS | awk -F@ '{print $2;}'`
    # Here, if we have the snap and we're in "full" node, we die
    if test "X$SNAP" = "X$BASESNAP"; then
      if test "$INCREMENTAL" != "yes" ; then
        echo "Base snapshot already exists."
        exit
      fi
      # These are the base snapshots off which we'll do incrementals
      if test -z "$MATCH"; then
        SNAPCNT=`expr $SNAPCNT + 1`
      fi
    fi
    if test -z "$MATCH" -a -z "$SNAP" ; then
      echo "WARNING: $ZFS on $MOUNT is not present in $BACKUPCONF"
    fi
    if test -z "$SNAP" -a "$USE" = "Y" ; then
      # These are the "real" mounts we want to backup
      MATCHCNT=`expr $MATCHCNT + 1`
    fi
  done

  # or, if we don't have the snaps and we're in incremental mode, we die
  if test "$SNAPCNT" != "$MATCHCNT" -a "$INCREMENTAL" = "yes"; then
    echo "We don't have base snaps for incremental backups."
    exit
  fi
}

postgres_start_backup() {
  echo "starting postgres backup on label $BACKUPLABEL"
  $RUN && su - postgres -c "/bin/psql -c \"CHECKPOINT;\""
  $RUN && su - postgres -c "/bin/psql -c \"SELECT pg_start_backup('$BACKUPLABEL');\""
}
postgres_stop_backup() {
  echo "stopping postgres backup on label $BACKUPLABEL"
  $RUN && su - postgres -c "/bin/psql -c \"SELECT pg_stop_backup();\""
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
  if test "$INCREMENTAL" != "yes"; then
    for line in `sed -e 's/ /:/g;' < $BACKUPCONF`
    do
      DO=`echo $line | awk -F: '{print $1;}'`
      ZFS=`echo $line | awk -F: '{print $2;}'`
      if test "$DO" = "Y"; then
        echo "zfs destroy $ZFS@$SNAPNAME"
        $RUN && /sbin/zfs destroy $ZFS@$SNAPNAME
      fi
    done
  fi
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
        echo "/sbin/zfs send -i $ZFS@$BASESNAP $ZFS@$SNAPNAME | /bin/bzip2 -3c >> $INCDUMPDIR/$FILE.$SNAPNAME.incremental"
        $RUN && mkfifo $INCDUMPDIR/$FILE.$SNAPNAME.incremental
        $RUN && /sbin/zfs send -i $ZFS@$BASESNAP $ZFS@$SNAPNAME >> $INCDUMPDIR/$FILE.$SNAPNAME.incremental &
        $RUN && $BPCMD -w -c $BPCLASS -s $BPSCHED -L $BPLOG $INCDUMPDIR/$FILE.$SNAPNAME.incremental &
      elif test "$SEND" = "yes"; then
        FILE=`echo $ZFS | sed -e 's/\//:/g;'`
        echo "/sbin/zfs send $ZFS@$SNAPNAME >> $INCDUMPDIR/$FILE.$SNAPNAME.full"
        $RUN && mkfifo $INCDUMPDIR/$FILE.$SNAPNAME.full
        $RUN && /sbin/zfs send $ZFS@$SNAPNAME >> $INCDUMPDIR/$FILE.$SNAPNAME.full &
        $RUN && $BPCMD -w -c $BPCLASS -s $BPSCHED -L $BPLOG $INCDUMPDIR/$FILE.$SNAPNAME.full &
      else
        # Normal tar-like backups happen "on the spot" and in parallel
        echo $MOUNT/.zfs/snapshot/$SNAPNAME
        $RUN && $BPCMD -w -c $BPCLASS -s $BPSCHED -L $BPLOG $MOUNT/.zfs/snapshot/$SNAPNAME &
      fi
    fi
  done

  # Wait for our ZFS send commands to finish (they should be done already)
  wait
  $RUN && rm $BFILE
}

# This clears the full snapshot only if -i (and -n) isn't specified
clear_full
sanity
echo "Backing up as '$BACKUPLABEL'"
postgres_start_backup
snap
postgres_stop_backup
backup

