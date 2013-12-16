CREATE OR REPLACE FUNCTION xmin_xmax_status (
    IN   p_xmin        xid,
    IN   p_xmax        xid,
    IN   p_frozenxid   xid,
    IN   p_currentxid  xid,
    OUT  status        INT4
) RETURNS INT4 as $$
DECLARE
    v_xmin        int8  :=  p_xmin::text::int8;
    v_xmax        int8  :=  p_xmax::text::int8;
    v_frozenxid   int8  :=  p_frozenxid::text::int8;
    v_currentxid  int8  :=  p_currentxid::text::int8;
BEGIN
    -- status = 0 (binary: 00) - all ok
    -- status = 1 (binary: 01) - xmin bad
    -- status = 2 (binary: 10) - xmax bad
    -- status = 3 (binary: 11) - xmin and xmax bad
    status := 0;
    IF v_xmin IS NULL AND v_xmax IS NULL THEN
        -- vacuumed, deleted, row ?
        RETURN;
    END IF;
    IF v_xmin in (1,2,v_frozenxid,v_currentxid) THEN
        -- correct values
    ELSIF v_xmin = 0 THEN
        status := status | 1;
    ELSIF v_frozenxid <= v_currentxid THEN
        IF v_xmin between v_frozenxid AND v_currentxid THEN
            -- correct value
        ELSE
            status := status | 1;
        END IF;
    ELSE
        -- xid wrapped between frozenxid AND currentxid
        IF v_xmin between v_currentxid AND v_frozenxid THEN
            status := status | 1;
        ELSE
            -- correct value
        END IF;
    END IF;
    IF v_xmax in (0,1,v_frozenxid,v_currentxid) THEN
        -- correct value
    ELSIF v_xmax = 2 THEN
        status := status | 2;
    ELSIF v_frozenxid <= v_currentxid THEN
        IF v_xmax between v_frozenxid AND v_currentxid THEN
            -- correct value
        ELSE
            status := status | 2;
        END IF;
    ELSE
        -- xid wrapped between frozenxid AND currentxid
        IF v_xmax between v_currentxid AND v_frozenxid THEN
            status := status | 2;
        ELSE
            -- correct value
        END IF;
    END IF;
    RETURN;
END;
$$ language plpgsql;
