/*
 * CDDL HEADER START
 *
 * The contents of this file are subject to the terms of the
 * Common Development and Distribution License (the "License").
 * You may not use this file except in compliance with the License.
 *
 * You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
 * or http://www.opensolaris.org/os/licensing.
 * See the License for the specific language governing permissions
 * and limitations under the License.
 *
 * When distributing Covered Code, include this CDDL HEADER in each
 * file and include the License file at usr/src/OPENSOLARIS.LICENSE.
 * If applicable, add the following below this CDDL HEADER, with the
 * fields enclosed by brackets "[]" replaced with your own identifying
 * information: Portions Copyright [yyyy] [name of copyright owner]
 *
 * CDDL HEADER END
 */

/*
 * Copyright 2006 Sun Microsystems, Inc.  All rights reserved.
 * Use is subject to license terms.
 */

#pragma ident	"@(#)pmap.c	1.32	06/09/11 SMI"

#include <stdio.h>
#include <stdio_ext.h>
#include <stdlib.h>
#include <unistd.h>
#include <ctype.h>
#include <fcntl.h>
#include <string.h>
#include <dirent.h>
#include <limits.h>
#include <link.h>
#include <libelf.h>
#include <sys/types.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/mkdev.h>
#include <sys/mman.h>
#include <sys/lgrp_user.h>
#include "libproc.h"
#include "libzonecfg.h"

#include "postgres.h"
#include "fmgr.h"
#include "funcapi.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

#define SOL_MAP_DATA_CNT 13
#define	KILOBYTE	1024
#define	MEGABYTE	(KILOBYTE * KILOBYTE)
#define	GIGABYTE	(KILOBYTE * KILOBYTE * KILOBYTE)

/*
 * Round up the value to the nearest kilobyte
 */
#define	ROUNDUP_KB(x)	(((x) + (KILOBYTE - 1)) / KILOBYTE)

/*
 * The alignment should be a power of 2.
 */
#define	P2ALIGN(x, align)		((x) & -(align))

#define	INVALID_ADDRESS			(uintptr_t)(-1)


/*
 * -L option requires per-page information. The information is presented in an
 * array of page_descr structures.
 */
typedef struct page_descr {
	uintptr_t	pd_start;	/* start address of a page */
	size_t		pd_pagesize;	/* page size in bytes */
	lgrp_id_t	pd_lgrp;	/* lgroup of memory backing the page */
	int		pd_valid;	/* valid page description if non-zero */
} page_descr_t;

/*
 * Per-page information for a memory chunk.
 * The meminfo(2) system call accepts up to MAX_MEMINFO_CNT pages at once.
 * When we need to scan larger ranges we divide them in MAX_MEMINFO_CNT sized
 * chunks. The chunk information is stored in the memory_chunk structure.
 */
typedef struct memory_chunk {
	page_descr_t	page_info[MAX_MEMINFO_CNT];
	uintptr_t	end_addr;
	uintptr_t	chunk_start;	/* Starting address */
	uintptr_t	chunk_end;	/* chunk_end is always <= end_addr */
	size_t		page_size;
	int		page_index;	/* Current page */
	int		page_count;	/* Number of pages */
} memory_chunk_t;

typedef int proc_xmap_f(void *, const prxmap_t *, const char *, int, int);

static	int	xmapping_iter(struct ps_prochandle *, proc_xmap_f *, void *,
    int);

static	int	look_xmap_nopgsz(void *, const prxmap_t *, const char *,
    int, int);

static int gather_xmap(void *, const prxmap_t *, const char *, int, int);
static int iter_map(proc_map_f *, void *);
static int iter_xmap(proc_xmap_f *, void *);

static	int	perr(char *);

static int	address_in_range(uintptr_t, uintptr_t, size_t);
static size_t	adjust_addr_range(uintptr_t, uintptr_t, size_t,
    uintptr_t *, uintptr_t *);

/*
 * The -A address range is represented as a pair of addresses
 * <start_addr, end_addr>. Either one of these may be unspecified (set to
 * INVALID_ADDRESS). If both are unspecified, no address range restrictions are
 * in place.
 */
static  uintptr_t start_addr = INVALID_ADDRESS;
static	uintptr_t end_addr = INVALID_ADDRESS;

static	int	addr_width, size_width;
static	char	*command;
static	char	*procname;
static	struct ps_prochandle *Pr;

typedef struct lwpstack {
	lwpid_t	lwps_lwpid;
	stack_t	lwps_stack;
} lwpstack_t;

typedef struct {
	prxmap_t	md_xmap;
	prmap_t		md_map;
	char		*md_objname;
	boolean_t	md_last;
	int		md_doswap;
} mapdata_t;

static	mapdata_t	*maps;
static	int		map_count;
static	int		map_alloc;

static	lwpstack_t *stacks = NULL;
static	uint_t	nstacks = 0;

#define	MAX_TRIES	5

static int
getstack(void *data, const lwpstatus_t *lsp)
{
	int *np = (int *)data;

	if (Plwp_alt_stack(Pr, lsp->pr_lwpid, &stacks[*np].lwps_stack) == 0) {
		stacks[*np].lwps_stack.ss_flags |= SS_ONSTACK;
		stacks[*np].lwps_lwpid = lsp->pr_lwpid;
		(*np)++;
	}

	if (Plwp_main_stack(Pr, lsp->pr_lwpid, &stacks[*np].lwps_stack) == 0) {
		stacks[*np].lwps_lwpid = lsp->pr_lwpid;
		(*np)++;
	}

	return (0);
}

/*
 * We compare the high memory addresses since stacks are faulted in from
 * high memory addresses to low memory addresses, and our prmap_t
 * structures identify only the range of addresses that have been faulted
 * in so far.
 */
static int
cmpstacks(const void *ap, const void *bp)
{
	const lwpstack_t *as = ap;
	const lwpstack_t *bs = bp;
	uintptr_t a = (uintptr_t)as->lwps_stack.ss_sp + as->lwps_stack.ss_size;
	uintptr_t b = (uintptr_t)bs->lwps_stack.ss_sp + bs->lwps_stack.ss_size;

	if (a < b)
		return (1);
	if (a > b)
		return (-1);
	return (0);
}

static char *
make_name(struct ps_prochandle *Pr, uintptr_t addr, const char *mapname,
	char *buf, size_t bufsz)
{
	const pstatus_t		*Psp = Pstatus(Pr);
	const psinfo_t		*pi = Ppsinfo(Pr);
	char			fname[100];
	struct stat		statb;
	int			len;
	char			zname[ZONENAME_MAX];
	char			zpath[PATH_MAX];
	char			objname[PATH_MAX];

	if (strcmp(mapname, "a.out") == 0 &&
	    Pexecname(Pr, buf, bufsz) != NULL)
		return (buf);

	if (Pobjname(Pr, addr, objname, sizeof (objname)) != NULL) {
		(void) strncpy(buf, objname, bufsz);

		if ((len = resolvepath(buf, buf, bufsz)) > 0) {
			buf[len] = '\0';
			return (buf);
		}

		/*
		 * If the target is in a non-global zone, attempt to prepend
		 * the zone path in order to give the global-zone caller the
		 * real path to the file.
		 */
		if (getzonenamebyid(pi->pr_zoneid, zname,
			sizeof (zname)) != -1 && strcmp(zname, "global") != 0 &&
		    zone_get_zonepath(zname, zpath, sizeof (zpath)) == Z_OK) {
			(void) strncat(zpath, "/root",
			    MAXPATHLEN - strlen(zpath));

			if (bufsz <= strlen(zpath))
				return (NULL);

			(void) strncpy(buf, zpath, bufsz);
			(void) strncat(buf, objname, bufsz - strlen(zpath));
		}

		if ((len = resolvepath(buf, buf, bufsz)) > 0) {
			buf[len] = '\0';
			return (buf);
		}
	}

	if (Pstate(Pr) != PS_DEAD && *mapname != '\0') {
		(void) snprintf(fname, sizeof (fname), "/proc/%d/object/%s",
			(int)Psp->pr_pid, mapname);
		if (stat(fname, &statb) == 0) {
			dev_t dev = statb.st_dev;
			ino_t ino = statb.st_ino;
			(void) snprintf(buf, bufsz, "dev:%lu,%lu ino:%lu",
				(ulong_t)major(dev), (ulong_t)minor(dev), ino);
			return (buf);
		}
	}

	return (NULL);
}

static char *
anon_name(char *name, const pstatus_t *Psp,
    uintptr_t vaddr, size_t size, int mflags, int shmid)
{
	if (mflags & MA_ISM) {
		if (shmid == -1)
			(void) snprintf(name, PATH_MAX, "  [ %s shmid=null ]",
			    (mflags & MA_NORESERVE) ? "ism" : "dism");
		else
			(void) snprintf(name, PATH_MAX, "  [ %s shmid=0x%x ]",
			    (mflags & MA_NORESERVE) ? "ism" : "dism", shmid);
	} else if (mflags & MA_SHM) {
		if (shmid == -1)
			(void) sprintf(name, "  [ shmid=null ]");
		else
			(void) sprintf(name, "  [ shmid=0x%x ]", shmid);
	} else if (vaddr + size > Psp->pr_stkbase &&
	    vaddr < Psp->pr_stkbase + Psp->pr_stksize) {
		(void) strcpy(name, "  [ stack ]");
	} else if ((mflags & MA_ANON) &&
	    vaddr + size > Psp->pr_brkbase &&
	    vaddr < Psp->pr_brkbase + Psp->pr_brksize) {
		(void) strcpy(name, "  [ heap ]");
	} else {
		lwpstack_t key, *stk;

		key.lwps_stack.ss_sp = (void *)vaddr;
		key.lwps_stack.ss_size = size;
		if (nstacks > 0 &&
		    (stk = bsearch(&key, stacks, nstacks, sizeof (stacks[0]),
		    cmpstacks)) != NULL) {
			(void) snprintf(name, PATH_MAX, "  [ %s tid=%d ]",
			    (stk->lwps_stack.ss_flags & SS_ONSTACK) ?
			    "altstack" : "stack",
			    stk->lwps_lwpid);
		} else if (Pstate(Pr) != PS_DEAD) {
			(void) strcpy(name, "  [ anon ]");
		} else {
			return (NULL);
		}
	}

	return (name);
}

static int
xmapping_iter(struct ps_prochandle *Pr, proc_xmap_f *func, void *cd, int doswap)
{
	char mapname[PATH_MAX];
	int mapfd, nmap, i, rc;
	struct stat st;
	prxmap_t *prmapp, *pmp;
	ssize_t n;

	(void) snprintf(mapname, sizeof (mapname),
	    "/proc/%d/xmap", (int)Pstatus(Pr)->pr_pid);

	if ((mapfd = open(mapname, O_RDONLY)) < 0 || fstat(mapfd, &st) != 0) {
		if (mapfd >= 0)
			(void) close(mapfd);
		return (perr(mapname));
	}

	nmap = st.st_size / sizeof (prxmap_t);
	nmap *= 2;
again:
	prmapp = malloc((nmap + 1) * sizeof (prxmap_t));

	if ((n = pread(mapfd, prmapp, (nmap + 1) * sizeof (prxmap_t), 0)) < 0) {
		(void) close(mapfd);
		free(prmapp);
		return (perr("read xmap"));
	}

	if (nmap < n / sizeof (prxmap_t)) {
		free(prmapp);
		nmap *= 2;
		goto again;
	}

	(void) close(mapfd);
	nmap = n / sizeof (prxmap_t);

	for (i = 0, pmp = prmapp; i < nmap; i++, pmp++) {
		if ((rc = func(cd, pmp, NULL, i == nmap - 1, doswap)) != 0) {
			free(prmapp);
			return (rc);
		}
	}

	/*
	 * Mark the last element.
	 */
	if (map_count > 0)
		maps[map_count - 1].md_last = B_TRUE;

	free(prmapp);
	return (0);
}

/*ARGSUSED*/
static int
look_xmap_nopgsz(void *data,
	const prxmap_t *pmp,
	const char *object_name,
	int last, int doswap)
{
	const pstatus_t *Psp = Pstatus(Pr);
	char mname[PATH_MAX];
	char *lname = NULL;
	char *ln;
	static uintptr_t prev_vaddr;
	static size_t prev_size;
	static offset_t prev_offset;
	static int prev_mflags;
	static char *prev_lname;
	static char prev_mname[PATH_MAX];
	static ulong_t prev_rss;
	static ulong_t prev_anon;
	static ulong_t prev_locked;
	static ulong_t prev_swap;
	int merged = 0;
	static int first = 1;
	ulong_t swap = 0;
	int kperpage;
	int vo = 0;
	char **values = (char **)data;

	/*
	 * Calculate swap reservations
	 */
	if (pmp->pr_mflags & MA_SHARED) {
		if ((pmp->pr_mflags & MA_NORESERVE) == 0) {
			/* Swap reserved for entire non-ism SHM */
			swap = pmp->pr_size / pmp->pr_pagesize;
		}
	} else if (pmp->pr_mflags & MA_NORESERVE) {
		/* Swap reserved on fault for each anon page */
		swap = pmp->pr_anon;
	} else if (pmp->pr_mflags & MA_WRITE) {
		/* Swap reserve for entire writable segment */
		swap = pmp->pr_size / pmp->pr_pagesize;
	}

	/*
	 * If the mapping is not anon or not part of the heap, make a name
	 * for it.  We don't want to report the heap as a.out's data.
	 */
	if (!(pmp->pr_mflags & MA_ANON) ||
	    pmp->pr_vaddr + pmp->pr_size <= Psp->pr_brkbase ||
	    pmp->pr_vaddr >= Psp->pr_brkbase + Psp->pr_brksize) {
		lname = make_name(Pr, pmp->pr_vaddr, pmp->pr_mapname,
		    mname, sizeof (mname));
	}

	if (lname != NULL) {
		if ((ln = strrchr(lname, '/')) != NULL)
			lname = ln + 1;
	} else if ((pmp->pr_mflags & MA_ANON) || Pstate(Pr) == PS_DEAD) {
		lname = anon_name(mname, Psp, pmp->pr_vaddr,
		    pmp->pr_size, pmp->pr_mflags, pmp->pr_shmid);
	}

	kperpage = pmp->pr_pagesize / KILOBYTE;

	prev_vaddr = pmp->pr_vaddr;
	prev_size = pmp->pr_size;
	prev_offset = pmp->pr_offset;
	prev_mflags = pmp->pr_mflags;
	if (lname == NULL) {
		prev_lname = NULL;
	} else {
		(void) strcpy(prev_mname, lname);
		prev_lname = prev_mname;
	}
	prev_rss = pmp->pr_rss * kperpage;
	prev_anon = pmp->pr_anon * kperpage;
	prev_locked = pmp->pr_locked * kperpage;
	prev_swap = swap * kperpage;

        values[vo] = palloc(32 * sizeof(char));
        snprintf(values[vo], 32, "%lu", (ulong_t)prev_vaddr);
	vo++;

        values[vo] = palloc(32 * sizeof(char));
        snprintf(values[vo], 32, "%ld", prev_size);
	vo++;

       	values[vo] = palloc(32 * sizeof(char));
       	snprintf(values[vo], 32, "%ld", prev_rss);
	vo++;
       	values[vo] = palloc(32 * sizeof(char));
       	snprintf(values[vo], 32, "%ld", prev_anon);
	vo++;
       	values[vo] = palloc(32 * sizeof(char));
       	snprintf(values[vo], 32, "%ld", prev_locked);
	vo++;

	values[vo] = palloc(2 * sizeof(char));
	values[vo][0] = (prev_mflags & MA_READ)?'t':'f';
        values[vo][1] = '\0';
        vo++;
	values[vo] = palloc(2 * sizeof(char));
	values[vo][0] = (prev_mflags & MA_WRITE)?'t':'f';
        values[vo][1] = '\0';
        vo++;
	values[vo] = palloc(2 * sizeof(char));
	values[vo][0] = (prev_mflags & MA_EXEC)?'t':'f';
        values[vo][1] = '\0';
        vo++;
	values[vo] = palloc(2 * sizeof(char));
	values[vo][0] = (prev_mflags & MA_SHARED)?'t':'f';
        values[vo][1] = '\0';
        vo++;
	values[vo] = palloc(2 * sizeof(char));
	values[vo][0] = (prev_mflags & MA_NORESERVE)?'t':'f';
        values[vo][1] = '\0';
        vo++;
	values[vo] = palloc(2 * sizeof(char));
	values[vo][0] = (prev_mflags & MA_RESERVED1)?'t':'f';
        values[vo][1] = '\0';
        vo++;

        values[vo] = NULL;
        if(prev_lname) {
		values[vo] = palloc(16 * sizeof(char));
		if(!strncmp(prev_lname, "  [ heap ", strlen("  [ heap "))) {
	          snprintf(values[vo], 16, "%s", "heap");
	        }
		else if(!strncmp(prev_lname, "  [ stack ", strlen("  [ stack "))) {
	          snprintf(values[vo], 16, "%s", "stack");
	        }
		else if(!strncmp(prev_lname, "  [ anon ", strlen("  [ anon "))) {
	          snprintf(values[vo], 16, "%s", "anon");
	        }
		else if(!strncmp(prev_lname, "  [ ism ", strlen("  [ ism "))) {
	          snprintf(values[vo], 16, "%s", "shared");
	        }
		else if(!strncmp(prev_lname, "  [ dism ", strlen("  [ dism "))) {
	          snprintf(values[vo], 16, "%s", "shared");
	        }
		else {
	          snprintf(values[vo], 16, "%s", "file");
	        }
	}
	vo++;

	values[vo] = NULL;
	if(prev_lname) {
		values[vo] = palloc(strlen(prev_lname)+1);
		strcpy(values[vo], prev_lname);
	}
	vo++;

	return (0);
}

static int
perr(char *s)
{
	if (!s) s = procname;
	ereport(ERROR, (errmsg("%s: %s", s, strerror(errno))));
	return (1);
}

static mapdata_t *
nextmap(void)
{
	mapdata_t *newmaps;
	int next;

	if (map_count == map_alloc) {
		if (map_alloc == 0)
			next = 16;
		else
			next = map_alloc * 2;

		newmaps = realloc(maps, next * sizeof (mapdata_t));
		if (newmaps == NULL) {
			(void) perr("failed to allocate maps");
			return NULL;
		}
		(void) memset(newmaps + map_alloc, '\0',
		    (next - map_alloc) * sizeof (mapdata_t));

		map_alloc = next;
		maps = newmaps;
	}

	return (&maps[map_count++]);
}

/*ARGSUSED*/
static int
gather_xmap(void *ignored, const prxmap_t *xmap, const char *objname,
    int last, int doswap)
{
	mapdata_t *data;

	/* Skip mappings which are outside the range specified by -A */
	if (!address_in_range(xmap->pr_vaddr,
		xmap->pr_vaddr + xmap->pr_size, xmap->pr_pagesize))
		return (0);

	data = nextmap();
	data->md_xmap = *xmap;
	if (data->md_objname != NULL)
		free(data->md_objname);
	data->md_objname = objname ? strdup(objname) : NULL;
	data->md_last = last;
	data->md_doswap = doswap;

	return (0);
}

static int
iter_map(proc_map_f *func, void *data)
{
	int i;
	int ret;

	for (i = 0; i < map_count; i++) {
		if ((ret = func(data, &maps[i].md_map,
		    maps[i].md_objname)) != 0)
			return (ret);
	}

	return (0);
}

static int
iter_xmap(proc_xmap_f *func, void *data)
{
	int i;
	int ret;

	for (i = 0; i < map_count; i++) {
		if ((ret = func(data, &maps[i].md_xmap, maps[i].md_objname,
		    maps[i].md_last, maps[i].md_doswap)) != 0)
			return (ret);
	}

	return (0);
}

/*
 * Convert lgroup ID to string.
 * returns dash when lgroup ID is invalid.
 */
static char *
lgrp2str(lgrp_id_t lgrp)
{
	static char lgrp_buf[20];
	char *str = lgrp_buf;

	(void) sprintf(str, lgrp == LGRP_NONE ? "   -" : "%4d", lgrp);
	return (str);
}

/*
 * Parse address range specification for -A option.
 * The address range may have the following forms:
 *
 * address
 *	start and end is set to address
 * address,
 *	start is set to address, end is set to INVALID_ADDRESS
 * ,address
 *	start is set to 0, end is set to address
 * address1,address2
 *	start is set to address1, end is set to address2
 *
 */
static int
parse_addr_range(char *input_str, uintptr_t *start, uintptr_t *end)
{
	char *startp = input_str;
	char *endp = strchr(input_str, ',');
	ulong_t	s = (ulong_t)INVALID_ADDRESS;
	ulong_t e = (ulong_t)INVALID_ADDRESS;

	if (endp != NULL) {
		/*
		 * Comma is present. If there is nothing after comma, the end
		 * remains set at INVALID_ADDRESS. Otherwise it is set to the
		 * value after comma.
		 */
		*endp = '\0';
		endp++;

		if ((*endp != '\0') && sscanf(endp, "%lx", &e) != 1)
			return (1);
	}

	if (startp != NULL) {
		/*
		 * Read the start address, if it is specified. If the address is
		 * missing, start will be set to INVALID_ADDRESS.
		 */
		if ((*startp != '\0') && sscanf(startp, "%lx", &s) != 1)
			return (1);
	}

	/* If there is no comma, end becomes equal to start */
	if (endp == NULL)
		e = s;

	/*
	 * ,end implies 0..end range
	 */
	if (e != INVALID_ADDRESS && s == INVALID_ADDRESS)
		s = 0;

	*start = (uintptr_t)s;
	*end = (uintptr_t)e;

	/* Return error if neither start nor end address were specified */
	return (! (s != INVALID_ADDRESS || e != INVALID_ADDRESS));
}

/*
 * Check whether any portion of [start, end] segment is within the
 * [start_addr, end_addr] range.
 *
 * Return values:
 *   0 - address is outside the range
 *   1 - address is within the range
 */
static int
address_in_range(uintptr_t start, uintptr_t end, size_t psz)
{
	int rc = 1;

	/*
	 *  Nothing to do if there is no address range specified with -A
	 */
	if (start_addr != INVALID_ADDRESS || end_addr != INVALID_ADDRESS) {
		/* The segment end is below the range start */
		if ((start_addr != INVALID_ADDRESS) &&
		    (end < P2ALIGN(start_addr, psz)))
			rc = 0;

		/* The segment start is above the range end */
		if ((end_addr != INVALID_ADDRESS) &&
		    (start > P2ALIGN(end_addr + psz, psz)))
			rc = 0;
	}
	return (rc);
}


PG_FUNCTION_INFO_V1(sol_pmap_pid);

Datum
sol_pmap_pid(PG_FUNCTION_ARGS)
{
    FuncCallContext     *funcctx;
    int                  call_cntr;
    int                  max_calls;
    TupleDesc            tupdesc;
    AttInMetadata       *attinmeta;

    struct rlimit rlim;
    struct stat64 statbuf;
    int gcode;
    int rc = 1;
    int tries = 0;
    int prr_flags = 0;
    psinfo_t psinfo;
    int mapfd;
    int i;
    int old_pr_pid;

#define SAVEPID(Pr) (old_pr_pid = *((int *)(Pr)))
#define FAKEPID(Pr, pid) (*((int *)(Pr)) = (pid))
#define RESTOREPID(Pr) (*((int *)(Pr)) = old_pr_pid)

  /* stuff done only on the first call of the function */
     if (SRF_IS_FIRSTCALL())
     {
        char         ***values = NULL;
        MemoryContext   oldcontext;
	char            cpid[10];

        /* create a function context for cross-call persistence */
        funcctx = SRF_FIRSTCALL_INIT();

        /* switch to memory context appropriate for multiple function calls */
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

	snprintf(cpid, sizeof(cpid)-1, "%d", PG_GETARG_INT32(0));
	map_count = 0;
	do {
	        /*
	         * Make sure we'll have enough file descriptors to handle a target
	         * that has many many mappings.
	         */
	        if (getrlimit(RLIMIT_NOFILE, &rlim) == 0) {
	                rlim.rlim_cur = rlim.rlim_max;
	                (void) setrlimit(RLIMIT_NOFILE, &rlim);
	                /* (void) enable_extended_FILE_stdio(-1, -1); */
	        }
	
	
	        if ((Pr = proc_arg_grab(cpid, PR_ARG_ANY,
					PGRAB_RDONLY, &gcode)) == NULL) {
	                ereport(WARNING,
				(errmsg("cannot examine %s: %s\n",
	          			cpid, Pgrab_error(gcode)),
				errhint("process not running")));
	                rc++;
	                break;
	        }

		SAVEPID(Pr);
		FAKEPID(Pr, atoi(cpid));
	        procname = cpid;         /* for perr() */
	
	        addr_width = (Pstatus(Pr)->pr_dmodel == PR_MODEL_LP64) ? 16 : 8;
	        size_width = (Pstatus(Pr)->pr_dmodel == PR_MODEL_LP64) ? 11 : 8;
	        (void) memcpy(&psinfo, Ppsinfo(Pr), sizeof (psinfo_t));
	        proc_unctrl_psinfo(&psinfo);
	
	        if (Pstate(Pr) != PS_DEAD) {
			static char buf[32];
	                (void) snprintf(buf, sizeof (buf),
	                    "/proc/%d/map", (int)psinfo.pr_pid);
	                if ((mapfd = open(buf, O_RDONLY)) < 0) {
				ereport(ERROR, (errmsg("cannot examine %s: lost control of process", cpid)));
	                        rc++;
				RESTOREPID(Pr);
	                        Prelease(Pr, prr_flags);
	                        break;
	                }
	        } else {
	                mapfd = -1;
	        }
	
	again:
	        map_count = 0;
	
	        if (!(Pstatus(Pr)->pr_flags & PR_ISSYS)) {
	
	                /*
	                 * Since we're grabbing the process readonly, we need
	                 * to make sure the address space doesn't change during
	                 * execution.
	                 */
	                if (Pstate(Pr) != PS_DEAD) {
	                        if (tries++ == MAX_TRIES) {
					RESTOREPID(Pr);
	                                Prelease(Pr, prr_flags);
	                                (void) close(mapfd);
					ereport(ERROR, (errmsg("cannot examine %s: address space is changing", cpid)));
	                                break;
	                        }
	
	                        if (fstat64(mapfd, &statbuf) != 0) {
					RESTOREPID(Pr);
	                                Prelease(Pr, prr_flags);
	                                (void) close(mapfd);
					ereport(ERROR, (errmsg("cannot examine %s: lost control of process", cpid)));
	                                break;
	                        }
	                }
	
	                nstacks = psinfo.pr_nlwp * 2;
	                stacks = calloc(nstacks, sizeof (stacks[0]));
	                if (stacks != NULL) {
	                        int n = 0;
	                        (void) Plwp_iter(Pr, getstack, &n);
	                        qsort(stacks, nstacks, sizeof (stacks[0]),
	                            cmpstacks);
	                }
	
	                if (Pgetauxval(Pr, AT_BASE) != -1L &&
	                    Prd_agent(Pr) == NULL) {
				ereport(WARNING,
					(errmsg("librtld_db failed to initialize")));
	                }
		}

	        rc += xmapping_iter(Pr, gather_xmap, NULL, 0);
	
	        /*
	         * Ensure mappings are consistent.
	         */
	        if (Pstate(Pr) != PS_DEAD) {
	                struct stat64 newbuf;
	
	                if (fstat64(mapfd, &newbuf) != 0 ||
	                    memcmp(&newbuf.st_mtim, &statbuf.st_mtim,
	                    sizeof (newbuf.st_mtim)) != 0) {
	                        if (stacks != NULL) {
	                                free(stacks);
	                                stacks = NULL;
	                        }
	                        goto again;
	                }
	        }

        	values = (char ***) palloc(map_count * sizeof(char **));
		for(i=0; i<map_count; i++) {
        		values[i] = (char **) palloc(SOL_MAP_DATA_CNT * sizeof(char *));
        		memset(values[i], 0, SOL_MAP_DATA_CNT * sizeof(char *));
        		look_xmap_nopgsz(values[i], &maps[i].md_xmap,
				maps[i].md_objname,
				maps[i].md_last,
				maps[i].md_doswap);
		}

		RESTOREPID(Pr);
	        Prelease(Pr, prr_flags);
	        if (mapfd != -1)
	        	(void) close(mapfd);
	} while(0);

	/* values get stashed for the rest of the call */
	funcctx->user_fctx = values;

        /* total number of tuples to be returned */
        funcctx->max_calls = map_count;

        /* Build a tuple descriptor for our result type */
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

    /* stuff done on every call of the function */
    funcctx = SRF_PERCALL_SETUP();

    call_cntr = funcctx->call_cntr;
    max_calls = funcctx->max_calls;
    attinmeta = funcctx->attinmeta;

    if (max_calls != map_count) {
      ereport(WARNING,
		(errmsg("pmap internet inconsistency"),
		errhint("Try again")));
      SRF_RETURN_DONE(funcctx);
    }

    if (call_cntr < max_calls)     /* do when there is more left to send */
    {
        HeapTuple    tuple;
        Datum        result;
	char      ***values;
        /*
         * Prepare a values array for building the returned tuple.
         * This should be an array of C strings which will
         * be processed later by the type input functions.
         */

        values = (char ***)funcctx->user_fctx;
        /* build a tuple */
        tuple = BuildTupleFromCStrings(attinmeta, values[call_cntr]);

        /* make the tuple into a datum */
        result = HeapTupleGetDatum(tuple);

        SRF_RETURN_NEXT(funcctx, result);
    }
    else    /* do when there is no more left */
    {
        SRF_RETURN_DONE(funcctx);
    }
}
