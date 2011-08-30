SELECT
    lpad(
        to_char(
            extract(
                epoch FROM clock_timestamp()-xact_start
            ),
            'FM999999990.000"s"'
        ),
        10
    ) as xact_t,
    lpad(
        to_char(
            extract(
                epoch FROM clock_timestamp()-query_start
            ),
            'FM999999990.000"s"'
        ),
        10
    ) as query_t,
    case when waiting then 'LOCK'::text else '    '::text end as lock,
    coalesce( client_addr::TEXT, '[local]') || ':' || client_port as client,
    array_to_string(
        ARRAY( SELECT (regexp_matches( current_query, '(.{1,80})', 'g'))[1] ),
        E' --\n'
    ) as query
FROM
    pg_stat_activity
WHERE
    current_query <> '<IDLE>'
    AND procpid <> pg_backend_pid()
ORDER BY
    xact_start
;
