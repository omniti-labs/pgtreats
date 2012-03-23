#include "postgres.h"
#include "funcapi.h"
#include "utils/tqual.h"
#include "catalog/pg_type.h"
#include "access/tupconvert.h"

typedef struct
{
    Relation            rel;
    HeapScanDesc        scan;
    TupleDesc           reltupdesc;
    TupleConversionMap  *map;
} pg_dirtyread_ctx;

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(pg_dirtyread);
Datum pg_dirtyread(PG_FUNCTION_ARGS);

Datum
pg_dirtyread(PG_FUNCTION_ARGS)
{
    FuncCallContext     *funcctx;
    MemoryContext       oldcontext;
    pg_dirtyread_ctx    *usr_ctx;
    Oid                 relid;
    HeapTuple           tuplein, tupleout;
    TupleDesc           tupdesc;

    if (SRF_IS_FIRSTCALL())
    {
        relid = PG_GETARG_OID(0);

        if (OidIsValid(relid))
        {
            funcctx = SRF_FIRSTCALL_INIT();
            oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);
            usr_ctx = (pg_dirtyread_ctx *) palloc(sizeof(pg_dirtyread_ctx));
            usr_ctx->rel = heap_open(relid, AccessShareLock);
            usr_ctx->reltupdesc = RelationGetDescr(usr_ctx->rel);
            get_call_result_type(fcinfo, NULL, &tupdesc);
            funcctx->tuple_desc = BlessTupleDesc(tupdesc);
            usr_ctx->map = convert_tuples_by_position(usr_ctx->reltupdesc, funcctx->tuple_desc, "Error converting tuple descriptors!");
            usr_ctx->scan = heap_beginscan(usr_ctx->rel, SnapshotAny, 0, NULL);
            funcctx->user_fctx = (void *) usr_ctx;
            MemoryContextSwitchTo(oldcontext);
        }
    }

    funcctx = SRF_PERCALL_SETUP();
    usr_ctx = (pg_dirtyread_ctx *) funcctx->user_fctx;

    if ((tuplein = heap_getnext(usr_ctx->scan, ForwardScanDirection)) != NULL)
    {
        tupleout = do_convert_tuple(tuplein, usr_ctx->map);
        SRF_RETURN_NEXT(funcctx, HeapTupleGetDatum(tupleout));
    }
    else
    {
        heap_endscan(usr_ctx->scan);
        heap_close(usr_ctx->rel, AccessShareLock);
        SRF_RETURN_DONE(funcctx);
    }
}
