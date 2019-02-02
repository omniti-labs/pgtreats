pg_dirtyread
============

The pg_dirtyread extension provides the ability to read dead but unvacuumed
rows from a relation.

Building
--------

To build pg_dirtyread, just do this:

    make
    make install

If you encounter an error such as:

    make: pg_config: Command not found

Be sure that you have `pg_config` installed and in your path. If you used a
package management system such as RPM to install PostgreSQL, be sure that the
`-devel` package is also installed. If necessary tell the build process where
to find it:

    env PG_CONFIG=/path/to/pg_config make && make install

Loading and Using
-------

Once pg_dirtyread is built and installed, you can add it to a database. Loading
pg_dirtyread is as simple as connecting to a database as a super user and
running:

  ```sql
    CREATE EXTENSION pg_dirtyread;
    SELECT * FROM pg_dirtyread('tablename'::regclass) AS t(col1 type1, col2 type2, ...);
  ```

The `pg_dirtyread()` function returns RECORD, therefore it is necessary to
attach a table alias clause that describes the table schema. Columns are
matched by name, so it is possible to omit some columns in the alias, or
rearrange columns.

Example:

  ```sql
    CREATE EXTENSION pg_dirtyread;

    -- Create table and disable autovacuum
    CREATE TABLE foo (bar bigint, baz text);
    ALTER TABLE foo SET (
      autovacuum_enabled = false, toast.autovacuum_enabled = false
    );

    INSERT INTO foo VALUES (1, 'Test'), (2, 'New Test');
    DELETE FROM foo WHERE bar = 1;

    SELECT * FROM pg_dirtyread('foo'::regclass) as t(bar bigint, baz text);
  ```

Where the schema of `foo` is `(bar bigint, baz text)`.

System Columns
--------------

System columns such as `xmax` and `ctid` can be retrieved by including them in
the table alias attached to the `pg_dirtyread()` call. A special column `dead` of
type boolean is available to report dead rows (as by `HeapTupleIsSurelyDead`).
The `dead` column is not usable during recovery, i.e. most notably not on
standby servers.

  ```sql
    SELECT * FROM pg_dirtyread('foo'::regclass)
        AS t(tableoid oid, ctid tid, xmin xid, xmax xid, cmin cid, cmax cid, dead boolean,
             oid oid, bar bigint, baz text);
     tableoid │ ctid  │ xmin │ xmax │ cmin │ cmax │ dead │ oid │ bar │        baz
    ──────────┼───────┼──────┼──────┼──────┼──────┼──────┼─────┼─────┼───────────────────
        41823 │ (0,1) │ 1484 │ 1485 │    0 │    0 │ t    │   0 │   1 │ Delete
        41823 │ (0,2) │ 1484 │    0 │    0 │    0 │ f    │   0 │   2 │ Insert
        41823 │ (0,3) │ 1484 │ 1486 │    0 │    0 │ t    │   0 │   3 │ Update
        41823 │ (0,4) │ 1484 │ 1488 │    0 │    0 │ f    │   0 │   4 │ Not deleted
        41823 │ (0,5) │ 1484 │ 1489 │    1 │    1 │ f    │   0 │   5 │ Not updated
        41823 │ (0,6) │ 1486 │    0 │    0 │    0 │ f    │   0 │   3 │ Updated
        41823 │ (0,7) │ 1489 │    0 │    1 │    1 │ t    │   0 │   5 │ Not quite updated
        41823 │ (0,8) │ 1490 │    0 │    2 │    2 │ t    │   0 │   6 │ Not inserted
  ```

License
-------

Original author: Phil Sorber

Copyright (c) 1996-2017, PostgreSQL Global Development Group

Copyright (c) 2012, OmniTI Computer Consulting, Inc.

Portions Copyright (c) 1994, The Regents of the University of California

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above
  copyright notice, this list of conditions and the following
  disclaimer in the documentation and/or other materials provided
  with the distribution.
* Neither the name OmniTI Computer Consulting, Inc. nor the names
  of its contributors may be used to endorse or promote products
  derived from this software without specific prior written
  permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
