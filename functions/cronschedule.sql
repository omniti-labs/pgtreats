create or replace function cronschedule 
    (
    in p_starttime timestamp without time zone, 
    in p_stoptime timestamp without time zone, 
    in p_min text, in p_hour text, in p_dom text, 
    in p_month text, in p_dow text
    )
RETURNS SETOF TIMESTAMPTZ
RETURNS NULL ON NULL INPUT 
AS $$
DECLARE
v_sql text;
v_record record;

v_startint integer;
v_endint integer;
v_return_me boolean;

v_min_arr text[];
v_hour_arr text[];
v_dom_arr text[];
v_month_arr text[];
v_dow_arr text[];

v_i integer;
v_rec record; 
v_nums record;
v_pos integer; 
v_mod text;
 
v_min_all integer[];
v_hour_all integer[];
v_dom_all integer[];
v_month_all integer[];
v_dow_all integer[];

BEGIN

select extract(epoch from p_starttime)::integer, extract(epoch from p_stoptime)::integer into v_startint, v_endint;
raise notice 'intvals: % & %',v_startint, v_endint;

IF p_min IS NOT NULL THEN
    select string_to_array(p_min,',') into v_min_arr;
    v_i := 0;
    FOR v_rec IN select v_min_arr[x] as v from generate_series(1,array_upper(v_min_arr,1)) as x LOOP
        -- RAISE NOTICE 'processing entry %',v_rec.v; 
        IF v_rec.v = '*' THEN
            FOR v_nums IN select * from generate_series(0,59) LOOP
                v_min_all[v_i] := v_nums.generate_series;
                v_i := v_i+1; 
            END LOOP; 
        ELSIF v_rec.v ~ '\\*' THEN
            select strpos(v_rec.v,'/') into v_pos;
            select substr(v_rec.v,v_pos+1) into v_mod;
            -- RAISE NOTICE 'pos & mod %,%',v_pos, v_mod; 
            FOR v_nums IN select * from generate_series(0,59) LOOP
                IF (v_nums.generate_series % v_mod::int = 0) THEN
                    v_min_all[v_i] := v_nums.generate_series;
                    v_i := v_i+1; 
                END IF;
            END LOOP; 
        ELSE
           v_min_all[v_i] := v_rec.v; 
           v_i := v_i+1; 
        END IF; 
    END LOOP;
END IF;


IF p_hour IS NOT NULL THEN
select string_to_array(p_hour,',') into v_hour_arr;
    v_i := 0;
    FOR v_rec IN select v_hour_arr[x] as v from generate_series(1,array_upper(v_hour_arr,1)) as x LOOP
        -- RAISE NOTICE 'processing entry %',v_rec.v;
        IF v_rec.v = '*' THEN
            FOR v_nums IN select * from generate_series(0,23) LOOP
                v_hour_all[v_i] := v_nums.generate_series;
                v_i := v_i+1;
            END LOOP;
        ELSIF v_rec.v ~ '\\*' THEN
            select strpos(v_rec.v,'/') into v_pos;
            select substr(v_rec.v,v_pos+1) into v_mod;
            -- RAISE NOTICE 'pos & mod %,%',v_pos, v_mod;
            FOR v_nums IN select * from generate_series(0,23) LOOP
                IF (v_nums.generate_series % v_mod::int = 0) THEN
                    v_hour_all[v_i] := v_nums.generate_series;
                    v_i := v_i+1;
                END IF;
            END LOOP;
        ELSE
           v_hour_all[v_i] := v_rec.v;
           v_i := v_i+1;
        END IF;
    END LOOP;
END IF;

IF p_dom IS NOT NULL THEN
    select string_to_array(p_dom,',') into v_dom_arr;
    v_i := 0;
    FOR v_rec IN select v_dom_arr[x] as v from generate_series(1,array_upper(v_dom_arr,1)) as x LOOP
        -- RAISE NOTICE 'processing entry %',v_rec.v;
        IF v_rec.v = '*' THEN
            FOR v_nums IN select * from generate_series(1,31) LOOP
                v_dom_all[v_i] := v_nums.generate_series;
                v_i := v_i+1;
            END LOOP;
        ELSIF v_rec.v ~ '\\*' THEN
            select strpos(v_rec.v,'/') into v_pos;
            select substr(v_rec.v,v_pos+1) into v_mod;
            -- RAISE NOTICE 'pos & mod %,%',v_pos, v_mod;
            FOR v_nums IN select * from generate_series(1,31) LOOP
                IF (v_nums.generate_series % v_mod::int = 0) THEN
                    v_dom_all[v_i] := v_nums.generate_series;
                    v_i := v_i+1;
                END IF;
            END LOOP;
        ELSE
           v_dom_all[v_i] := v_rec.v;
           v_i := v_i+1;
        END IF;
    END LOOP;
END IF;

IF p_month IS NOT NULL THEN
    select string_to_array(p_month,',') into v_month_arr;
    v_i := 0;
    FOR v_rec IN select v_month_arr[x] as v from generate_series(1,array_upper(v_month_arr,1)) as x LOOP
        -- RAISE NOTICE 'processing entry %',v_rec.v;
        IF v_rec.v = '*' THEN
            FOR v_nums IN select * from generate_series(1,12) LOOP
                v_month_all[v_i] := v_nums.generate_series;
                v_i := v_i+1;
            END LOOP;
        ELSIF v_rec.v ~ '\\*' THEN
            select strpos(v_rec.v,'/') into v_pos;
            select substr(v_rec.v,v_pos+1) into v_mod;
            -- RAISE NOTICE 'pos & mod %,%',v_pos, v_mod;
            FOR v_nums IN select * from generate_series(1,12) LOOP
                IF (v_nums.generate_series % v_mod::int = 0) THEN
                    v_month_all[v_i] := v_nums.generate_series;
                    v_i := v_i+1;
                END IF;
            END LOOP;
        ELSE
           v_month_all[v_i] := v_rec.v;
           v_i := v_i+1;
        END IF;
    END LOOP;
END IF;

IF p_dow IS NOT NULL THEN
    select string_to_array(p_dow,',') into v_dow_arr;
    v_i := 0;
    FOR v_rec IN select v_dow_arr[x] as v from generate_series(1,array_upper(v_dow_arr,1)) as x LOOP
        -- RAISE NOTICE 'processing entry %',v_rec.v;
        IF v_rec.v = '*' THEN
            FOR v_nums IN select * from generate_series(0,6) LOOP
                v_dow_all[v_i] := v_nums.generate_series;
                v_i := v_i+1;
            END LOOP;
        ELSIF v_rec.v ~ '\\*' THEN
            select strpos(v_rec.v,'/') into v_pos;
            select substr(v_rec.v,v_pos+1) into v_mod;
            -- RAISE NOTICE 'pos & mod %,%',v_pos, v_mod;
            FOR v_nums IN select * from generate_series(0,6) LOOP
                IF (v_nums.generate_series % v_mod::int = 0) THEN
                    v_dow_all[v_i] := v_nums.generate_series;
                    v_i := v_i+1;
                END IF;
            END LOOP;
        ELSE
           -- in vixie, you can use 0 or 7 for sunday, in pg it must be 0
           IF v_rec.v = 7 THEN 
                v_rec.v := 0; 
           END IF;
           v_dow_all[v_i] := v_rec.v;
           v_i := v_i+1;
        END IF;
    END LOOP;
END IF;


FOR v_record IN
    select (p_starttime + '1 minute'::interval * x) as ptime from generate_series(0,(v_endint-v_startint)/60) x
LOOP
    IF extract(minute from v_record.ptime) <> ALL (v_min_all) THEN
        continue;
    END IF;

    IF extract(hour from v_record.ptime) <> ALL (v_hour_all) THEN
        continue;
    END IF;
    
    IF extract(day from v_record.ptime) <> ALL (v_dom_all) THEN
        continue;
    END IF;

    IF extract(month from v_record.ptime) <> ALL (v_month_all) THEN
        continue;
    END IF;

    IF extract(dow from v_record.ptime) <> ALL (v_dow_all) THEN
        continue;
    END IF;

    RETURN NEXT v_record.ptime;

END LOOP;

RETURN;

END
$$ LANGUAGE plpgsql; 

