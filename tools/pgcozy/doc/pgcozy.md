pgcozy
======

Functions
---------
pgcozy_init ()

initializes the schema and the table and creates a custom type. Runs with no arguments and if run after the initialization, it will re-initialize deleting all contents.

pgcozy_snapshot (popularity int)

Gets a snapshot from pg_buffercache, popularity can be 0-5, 0 will take all contents of pg_buffercache. Popularity refers to Page LRU count. When you get a snapshot using 3 as
popularity pgcozy will take a snapshot of all pages that have usagecount 3-5 etc.
Snapshots are getting stored in a table under pgcozy schema named shanpshots, snapshots are in jsonb form and they look like this :

id            | 3
snapshot_date | 2015-04-29
snapshot      | [{"block_no": 13, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 12, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 11, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 10, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 9, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 8, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 7, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 6, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 5, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 4, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 3, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 2, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 1, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 0, "popularity": 5, "table_name": "public.checkpoints"}, {"block_no": 0, "popularity": 5, "table_name": "public.koko"}]

(check pg_buffercache extension for more information about usagecount)

pgcozy_warm (snapshot_id int)

Prewarms buffercache according to a snapshot id. More information about snapshots can be found by selecting from pgcozy.snapshots.
using 0 as snapshot_id will prewarm based on the latest snapshot.


Usecases
---------
You can schedule pgcozy_snapshot to run from a crontab entry daily, a similar entry will be sufficient:

00 00 * * * psql -c 'select pgcozy_snapshot(0)' monkey

Or it can run manually in cases that normal contents of shared buffers have altered (failover, pgdumps etc).
in case of a failover shared buffers on the newly promoted master will be empty or filled with pages from readonly operations that were performed on the server when it was a slave
to recover shared buffers fast you can use the latest snapshot , or the snapshot you took before the failover to prewarm shared buffers with the correct content.

