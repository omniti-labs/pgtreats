CREATE TABLE otools.table_growth (
    table_owner text NOT NULL,
    schema_name text NOT NULL,
    table_name text NOT NULL,
    actual_size numeric NOT NULL,
    growth_size numeric NOT NULL,
    sum_flag smallint NOT NULL,
    capture_time date NOT NULL
);

