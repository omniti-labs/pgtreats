START TRANSACTION;

CREATE SCHEMA alt;

create table alt.job_log (
    job_id  bigserial primary key,
    owner   text not null,
    job_name    text not null,
    start_time  timestamp not null,
    end_time timestamp,
    status text,
    pid integer not null 
);

create index job_log_job_name_idx on alt.job_log(job_name);
create index job_log_start_time_idx on alt.job_log(start_time);

create table alt.job_details (
    job_id bigint not null references alt.job_log(job_id),
    step_id bigserial not null,
    action text not null,
    start_time  timestamp not null,
    end_time timestamp,
    elapsed_time integer,
    status text,
    message text,
    PRIMARY KEY (job_id, step_id) 
);

-- procedures

CREATE OR REPLACE FUNCTION alt._autonomous_add_job (in p_owner text, in p_job_name text, p_pid integer)
RETURNS integer
AS $$
DECLARE
    v_job_id INTEGER;
BEGIN
    SELECT nextval('alt.job_log_job_id_seq') INTO v_job_id;

    INSERT INTO alt.job_log (job_id, owner, job_name, start_time, pid)
    VALUES (v_job_id, p_owner, p_job_name, current_timestamp, p_pid); 

    RETURN v_job_id; 
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION alt.add_job (in p_job_name text)
RETURNS integer
AS $$
DECLARE 
    v_job_id INTEGER;
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT alt._autonomous_add_job (' ||
        quote_literal(current_user) || ',' ||
        quote_literal(p_job_name) || ',' ||
        pg_backend_pid() || ')';

    EXECUTE 'SELECT job_id FROM dblink.dblink(''dbname='|| current_database() ||
        ''','|| quote_literal(v_remote_query) || ',TRUE) t (job_id int)' INTO v_job_id;      

    IF v_job_id IS NULL THEN
        RAISE EXCEPTION 'Job creation failed';
    END IF;

    RETURN v_job_id;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION alt._autonomous_add_step (in p_job_id integer, in p_action text)
RETURNS integer
AS $$
DECLARE
    v_step_id INTEGER;
BEGIN
    SELECT nextval('alt.job_details_step_id_seq') INTO v_step_id;

    INSERT INTO alt.job_details (job_id, step_id, action, start_time)
    VALUES (p_job_id, v_step_id, p_action, current_timestamp);

    RETURN v_step_id;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION alt.add_step (in p_job_id integer, in p_action text)
RETURNS integer
AS $$
DECLARE 
    v_step_id INTEGER;
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT alt._autonomous_add_step (' ||
        p_job_id || ',' ||
        quote_literal(p_action) || ')';

    EXECUTE 'SELECT step_id FROM dblink.dblink(''dbname='|| current_database() ||
        ''','|| quote_literal(v_remote_query) || ',TRUE) t (step_id int)' INTO v_step_id;      

    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'Job creation failed';
    END IF;

    RETURN v_step_id;
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION alt._autonomous_upd_step (in p_job_id integer, in p_step_id integer, in p_status text, in p_message text)
RETURNS integer 
AS $$
DECLARE
    v_numrows integer;
BEGIN
    UPDATE alt.job_details SET 
        end_time = current_timestamp,
        elapsed_time = date_part('epoch',now() - start_time)::integer,
        status = p_status,
        message = p_message
    WHERE job_id = p_job_id AND step_id = p_step_id; 
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION alt.upd_step (in p_job_id integer, in p_step_id integer, in p_status text, in p_message text)
RETURNS void
AS $$
DECLARE
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT alt._autonomous_upd_step ('||
    p_job_id || ',' ||
    p_step_id || ',' ||
    quote_literal(p_status) || ',' ||
    quote_literal(p_message) || ')';

    EXECUTE 'SELECT devnull FROM dblink.dblink(''dbname=' || current_database() ||
        ''','|| quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION alt._autonomous_close_job (in p_job_id integer)
RETURNS integer
AS $$
DECLARE
    v_numrows integer;
BEGIN    
    UPDATE alt.job_log SET
        end_time = current_timestamp,
        status = 'OK'
    WHERE job_id = p_job_id;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION alt.close_job (in p_job_id integer)
RETURNS void
AS $$
DECLARE
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT alt._autonomous_close_job('||p_job_id||')'; 

    EXECUTE 'SELECT devnull FROM dblink.dblink(''dbname=' || current_database() ||
        ''',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  
END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION alt._autonomous_fail_job (in p_job_id integer)
RETURNS integer 
AS $$
DECLARE
    v_numrows integer;
BEGIN
    UPDATE alt.job_log SET
        end_time = current_timestamp,
        status = 'BAD'
    WHERE job_id = p_job_id;
    GET DIAGNOSTICS v_numrows = ROW_COUNT;
    RETURN v_numrows;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION alt.fail_job (in p_job_id integer)
RETURNS void
AS $$
DECLARE
    v_remote_query TEXT;
BEGIN
    v_remote_query := 'SELECT alt._autonomous_fail_job('||p_job_id||')'; 

    EXECUTE 'SELECT devnull FROM dblink.dblink(''dbname=' || current_database() ||
        ''',' || quote_literal(v_remote_query) || ',TRUE) t (devnull int)';  

END
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION alt._autonomous_cancel_job (in p_job_id integer)
RETURNS integer 
AS $$
DECLARE
    p_pid INTEGER;
BEGIN
    SELECT pid FROM alt.job_logs WHERE job_id = p_job_id INTO p_pid;
    SELECT pg_cancel_backend(p_pid);
    SELECT alt._autonomous_fail_job(p_job_id);    
END
$$ LANGUAGE plpgsql;

END;

