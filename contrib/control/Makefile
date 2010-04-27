MODULE_big	= controldata
OBJS		= controldata.o
DOCS		= README.controldata
DATA		= uninstall_controldata.sql controldata.sql

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/controldata
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

