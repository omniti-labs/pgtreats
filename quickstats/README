NAME 

    quickstats - a set of scripts for gathering transaction information in
    postgres

SYNOPSIS 

    A set of schema and functions for gathering transaction information
    (insert/update/delete), which can be used to report on transaction rates over
    time.

VERSION 

    This document refers to version 0.1 of quickstats, released December 9th, 2008

USAGE 

    To use quickstats , install quickstats_schema.sql in the database you want to
    gather data on. You then need to schedule a cron job to gather the statistics.

    */5 * * * * /opt/pgsql/bin/psql -U postgres -c "select quickstats.gather()" -d
    DBNAME > /dev/null 2>&1

BUGS AND LIMITATIONS 

    The package is designed to work on single databases at a time, if you want to
    report on multiple databases in a cluster, you will need to install this in
    each individual database, and also set cron jobs independently for each
    database.

    This package is only verified to work on Postgres 8.3, although it probably
    would work on earlier versions.

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

