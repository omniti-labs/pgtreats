/*
 * Copyright (c) 2010, OmniTI Computer Consulting, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 *       copyright notice, this list of conditions and the following
 *       disclaimer in the documentation and/or other materials provided
 *       with the distribution.
 *     * Neither the name OmniTI Computer Consulting, Inc. nor the names
 *       of its contributors may be used to endorse or promote products
 *       derived from this software without specific prior written
 *       permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Author: Theo Schlossnagle
 *
 */

#include <time.h>
#include <unistd.h>
#include <sys/time.h>

#include "postgres.h"
#include "funcapi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "catalog/pg_control.h"
#include "access/xlog_internal.h"
#include "storage/lwlock.h"
#include "storage/shmem.h"
#include "storage/ipc.h"

#if PG_CONTROL_VERSION >= 840 && PG_CONTROL_VERSION < 900
#define CONTROL_NUM_ROWS 25
#endif

#define uint64_item(elem) do { \
  values[0] = (char *) pstrdup(#elem); \
  values[1] = (char *) palloc(32); \
  snprintf(values[1], 32, "%llu", (unsigned long long)cfd->elem); \
} while(0)
#define uint32_item(elem) do { \
  values[0] = (char *) pstrdup(#elem); \
  values[1] = (char *) palloc(20); \
  snprintf(values[1], 20, "%u", (unsigned int)cfd->elem); \
} while(0)
#define bool_item(elem) do { \
  values[0] = (char *) pstrdup(#elem); \
  values[1] = (char *) pstrdup( cfd->elem ? "t" : "f" ); \
} while(0)
#define dbstate_item(elem) do { \
  values[0] = (char *) pstrdup(#elem); \
  switch(cfd->elem) { \
    case DB_STARTUP: values[1] = (char *) pstrdup("startup"); break; \
    case DB_SHUTDOWNED: values[1] = (char *) pstrdup("shutdown"); break; \
    case DB_SHUTDOWNING: values[1] = (char *) pstrdup("shutting down"); break; \
    case DB_IN_CRASH_RECOVERY: values[1] = (char *) pstrdup("crash recovery"); break; \
    case DB_IN_ARCHIVE_RECOVERY: values[1] = (char *) pstrdup("archive recovery"); break; \
    case DB_IN_PRODUCTION: values[1] = (char *) pstrdup("production"); break; \
    default: values[1] = (char *) pstrdup("unknown"); \
  } \
} while(0)
#define XLogRecPtr_item(elem) do { \
  values[0] = (char *) pstrdup(#elem); \
  values[1] = (char *) palloc(8+8+2); \
  snprintf(values[1], 8+8+2, "%X/%08X", cfd->elem.xlogid, cfd->elem.xrecoff); \
} while(0)
#define time_item(elem) do { \
  struct tm tm, *tmr; \
  time_t t = cfd->elem; \
  values[0] = (char *) pstrdup(#elem); \
  tmr = gmtime_r(&t, &tm); \
  if(tmr) { \
    values[1] = (char *) palloc(32); \
    strftime(values[1], 32, "%Y-%m-%d %H:%M:%S-00", tmr); \
  } \
  else values[1] = NULL; \
} while(0)

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

Datum pg_control_variables(PG_FUNCTION_ARGS);

PG_FUNCTION_INFO_V1(pg_control_variables);
Datum
pg_control_variables(PG_FUNCTION_ARGS) {
  FuncCallContext  *funcctx;
  MemoryContext     oldcontext;
  ControlFileData  *cfd;

  if(SRF_IS_FIRSTCALL()) {
    int fd;
    AttInMetadata        *attinmeta;
    TupleDesc             tupdesc;

    funcctx = SRF_FIRSTCALL_INIT();
    oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

    /* Local copy of data so we don't hold a lock for a long time */
    funcctx->max_calls = 0;

    funcctx->user_fctx = palloc(PG_CONTROL_SIZE);
    fd = open(XLOG_CONTROL_FILE, O_RDONLY);
    if(fd < 0) {
      elog(ERROR, "cannot open control file");
    }
    if(read(fd, funcctx->user_fctx, PG_CONTROL_SIZE) != PG_CONTROL_SIZE) {
      close(fd);
      elog(ERROR, "short read on control file");
    }
    close(fd);

    cfd = funcctx->user_fctx;
    funcctx->max_calls = 0;
    if(cfd->pg_control_version != PG_CONTROL_VERSION)
      elog(ERROR, "control file version %d, expected %d",
           cfd->pg_control_version, PG_CONTROL_VERSION);

    funcctx->max_calls = CONTROL_NUM_ROWS;
    if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
        ereport(ERROR,
                (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                 errmsg("function returning record called in context "
                        "that cannot accept type record")));

    /*
     * generate attribute metadata needed later to produce tuples from raw
     * C strings
     */
    attinmeta = TupleDescGetAttInMetadata(tupdesc);
    funcctx->attinmeta = attinmeta;

    MemoryContextSwitchTo(oldcontext);
  }

  funcctx = SRF_PERCALL_SETUP();
  cfd = (ControlFileData *)funcctx->user_fctx;

  if(funcctx->call_cntr < funcctx->max_calls) {
    char      **values;
    HeapTuple   tuple;
    Datum       result;
    int         i;

    /* procpid, client_addr, client_port,
     * create_time, last_update,
     * description, status
     */

    values = (char **) palloc(2 * sizeof(char *));
    switch(funcctx->call_cntr) {
      case 0: uint64_item(system_identifier); break;
      case 1: uint32_item(pg_control_version); break;
      case 2: uint32_item(catalog_version_no); break;
      case 3: dbstate_item(state); break;
      case 4: time_item(time); break;
      case 5: uint32_item(blcksz); break;
      case 6: uint32_item(relseg_size); break;
      case 7: uint32_item(xlog_blcksz); break;
      case 8: uint32_item(xlog_seg_size); break;
      case 9: uint32_item(nameDataLen); break;
      case 10: uint32_item(indexMaxKeys); break;
      case 11: uint32_item(toast_max_chunk_size); break;
      case 12: bool_item(enableIntTimes); break;
      case 13: uint32_item(maxAlign); break;
      case 14: XLogRecPtr_item(checkPoint); break;
      case 15: XLogRecPtr_item(prevCheckPoint); break;
      case 16: XLogRecPtr_item(minRecoveryPoint); break;
      case 17: XLogRecPtr_item(checkPointCopy.redo); break;
      case 18: uint32_item(checkPointCopy.ThisTimeLineID); break;
      case 19: uint32_item(checkPointCopy.nextXidEpoch); break;
      case 20: uint32_item(checkPointCopy.nextXid); break;
      case 21: uint32_item(checkPointCopy.nextOid); break;
      case 22: uint32_item(checkPointCopy.nextMulti); break;
      case 23: uint32_item(checkPointCopy.nextMultiOffset); break;
      case 24: time_item(checkPointCopy.time); break;
      default:
        elog(ERROR, "internal control error");
    }

    tuple = BuildTupleFromCStrings(funcctx->attinmeta, values);
    result = HeapTupleGetDatum(tuple);

    for(i=0;i<2;i++) pfree(values[i]);
    pfree(values);

    SRF_RETURN_NEXT(funcctx, result);
  }
  else {
    SRF_RETURN_DONE(funcctx);
  }
}
