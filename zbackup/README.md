# Zbackup #

## Overview ##

The ```zbackup.sh``` script is used to perform "hot" backups using native features of ZFS in conjunction with the command-line Veritas !NetBackup utilities.  ZFS allows us to take a live snapshot of any ZFS filesystems on the system.  Because ZFS only records the changed blocks, it can complete a full snapshot at blazing speeds.

Once the snapshot is ready, we can use ```zfs send``` to pipe it through a fifo.  In the meantime, ```zbackup.sh``` starts up another process to execute the !NetBackup client.  It reads in from the fifo and sends the backup stream to a policy on the !NetBackup media server.

## Configuration ##

Zbackup relies on a very simple configuration file delimited by whitespace.  Each entry describes a filesystem, its mount point, and whether ```zbackup.sh``` should perform a backup of that filesystem.  In this example, we have four zfs mount points but we are only backing up our PostgreSQL data in ```/pgdata/main```.

```
N zfsarray /zfsarray
N zfsarray/crash /var/crash
N zfsarray/homes /export/home
Y zfsarray/pgdata /pgdata/main
```

## Details ##

We'll start off by reviewing the variables defined at the top of ```zbackup.sh``` and looking at the order in which our tasks are called.  Then we'll dig deeper to see how each routine performs its functionality.

### Variables ###

```
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
```

 * BASESNAP - The suffix to append to our FULL backup snapshot.  This can be seen using ```zfs list```.
 * INCREMENTAL - By default, we want to run a FULL backup.  This can be overridden with the '''-i''' option to ```zbackup.sh```.
 * BACKUPCONF - Where to find our configuration file.
 * BFILE - The lock file used by ```zbackup.sh```.  Zbackup will exit if this file exists.  Force override with the '''-f''' flag.
 * BPCMD - Path to the !NetBackup command-line backup utility.
 * BPLOG - Path to the !NetBackup log file.
 * BPCLASS - Name of our !NetBackup policy, as defined on the !NetBackup media server.
 * BPSCHED - Name of our !NetBackup policy schedule, as defined on the !NetBackup media server.
 * RUN - By overriding this value with the '''-n''' flag, Zbackup will tell us what it ''would have'' done, without actually performing the backup.
 * INCDUMPDIR - Directory where we will create our fifo.

### Workflow ###

```
clear_full
sanity
postgres_start_backup
snap
postgres_stop_backup
backup
```

Zbackup starts by performing a ```zfs destroy``` on any FULL snapshots we might be duplicating (''FULL'' mode).  It then runs a validation routine to confirm that our FULL snapshot was destroyed (''FULL'' mode) or that we have a FULL snapshot available (''INCREMENTAL'' mode).

If everything checks out ok, we tell PostgreSQL to prepare for an online backup.  Specifically, we tell it to force a transaction log [checkpoint](http://www.postgresql.org/docs/8.2/static/sql-checkpoint.html) and begin the online backup ([pg_start_backup()](http://postgresql.mirrors-r-us.net/docs/8.2/static/functions-admin.html#FUNCTIONS-ADMIN-BACKUP-TABLE)).

Next, we perform the actual ```zfs snapshot``` to fifo.  Once this is completed, we inform PostgreSQL that we are finished ([pg_stop_backup()](http://postgresql.mirrors-r-us.net/docs/8.2/static/functions-admin.html#FUNCTIONS-ADMIN-BACKUP-TABLE)).

Finally, we start the !NetBackup client to read from the fifo and begin the backup to tape.

## Troubleshooting ##

This section is not meant to be an exhaustive dissection of all that can go wrong with ```zbackup.sh```.  Rather, it is intended to give the new user an introduction into using the tools behind Zbackup.  If we can reproduce a problem manually, it provides us with better feedback and a better understanding of where the process flow breaks down.

First, you should become familiar with how some of the basic ZFS functionality works.  At a very rudimentary level,```zfs list``` will tell us which ZFS filesystems are available and in use.


```
$ zfs list
NAME                         USED  AVAIL  REFER  MOUNTPOINT
intmirror                   24.6G  42.3G  24.5K  /intmirror
intmirror/pgdata            24.6G  42.3G  12.9G  /pgdata/main
intmirror/pgdata@20080326   3.87G      -  12.6G  -
intmirror/pgdata@20080327   4.09G      -  12.8G  -
intmirror/pgdata@lastfull   3.75G      -  12.7G  -
storedge_2                  1.66T   757G  1.45M  /storedge_2
storedge_2/pgdata           1.66T   757G  1.48T  /pgdata/alldata1
storedge_2/pgdata@20080326  42.4G      -  1.43T  -
storedge_2/pgdata@20080327  38.4G      -  1.43T  -
storedge_2/pgdata@lastfull  53.5G      -  1.48T  -
```

Let's imagine that we're having difficulties with the FULL backups for ```intmirror/pgdata```.  We've already created a manual snapshot that we can use for testing.  With this we can emulate ```zbackup.sh``` by issuing a ```zfs send``` to the fifo.  If it doesn't already exist, you'll need to create the fifo.

```
# zfs send intmirror/pgdata@lastfull >> /tmp/intmirror\:pgdata.lastfull.full
```

If no problems were reported, we can proceed to running the !NetBackup client.  In a separate terminal, run the following (changing policy and schedule names were appropriate).

```
# /usr/openv/netbackup/bin/bpbackup -w -c PGdata -s PGDATA.UserBackup -L /var/log/netbackup_backup.log \
/tmp/intmirror\:pgdata.lastfull.full
```

If there are any problems with the policy configuration, you should see errors at this point.  Otherwise, everything should be running smoothly and you should be able to monitor the backup job on the media server.
