NAME 

    table_growth - a set of scripts for reporting table size growth in postgres

SYNOPSIS 

    A set of schema, functions, and shell script to report table size growth.


VERSION 

    This document refers to version 0.2 of table_growth, released December 9th,
    2008

USAGE 

    To use table_growth, you need to add the schema for holding table size
    information, install the included functions into your database, set up a cron
    job to do the data population, and set up a cron job to send the reports. We
    typically setup the conr jobs to look like this:

    15 0 * * * psql -c "select otools.collect_table_growth(); select
    otools.summarize_table_growth(); " 1>/dev/null 

    45 6 1 * * /var/lib/pgsql/scripts/table_growth_report.sh 1>/dev/null

BUGS AND LIMITATIONS 

    The package is designed to work on single databases at a time, if you want to
    report on multiple databases in a cluster, you will need to install this in
    each individual database, and also set cron jobs independently for each
    database.

    Some actions may not work on older versions of Postgres (before 8.1)

    Please report any problems to robert@omniti.com.

TODO 

LICENSE AND COPYRIGHT 

    Copyright (c) 2008 OmniTI, Inc.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    1. Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
    2. Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.


    THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
    WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
    MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
    EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
    PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
    BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
    IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.

