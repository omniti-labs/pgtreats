#!/bin/bash
# Copyright (c) 2007 OmniTI, Inc.  All rights reserved.
# This is released for use under the same license as PostgreSQL itself.

# What you need: Solaris 10, a working postgres PITR slave with data in a
# ZFS filesystem

# You need a zone that is configured identically to the zone running
# the postgres PITR slave.
#
# We have our globalzone accessing postgres data in:
# /data/postgres/82 @ store2/postgres/82 on ZFS
#   with xlogs in /data/postgres/82_xlogs on a different ZFS mount.
# All our incoming (master) WAL logs are in /data/postgres/82_walarchives
# It is important to note that by copying the contents of the /data/postgres/82 
# filesystem, we _do not_ get xlogs or WALs.

# The zone has a dataset added called "pool/zonename" (store2/clonedb) here.
# We will clone the PITR slave's data into the zones dataset, mount it up
# and let it spin... There are a few other steps, but we'll take care of that
# too.

ZONE=clonedb
SRCDATA=store2/postgres/82
DSTDATA=store2/clonedb/82

DATAMOUNT=/data/postgres/82
WALS=/data/postgres/82_walarchives

ZONEDO="zlogin $ZONE"
ZONEPATH=`zonecfg -z clonedb info zonepath | awk '{print $2;}'`

WAL_NEEDED=`ls -rt $WALS | tail -1`

log() {
  NOW=`date`
  echo "[$NOW] $*"
}

# Stop postgres
log "Stopping postgres in $ZONE"
$ZONEDO svcadm disable -s postgres
# Drop the old copy
log "Dropping clone and base snapshot"
$ZONEDO zfs destroy $DSTDATA
zfs destroy $SRCDATA@clonebase

# Snap the source.
log "Snapshot $SRCDATA"
zfs snapshot $SRCDATA@clonebase

# Clone the data
log "Clone to $DSTDATA"
zfs clone $SRCDATA@clonebase $DSTDATA

log "Mount $DSTDATA at $DATAMOUNT in $ZONE"
$ZONEDO zfs mount $DSTDATA
$ZONEDO zfs set mountpoint=$DATAMOUNT $DSTDATA
log "Copy last WAL [$WAL_NEEDED]"
cp -p $WALS/$WAL_NEEDED $ZONEPATH/root/$WALS/$WAL_NEEDED
$ZONEDO touch $DATAMOUNT/failover
log "Make it active [induce failover]"
$ZONEDO find $DATAMOUNT/pg_log/. -name postgres\*log -exec rm {} \\\;
log "Start postgres in $ZONE"
$ZONEDO svcadm enable postgres

sleep 1
TRIES=200
while [ $TRIES -gt 0 ]
do
  STATUS=`echo "select 'database system is up';" | \
	$ZONEDO psql postgres postgres 2>&1 | \
	grep 'database system is' |
	sed -e 's/^ *//; s/ *$//;'`
  if [ -z "$STATUS" ]; then
    log "Error: $STATUS"
    exit
  elif [ "$STATUS" = "database system is up" ]; then
    log "System up"
    exit
  fi
  TRIES=$(($TRIES - 1))
done

log "Timeout waiting for system to come up, please investigate"
