/*
 * Copyright (c) 2007, OmniTI Computer Consulting, Inc.
 * Copyright (c) 2007, Message Systems, Inc.
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
#include <sys/time.h>

#include "postgres.h"
#include "funcapi.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "pgstat.h"
#include "storage/lwlock.h"
#include "storage/shmem.h"
#include "storage/ipc.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

#define HASH_BUCKETS 128
#define MAX_SLOTS    1024

#ifndef MIN
#define MIN(x, y)               ((x) < (y) ? (x) : (y))
#endif
#ifndef MAX
#define MAX(x, y)               ((x) > (y) ? (x) : (y))
#endif

void _PG_init(void);
Datum process_register(PG_FUNCTION_ARGS);
Datum process_deregister(PG_FUNCTION_ARGS);
Datum process_status(PG_FUNCTION_ARGS);
Datum process_scoreboard(PG_FUNCTION_ARGS);
static void setup_pg_scoreboard();

static int registered_onexit = 0;

struct psr_ll {
  short recordid;
  short next_nodesetid;
};

#define PG_SCOREBOARD_RECORD_LEN 512
#define PG_SCOREBOARD_MAX_CLIENT_ADDR_LEN 15
#define PG_SCOREBOARD_MAX_DESCRIPTION 63
#define PG_SCOREBOARD_MAX_STATUS_MESSAGE_LEN \
        (PG_SCOREBOARD_RECORD_LEN - \
	 sizeof(struct timeval) - sizeof(struct timeval) - \
         sizeof(unsigned int) - (PG_SCOREBOARD_MAX_CLIENT_ADDR_LEN + 1) - \
	 (PG_SCOREBOARD_MAX_DESCRIPTION + 1) - sizeof(unsigned short) - 1)

typedef struct {
  unsigned int   procpid;
} pg_scoreboard_record_key;

typedef struct {
  struct timeval create_time;
  struct timeval last_update;
  pg_scoreboard_record_key key;
  char           client_addr[PG_SCOREBOARD_MAX_CLIENT_ADDR_LEN + 1];
  unsigned short client_port;
  char           client_description[PG_SCOREBOARD_MAX_DESCRIPTION + 1];
  char           status_message[PG_SCOREBOARD_MAX_STATUS_MESSAGE_LEN + 1];
} pg_scoreboard_record;

typedef struct {
  struct timeval last_update;
  short next_recordid;
} pg_scoreboard_free_record;

/* How this works:
 * We have a hash table with buckets that are chains of nodes (psr_ll).
 * This hash is called nodehash.
 * We're working in shared memory and we're tight on space, so everything
 * is preallocated.  The link list of nodes is nodeset.  The records they
 * reference are in recordset.
 * As we need to "allocate" the nodes, we use the freelist_nodesetid.
 * As we need to "allocate" the records, we use the freelist_recordsetid.
 */

typedef struct {
  LWLockId lockid;
  short freelist_nodesetid;
  short freelist_recordsetid;
  short nodehash[HASH_BUCKETS];
  struct psr_ll nodeset[MAX_SLOTS];
  pg_scoreboard_record recordset[MAX_SLOTS];
} pg_scoreboard;

static pg_scoreboard *scoreboard = NULL;

#define NODEPTR(id) ((id < 0)?NULL:&scoreboard->nodeset[id])
#define RECORDPTR(id) ((id < 0)?NULL:&scoreboard->recordset[id])
#define FREERECORDPTR(id) ((pg_scoreboard_free_record *)((id < 0)?NULL:&scoreboard->recordset[id]))

/* These routines all require the called to have locked the scoreboard */
static short alloc_recordid() {
  short recordid;
  pg_scoreboard_free_record *record;

  recordid = scoreboard->freelist_recordsetid;
  record = FREERECORDPTR(recordid);
  if(record) {
    scoreboard->freelist_recordsetid = record->next_recordid;
  }
  return recordid;
}
static void free_recordid(short recordsetid) {
  pg_scoreboard_free_record *record;
  record = FREERECORDPTR(recordsetid);
  record->next_recordid = scoreboard->freelist_recordsetid;
  scoreboard->freelist_recordsetid = recordsetid;
}
static short alloc_nodeid() {
  struct psr_ll *node;
  short nodesetid;

  nodesetid = scoreboard->freelist_nodesetid;
  node = NODEPTR(nodesetid);
  if(node) {
    scoreboard->freelist_nodesetid = node->next_nodesetid;
  }
  return nodesetid;
}
static void free_nodeid(short nodesetid) {
  struct psr_ll *node;
  node = NODEPTR(nodesetid);
  node->next_nodesetid = scoreboard->freelist_nodesetid;
  scoreboard->freelist_nodesetid = nodesetid;
}

static void delete_record(int pid) {
  pg_scoreboard_record *record;
  short bucket;
  short nodesetid;
  short recordid;
  struct psr_ll *node = NULL, *prev_node = NULL;
  bucket = pid % HASH_BUCKETS;

  for(nodesetid = scoreboard->nodehash[bucket], node = NODEPTR(nodesetid);
      node;
      nodesetid = node->next_nodesetid, node = NODEPTR(nodesetid)) {
    record = RECORDPTR(node->recordid);
    if(record->key.procpid == pid) break;
    prev_node = node;
  }
  if(node) {
    /* Match found */
    if(prev_node)   /* detach it from the list */
      prev_node->next_nodesetid = node->next_nodesetid;
    else            /* or from the front of the list */
      scoreboard->nodehash[bucket] = node->next_nodesetid;
    recordid = node->recordid;
    memset(record, 0, sizeof(*record));
    free_recordid(recordid);
    free_nodeid(nodesetid);
  }
}
static pg_scoreboard_record *find_record(int pid, int create) {
  pg_scoreboard_record *record;
  short bucket;
  short nodesetid;
  short recordid;
  struct psr_ll *node = NULL;
  bucket = pid % HASH_BUCKETS;

  for(node = NODEPTR(scoreboard->nodehash[bucket]);
      node;
      node = NODEPTR(node->next_nodesetid)) {
    record = RECORDPTR(node->recordid);
    if(record->key.procpid == pid) return record;
  }

  if(!create) return NULL;

  recordid = alloc_recordid();
  record = RECORDPTR(recordid);
  if(!record) return NULL;
  memset(record, 0, sizeof(*record));
  record->key.procpid = pid;
  nodesetid = alloc_nodeid();
  node = NODEPTR(nodesetid);
  if(!node) {
    free_recordid(recordid);
    return NULL;
  }
  node->recordid = recordid;
  node->next_nodesetid = scoreboard->nodehash[bucket];
  scoreboard->nodehash[bucket] = nodesetid;
  gettimeofday(&record->create_time, NULL);
  memcpy(&record->last_update, &record->create_time, sizeof(struct timeval));
  return record;
}

static void exit_cb(int code, unsigned long unused) {
  LWLockAcquire(scoreboard->lockid, LW_EXCLUSIVE); 

  delete_record(MyProcPid);
 
  LWLockRelease(scoreboard->lockid);
}

void _PG_init() {
  RequestAddinShmemSpace(sizeof(*scoreboard));
  RequestAddinLWLocks(1);
}

static void setup_pg_scoreboard() {
  if (!scoreboard) {
    int     i;
    bool    found;

    LWLockAcquire(AddinShmemInitLock, LW_EXCLUSIVE);
    scoreboard = ShmemInitStruct("pg_scoreboard", sizeof(*scoreboard), &found);

    if (!scoreboard)
      elog(ERROR, "out of shared memory");
    if (!found) {
      pg_scoreboard_free_record *freeset;

      scoreboard->lockid = LWLockAssign();

      for(i=0; i<HASH_BUCKETS; i++)    /* "null" out the hash bucket */
        scoreboard->nodehash[i] = -1;

      /* point at node 0
       * then point each node
       * at the next one and
       * the last one to nowhere
       */
      scoreboard->freelist_nodesetid = 0;
      for(i=0; i<MAX_SLOTS-1; i++)
        scoreboard->nodeset[i].next_nodesetid = i+1;
      scoreboard->nodeset[MAX_SLOTS-1].next_nodesetid = -1;

      /* point at record 0
       * then point each record
       * at the next one and
       * the last one to nowhere
       */
      scoreboard->freelist_recordsetid = 0;
      memset(scoreboard->recordset, 0,
             sizeof(*scoreboard->recordset) * MAX_SLOTS);
      for(i=0; i<MAX_SLOTS-1; i++) {
        freeset = (pg_scoreboard_free_record *)&scoreboard->recordset[i];
        freeset->next_recordid = i+1;
      }
      ((pg_scoreboard_free_record *)&scoreboard->recordset[MAX_SLOTS-1])->next_recordid = -1;
    }
    LWLockRelease(AddinShmemInitLock);
  }
}

PG_FUNCTION_INFO_V1(process_deregister);
Datum
process_deregister(PG_FUNCTION_ARGS) {
  setup_pg_scoreboard();
 
  LWLockAcquire(scoreboard->lockid, LW_EXCLUSIVE); 

  delete_record(MyProcPid);
 
  LWLockRelease(scoreboard->lockid);

  PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(process_register);
Datum
process_register(PG_FUNCTION_ARGS) {
  pg_scoreboard_record    *record;
  text *client_addr = NULL;
  int   client_addr_len;
  int32 client_port = 0;
  text *client_description = NULL;
  int   client_description_len;
 
  setup_pg_scoreboard();

  if(!registered_onexit) {
    on_shmem_exit(exit_cb, 0);
    registered_onexit = 1;
  }
 
  LWLockAcquire(scoreboard->lockid, LW_EXCLUSIVE);

  if(!PG_ARGISNULL(0)) client_addr = PG_GETARG_VARCHAR_P(0);
  if(!PG_ARGISNULL(1)) client_port = PG_GETARG_INT32(1);
  if(!PG_ARGISNULL(2)) client_description = PG_GETARG_VARCHAR_P(2);

  record = find_record(MyProcPid, 1);

  if(!record) {
    LWLockRelease(scoreboard->lockid);
    elog(WARNING, "Cannot allocate scoreboard record");
    PG_RETURN_VOID();
  }
  record->client_port = client_port;

  /* Fill out the client_addr */
  client_addr_len = client_addr?
    MIN(VARSIZE(client_addr) - VARHDRSZ, PG_SCOREBOARD_MAX_CLIENT_ADDR_LEN):
    0;
  if(client_addr_len) {
    memcpy(record->client_addr, VARDATA(client_addr), client_addr_len);
    record->client_addr[client_addr_len] = '\0';
  }
  else
    strcpy(record->client_addr, "local");

  /* Fill out the client_addr */
  client_description_len = client_description?
    MIN(VARSIZE(client_description) - VARHDRSZ, PG_SCOREBOARD_MAX_DESCRIPTION):
    0;
  if(client_description_len) {
    memcpy(record->client_description, VARDATA(client_description), client_description_len);
    record->client_description[client_description_len] = '\0';
  }
  else
    strcpy(record->client_description, "local");

  LWLockRelease(scoreboard->lockid);

  PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(process_status);
Datum
process_status(PG_FUNCTION_ARGS)
{
  pg_scoreboard_record    *record;
  pg_scoreboard_record_key key;
  text *status_message = NULL;
  int   status_message_len;
  key.procpid = MyProcPid;

  if(PG_ARGISNULL(0)) PG_RETURN_VOID();

  status_message = PG_GETARG_VARCHAR_P(0);
  setup_pg_scoreboard();

  if(!registered_onexit) {
    on_shmem_exit(exit_cb, 0);
    registered_onexit = 1;
  }

  LWLockAcquire(scoreboard->lockid, LW_EXCLUSIVE); 

  record = find_record(key.procpid, 0);

  if(record) {
    gettimeofday(&record->last_update, NULL);
    status_message_len = status_message?
      MIN(VARSIZE(status_message) - VARHDRSZ, PG_SCOREBOARD_MAX_STATUS_MESSAGE_LEN):
      0;
    if(status_message_len) {
      memcpy(record->status_message, VARDATA(status_message), status_message_len);
      record->status_message[status_message_len] = '\0';
    }
    else
      strcpy(record->status_message, "???");
  }

  LWLockRelease(scoreboard->lockid);

  PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(process_scoreboard);
Datum
process_scoreboard(PG_FUNCTION_ARGS) {
  FuncCallContext  *funcctx;
  MemoryContext     oldcontext;
  pg_scoreboard_record *records;

  if(SRF_IS_FIRSTCALL()) {
    int i, j;
    AttInMetadata        *attinmeta;
    pg_scoreboard_record *record;
    TupleDesc             tupdesc;

    funcctx = SRF_FIRSTCALL_INIT();
    oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

    /* Local copy of data so we don't hold a lock for a long time */
    funcctx->max_calls = 0;
    setup_pg_scoreboard();

    LWLockAcquire(scoreboard->lockid, LW_EXCLUSIVE); 

    for(i=0;i<MAX_SLOTS;i++) {
      record = RECORDPTR(i);
      if(record->create_time.tv_sec != 0) funcctx->max_calls++;
    }
    records = palloc(MAX(1,funcctx->max_calls) * sizeof(*record));
    funcctx->user_fctx = (void *)records;
    for(i=0,j=0;i<MAX_SLOTS;i++) {
      record = RECORDPTR(i);
      if(record->create_time.tv_sec != 0)
        memcpy(&records[j++], record, sizeof(*record));
    }

    LWLockRelease(scoreboard->lockid);

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
  records = (pg_scoreboard_record *)funcctx->user_fctx;

  if(funcctx->call_cntr < funcctx->max_calls) {
    char      **values;
    HeapTuple   tuple;
    Datum       result;
    char        datetime_scratch[32];
    struct tm   tm, *tmr;
    time_t      sec;
    int         i;

    /* procpid, client_addr, client_port,
     * create_time, last_update,
     * description, status
     */

    values = (char **) palloc(7 * sizeof(char *));
    values[0] = (char *) palloc(8);
    values[1] = (char *) palloc(PG_SCOREBOARD_MAX_CLIENT_ADDR_LEN + 1);
    values[2] = (char *) palloc(8);
    values[3] = (char *) palloc(64);
    values[4] = (char *) palloc(64);
    values[5] = (char *) palloc(PG_SCOREBOARD_MAX_DESCRIPTION + 1);
    values[6] = (char *) palloc(PG_SCOREBOARD_MAX_STATUS_MESSAGE_LEN + 1);

    snprintf(values[0], 8, "%d", records[funcctx->call_cntr].key.procpid);
    snprintf(values[1], PG_SCOREBOARD_MAX_CLIENT_ADDR_LEN + 1,
             "%s", records[funcctx->call_cntr].client_addr);
    snprintf(values[2], 8, "%d", records[funcctx->call_cntr].client_port);

    sec = records[funcctx->call_cntr].create_time.tv_sec;
    tmr = localtime_r(&sec, &tm);
    strftime(datetime_scratch, 32, "%Y-%m-%d %H:%M:%S", tmr);
    snprintf(values[3], 64, "%s.%d", datetime_scratch,
             (int)(records[funcctx->call_cntr].create_time.tv_usec/1000));

    sec = records[funcctx->call_cntr].last_update.tv_sec;
    tmr = localtime_r(&sec, &tm);
    strftime(datetime_scratch, 32, "%Y-%m-%d %H:%M:%S", tmr);
    snprintf(values[4], 64, "%s.%d", datetime_scratch,
             (int)(records[funcctx->call_cntr].last_update.tv_usec/1000));

    strcpy(values[5], records[funcctx->call_cntr].client_description);
    strcpy(values[6], records[funcctx->call_cntr].status_message);

    tuple = BuildTupleFromCStrings(funcctx->attinmeta, values);
    result = HeapTupleGetDatum(tuple);

    for(i=0;i<7;i++) pfree(values[i]);
    pfree(values);

    SRF_RETURN_NEXT(funcctx, result);
  }
  else {
    SRF_RETURN_DONE(funcctx);
  }
}
