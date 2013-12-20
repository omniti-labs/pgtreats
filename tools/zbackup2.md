zbackup documentation
=====================================

This is a bash script to automate the creation of ZFS backups of selective datasets. 

STRUCTURE:
-------------------------------------

The script is divided into a couple of functions, which are executed in the following sequence:

**read_params()** - This function read the command line configuration parameters. More on this parameters can be found in the configuration section of this file.

**sanity_check()** - This function checks if there is already an ongoing backup, and if so, the program is terminated. If not, it goes on to check if a backup method is specified (netbackup, zfs send, bacula or tar). 

**postgres_start_backup()** - prior to taking a zfs snap, this function issues a checkpoint and pg_start_backup(<label>) to let the database know that a backup is in process.

**zfs_snap()** - This function executes a zfs snap to take snapshots of each dataset mentioned in the .conf file (more on this in the configuration section).

**postgres_stop_backup()** - This function issues a pg_stop_backup() command.

**backup()** - This function loops over the list of the datasets to be backed up and issues zfs_send() for each one.

**zfs_send()** - This function sends the zfs snapshot after compressing it to the destination. Depending on whether the user specifies incremental option, when feasible if will just send the incremental snapshot. If incremental is false, it will always send the complete snapshot. 

**clear_zfs_snaps()** - Once the backups are created and sent, this function releases the holds from the snapshots created, and destroys them.

OPTIONS
-------------------------------------

**-o**  When set, the script knows that the database is up and running and to take a backup, it will need to issue the pg_start_backup(<label>) and pg_stop_backup commands before and after taking the snapshots respectively. If not set to true, the script will directly issue the zfs snap command. 

**-f** When set to true, the script ignores if a lockfile is already in place and goes on to create a backup.

**-i** When set to true, the script will create incremental snapshots whenever possible, that is, as long as it already has a base snapshot. If not, it will just take the whole snapshot and ignore this option. 

**-p** Port at which postgres is running. Need to connect to the database to issue pg_start_backup and pg_stop_backup commands.

**-z** The target location where the compressed backup files will be stored. This should only be the hostname, the directory path is provided as part of the configuration parameters.

**-t** tar path, when tar is used to compress the files.

**-l** the label used when issuing the pg_start_backup command in postgres. 

**-c** path for alternate configuration file.

CONFIGURATION PARAMETERS
-------------------------------------

**HOSTNAME** - name of the host on which the backups are created.

**BACKUPCONF** - complete path of the configuration file. This file contains full name of all the datasets that need to be backed up. Every name is given in a new line.

**PSQLCMD** - This is the path to psql command

**LOCKFILEPATH** - the location where the lockfile is created

**OFFSITEDIR** - the location on the target backup host where the backup files will be stored


