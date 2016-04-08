#!/usr/bin/python3

import sys
import time
import socket
import os
import argparse
import gnupg

parser = argparse.ArgumentParser (
                                    formatter_class=argparse.RawDescriptionHelpFormatter,
                                    description="This program takes a database dump, encrypts and uploads it to S3",
                                    epilog='''------
USAGE:
------
    Dump only: python3 ./pg_dump_upload.py -c /etc/pg_dump_upload.conf -dp /usr/bin/pg_dump -da /usr/bin/pg_dumpall -df /data/backups -p 5432
    Dump with encryption: python3 ./pg_dump_upload.py -c /etc/pg_dump_upload.conf -dp /usr/bin/pg_dump -da /usr/bin/pg_dumpall -df /data/backups -p 5432 \\
                                    --gpg -gp /usr/bin/gpg -r recipient_name -gd /home/postgres/.gnupg -gf database1,database2...
    Dump with encryption and upload: python3 ./pg_dump_upload.py -c /etc/pg_dump_upload.conf -dp /usr/bin/pg_dump -da /usr/bin/pg_dumpall -df /data/backups -p 5432 \\
                                    --gpg -gp /usr/bin/gpg -r recipient_name -gd /home/postgres/.gnupg -gf database1,database2... \\
                                    --s3 -sp /usr/bin/python26/bin -sf database1, database2... --upload_roles  -sl s3://bucket_name/ --verbose
                                       ''' )

args_general = parser.add_argument_group(title="General options")
args_general.add_argument('-n', '--hostname', default=socket.gethostname(), help='name of the machine')
args_general.add_argument('-p', '--port', default='5432', help='postgres cluster port, defaults to 5432')
args_general.add_argument('-c', '--config_file', default='/home/postgres/etc/pg_dump.conf', help='file containing contents to dump')
args_general.add_argument('-l', '--lock_file', default='/var/tmp/postgres_dump.lock', help='this file ensures only one backup job runs at a time')
args_general.add_argument('-v', '--verbose', action='store_true', help='produced log with more information about the execution, helpful for debugging issues')
args_general.add_argument('--cleanup', choices=['encrypted', 'unencrypted', 'all'], help='choose which files to remove locally after files are uploaded')

args_postgres = parser.add_argument_group(title="Postgres options")
args_postgres.add_argument('-dp', '--pg_dump_path', help='path to pg_dump command')
args_postgres.add_argument('-da', '--pg_dumpall_path',help='path to pg_dumpall command')
args_postgres.add_argument('-df', '--dump_file_path', help='The backup directory to store the pg dump files. The script creates sub directories per database, so only give the parent directory path')

args_gpg = parser.add_argument_group(title='GPG options')
args_gpg.add_argument('--gpg', action='store_true', help='specify this option to encrypt the files')
args_gpg.add_argument('-gp', '--gpg_path', help='path to gpg binary')
args_gpg.add_argument('-r', '--recipient', help='recipient\'s key name or email')
args_gpg.add_argument('-gd', '--gnupg_dir_path', help='path to .gnupg directory')
args_gpg.add_argument('-gf', '--gpg_encrypt_files', default='all', help='comma separated list of database backups to encrypt')

args_s3 = parser.add_argument_group(title='S3 options')
args_s3.add_argument('--s3', action='store_true', help='specify this option to upload files to S3. Encryption of files is a prerequisite (see --gpg)')
args_s3.add_argument('-sp', '--s3_path',  help='path to s3cmd executable')
args_s3.add_argument('-sf', '--s3_upload_files', default='all', help='comma separated list of database backups to upload to S3')
args_s3.add_argument('-sl', '--s3_bucket_link', help='S3 bucket link on AWS')

args = parser.parse_args()

if args.s3 and not args.gpg:
    print("ERROR: Uploading to S3 without encrypting is not permitted. Please encrypt your files first (see --gpg)")
    sys.exit(1)
# Timestamp for backed up filenames
start_time = time.strftime("%Y-%m-%d_%H:%M:%S")

# Path normalizations and joins
config_file = os.path.normpath(args.config_file)
lock_file = os.path.normpath(args.lock_file)
pg_dump_path = os.path.normpath(args.pg_dump_path)
pg_dumpall_path = os.path.normpath(args.pg_dumpall_path)
dump_file_path = os.path.join(os.path.normcase(args.dump_file_path), '')
if args.gpg:
    gpg_path = os.path.normpath(args.gpg_path)
    gnupg_dir_path = os.path.normpath(args.gnupg_dir_path)
if args.s3:
    s3_path = os.path.join(os.path.normpath(args.s3_path), "s3cmd")
    s3_bucket_link = os.path.join(args.s3_bucket_link, '')

def check_lock():
    if os.path.isfile(lock_file):
        sys.exit('ERROR: lock file already exists: %s' % lock_file)
    else:
        open(lock_file, 'w+').close()
        if args.verbose:
            print('Lock file created.')


def take_dump():
    try:
        with open(config_file, 'r') as f:
            for db in f:
                if db.strip():
                    if args.verbose:
                        print("taking backup of " + db.split()[-1])
                    db = db.replace("\n", "")
                    db_name = db.split()[-1]
                    db_dump_file_name = os.path.join(dump_file_path, db_name, db_name + "_" + start_time + ".sql")
                    dump_command = pg_dump_path + " -p " + args.port + " -U postgres -v -Fc -f " + db_dump_file_name + " " + db + " 2>> " + os.path.join(dump_file_path, db_name, '') + db_name + "_" + start_time  + ".log"
                    print(dump_command)
                    os.system(dump_command)
                    if args.verbose:
                        print('backup of ' + db_name + ' completed successfully')
                        print('Dump Command: ' + dump_command)
                    if args.gpg and db_name in args.gpg_encrypt_files.split(',') or args.gpg and args.gpg_encrypt_files == 'all':
                        gpg_encrypt(db_dump_file_name, db_name)
                    if args.cleanup in ['unencrypted', 'all']:
                        os.remove(db_dump_file_name)
                        if args.verbose:
                            print(db_dump_file_name + ' removed from local machine')

    except:
        print('ERROR: bash command did not execute properly')


def take_dumpall():
    try:
        if not os.path.exists(os.path.join(dump_file_path, 'globals')):
            os.makedirs(os.path.join(dump_file_path, 'globals'))
        global_file_path = os.path.join(dump_file_path, 'globals', '')
        print(global_file_path)
    except:
        print('ERROR: Could not find globals directory. Failed to create. Check permissions')
        sys.exit(1)
    try:
           if args.verbose:
                print("Taking globals dump")
           global_file_name = global_file_path + args.hostname + "_" + start_time  + "_" + "roles.sql"
           dumpall_command = pg_dumpall_path + " -p" + args.port + " -g " + " 1>> " + global_file_name
           os.system(dumpall_command)
           if args.verbose:
                print("Dumpall Command: " + dumpall_command)
                print('backup of globals completed successfully')
           if args.gpg:
                if args.verbose:
                    print("Encrypting global file")
                gpg = gnupg.GPG(gpgbinary=gpg_path, gnupghome=gnupg_dir_path)
                plain_text_role = open(global_file_name, 'rb')
                encrypted_role = global_file_name + ".gpg"
                gpg.encrypt_file(plain_text_role, args.recipient, output=encrypted_role)
                if args.verbose:
                    print('backup of globals  encrypted successfully')
           if args.s3 and args.gpg:
                if args.verbose:
                    print('uploading globals to s3')
                s3_command = s3_path + " put FILE " + encrypted_role + " " + s3_bucket_link
                os.system(s3_command)
                if args.verbose:
                    print("S3 Upload Command: " + s3_command)
                    print('backup of globals uploaded successfully')
                if args.cleanup == 'encrypted':
                    os.remove(encrypted_role)
                    if args.verbose:
                        print("Removed file " + encrypted_role)
                elif args.cleanup == 'unencrypted':
                    os.remove(global_file_name)
                    if args.verbose:
                        print("Removed file " + global_file_name)
                elif args.cleanup == 'all':
                    os.remove(encrypted_role)
                    os.remove(global_file_name)
                    if args.verbose:
                        print("Removed files " + global_file_name + " and " + encrypted_role)
                

    except:
        print('ERROR: dumpall command did not execute properly')


def gpg_encrypt(file_to_encrypt, db_name):
    try:
        gpg = gnupg.GPG(gpgbinary=gpg_path, gnupghome=gnupg_dir_path)

        try:
                if args.verbose:
                    print("encrypting " + file_to_encrypt)
                plain_text_file = open(file_to_encrypt, 'rb')
                encrypted_file = file_to_encrypt + ".gpg"
                gpg.encrypt_file(plain_text_file, args.recipient, output=encrypted_file)
                if args.verbose:
                    print(file_to_encrypt + ' encrypted successfully')
                if args.s3 and db_name in args.s3_upload_files.split(',') or args.s3 and args.s3_upload_files == 'all':
                    s3_upload(encrypted_file)
                if args.cleanup in ['encrypted', 'all']:
                    os.remove(encrypted_file)
                    if args.verbose:
                        print(encrypted_file + ' removed from local machine')
                
        except:
            print('ERROR: Could not encrypt file')

    except:
        print('ERROR: Could not find gpg executable and/or gnupg directory')


def s3_upload(file_to_upload):
    try:
            if args.verbose:
                print("uploading " + file_to_upload)
            s3_command = s3_path + " put " + file_to_upload + ' ' + s3_bucket_link
            os.system(s3_command)
            if args.verbose:
                print("S3 Upload Command: " + s3_command)
                print(file_to_upload + ' uploaded successfully...')

    except:
        print('ERROR: s3cmd did not execute successfully')

    if args.verbose:
        list_contents = s3_path + " ls " + s3_bucket_link + file_to_upload.split('/')[-1]
        os.system(list_contents)


def cleanup():
    if os.path.exists(lock_file):
        os.remove(lock_file)

    if args.verbose:
        print('All cleaned up.')


check_lock()
take_dumpall()
take_dump()
cleanup()
