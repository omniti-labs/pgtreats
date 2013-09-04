\echo '-- Test of indexes to be removed'

CREATE temp TABLE ignore_indexes ( id regclass );

\echo '-- Unused indexes'

with base_info as (
    SELECT
        i.indrelid::regclass::text as table_name,
        pg_relation_size( i.indexrelid ) as index_size,
        pg_get_indexdef( i.indexrelid ) as index_def,
        i.indexrelid::regclass::text as index_name,
        i.indexrelid as index_oid
    FROM
        pg_stat_user_indexes s
        JOIN pg_index i USING (indexrelid)
    WHERE
        s.idx_scan = 0
        AND i.indisunique IS false
), arrayed as (
SELECT
    table_name,
    sum(index_size)::INT8 as total_size,
    count(*) as index_count,
    array_agg(
        format(
            E'-- %s; -- %s\nDROP INDEX %s;',
            index_def,
            pg_size_pretty( index_size ),
            index_name
        )
    ) as sql_array
FROM
    base_info
GROUP BY table_name
), inserts as (
    INSERT INTO ignore_indexes SELECT index_oid FROM base_info
)
SELECT
    format(
        E'-- Table: %s, indexes to drop: %s; total disk space to reclaim: %s\n%s\n',
        table_name,
        index_count,
        pg_size_pretty( total_size ),
        array_to_string( sql_array, E'\n' )
    )
FROM
    arrayed
ORDER BY total_size desc
;

\echo '-- Indexes that have super-set indexes'
with review_indexes as (
    SELECT
        indrelid::regclass,
        indexrelid::regclass,
        array_to_string(indkey,' ') as cols
    FROM
        pg_index
    WHERE
        indpred IS NULL
        AND indexrelid NOT in (SELECT id FROM ignore_indexes)
), bad_indexes as (
    SELECT
        a.indexrelid as index_a,
        array_agg( pg_get_indexdef( b.indexrelid ) ) as index_b
    FROM
        review_indexes a
        join review_indexes b on a.indrelid=b.indrelid
    WHERE
        b.cols LIKE a.cols||' %'
    GROUP BY a.indexrelid
), store_ids as (
    INSERT INTO ignore_indexes SELECT index_a FROM bad_indexes
)
SELECT
    format(
        E'-- Index %s, size %s\n-- %s\n-- Obsolete because of:\n--   - %s\nDROP INDEX %s;\n',
        x.index_a,
        pg_size_pretty( pg_relation_size(x.index_a) ),
        pg_get_indexdef( x.index_a ),
        array_to_string( x.index_b, E'\n--   - ' ),
        x.index_a
    )
FROM
    bad_indexes as x
ORDER BY
    pg_relation_size( x.index_a) desc;
