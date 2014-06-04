#!/usr/bin/bash

set -e 
set -x

######## CONFIGURATION ########
REMOTE_DIR="/data/zbackup/.../..."         # Where zfs filesystem backups are stored
REMOTE_SERVER="user@backup.full.name"         # The server where the zfs backups are stored
ZFS_PATH="/usr/sbin/zfs"             # Full path of the zfs command
HOSTNAME=`hostname`         # Hostname of the server on which restore is to be done (This script assumes that this is the server where this script is being run)
SVCADM_PATH="/usr/sbin/svcadm"
PG_SERVICE_NAME="postgres"
PGDATA_PATH="/data/set/pgdata"
XLOG_PATH="/data/set/xlog"
WALARCHIVE_PATH="/data/set/walarchive"
PG_XLOG_PATH="$PGDATA_PATH/9.2/pg_xlog"
XLOG_FILES_PATH="$XLOG_PATH/9.2"
######## CONFIGURATION ########


#Calling script to stop postgres
sudo $SVCADM_PATH disable $PG_SERVICE_NAME

# If datasets already exist, then destroy them so that they can be recreated with the snapshots
    if [ -d "$PGDATA_PATH" ]; then
        echo "Directory pgdata exists on this server, destroying it"
        sudo $ZFS_PATH destroy -r $PGDATA_PATH
    fi
    if [ -d "$XLOG_PATH" ]; then
        echo "Directory xlog exists on this server, destroying it"
        sudo $ZFS_PATH destroy -r $XLOG_PATH
    fi
    if [ -d "$WALARCHIVE_PATH" ]; then
        echo "Directory walarchive exists on this server, destroying it"
        sudo $ZFS_PATH destroy -r $WALARCHIVE_PATH
    fi

# Find latest full backup files from the remote server
LATEST_XLOG_FILE=`ssh $REMOTE_SERVER ls -t1 $REMOTE_DIR/ | grep .full.zfs.gz$ | grep xlog | head -n1` 
LATEST_WALARCHIVE_FILE=`ssh $REMOTE_SERVER ls -t1 $REMOTE_DIR/ | grep .full.zfs.gz$ | grep walarchive | head -n1`
LATEST_PGDATA_FILE=`ssh $REMOTE_SERVER ls -t1 $REMOTE_DIR/ | grep .full.zfs.gz$ | grep pgdata | head -n1`

# Get new names of the snapshots
echo "latest xlog file: $LATEST_XLOG_FILE"
echo "latest walarchive file: $LATEST_WALARCHIVE_FILE"
echo "latest pgdata file: $LATEST_PGDATA_FILE"

# Create datasets from the snapshots
echo "Creating xlog dataset"
ssh $REMOTE_SERVER "sudo gzip -dc $REMOTE_DIR/$LATEST_XLOG_FILE" | sudo $ZFS_PATH receive -F $XLOG_PATH
echo "xlog dataset created."

echo "Creating walarchive dataset"
ssh $REMOTE_SERVER "sudo gzip -dc $REMOTE_DIR/$LATEST_WALARCHIVE_FILE" | sudo $ZFS_PATH receive -F $WALARCHIVE_PATH
echo "walarchive dataset created."

echo "Creating pgdata dataset. This will take a while."
ssh $REMOTE_SERVER "sudo gzip -dc $REMOTE_DIR/$LATEST_PGDATA_FILE" | sudo $ZFS_PATH receive -F $PGDATA_PATH
echo "pgdata dataset created."

echo "Restoration Completed. Recreating pg_xlog symlink..."
sudo rm -r $PG_XLOG_PATH
sudo ln -s $XLOG_FILES_PATH $PG_XLOG_PATH

echo "Chef run complete, now starting postgres as user postgres"
sudo $SVCADM_PATH enable $PG_SERVICE_NAME
echo "Database restored and restarted successfully"

echo "IMPORTANT: If restoring to a dev database with lesser resources, consider modifying config parameters \"shared_buffers = 1GB\" and \"effective_cache_size = 4GB\" in postgresql.conf file before starting postgres."
