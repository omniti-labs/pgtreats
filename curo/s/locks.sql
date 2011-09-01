-- Locks information!menuwait
SELECT
    l.*
FROM
    pg_locks l
    join pg_stat_activity a on l.pid = a.procpid
WHERE
    a.datname = current_database()
;
