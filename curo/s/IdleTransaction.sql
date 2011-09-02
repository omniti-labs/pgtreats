-- Idle in Transaction!menuwait
SELECT now()-query_start as query_running_for,ps.*, 
             pl.relation::regclass, pl.mode, pl.granted  
     FROM pg_stat_activity ps
               LEFT JOIN pg_locks pl ON pl.pid=ps.procpid
       WHERE ps.current_query = '<IDLE> in transaction' 
        ORDER  BY ps.query_start LIMIT 1;
