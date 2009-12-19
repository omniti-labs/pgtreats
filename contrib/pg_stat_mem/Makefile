# $PostgreSQL: pgsql/contrib/cube/Makefile,v 1.15 2005/10/18 01:30:48 tgl Exp $

MODULE_big = pgsol10
OBJS= pmap.o

DATA = pgsol10.sql
DOCS = README.pgsol10
REGRESS = pgsol10

EXTRA_CLEAN = 

PG_CPPFLAGS = -I.

SHLIB_LINK += -lproc -lrtld_db /usr/lib/amd64/libzonecfg.so.1

ifdef USE_PGXS
PGXS := $(shell pg_config --pgxs)
include $(PGXS)
else
subdir = contrib/pgsol10
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

