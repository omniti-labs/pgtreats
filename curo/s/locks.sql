-- Locks information
SELECT
    l.*
FROM
    pg_locks l
    join pg_database d on coalesce(l.database, d.oid) = d.oid
WHERE
    d.datname = current_database()
;
