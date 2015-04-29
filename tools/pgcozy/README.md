pgicozy
=========

pgcozy is an extension who adds the capability to keep snapshots of the buffer cache and later can prewarm according to these snapshots.
Snapshots are saved in jsonb format under a schema and a table and they can be reviewed , backed up or transferred
Also see my blog for some examples and tips: 

INSTALLATION
------------

Requirements: pg_preworm and pg_buffercache extensions

In directory where you downloaded pgcozy to run

    make
    make install

Log into PostgreSQL and run the following commands. 

    CREATE EXTENSION pgcozy;
	select pgcozy_init();

This will create a schema called pgcozy , a table called snapshots and a type called cozy_type.
This extension uses pg_prewarm and pg_buffercache to read the contents of shared buffers and store them for later prewarm.

UPGRADE
-------

Make sure all the upgrade scripts for the version you have installed up to the most recent version are in the $BASEDIR/share/extension folder. 

    ALTER EXTENSION pgcozy UPDATE TO '<latest version>';

For detailed change logs of each version, please see the top of each update script.

AUTHOR
------

Vasilis Ventirozos
OmniTI, Inc - http://www.omniti.com
vventirozos@omniti.com


LICENSE AND COPYRIGHT
---------------------

pgcozy is released under the PostgreSQL License, a liberal Open Source license, similar to the BSD or MIT licenses.

Copyright (c) 2015 OmniTI, Inc.

Permission to use, copy, modify, and distribute this software and its documentation for any purpose, without fee, and without a written agreement is hereby granted, provided that the above copyright notice and this paragraph and the following two paragraphs appear in all copies.

IN NO EVENT SHALL THE AUTHOR BE LIABLE TO ANY PARTY FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES, INCLUDING LOST PROFITS, ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

THE AUTHOR SPECIFICALLY DISCLAIMS ANY WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND THE AUTHOR HAS NO OBLIGATIONS TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
 
