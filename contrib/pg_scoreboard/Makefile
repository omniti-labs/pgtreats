MODULE_big	= pg_scoreboard
OBJS		= pg_scoreboard.o
DOCS		= README.pg_scoreboard
DATA		= uninstall_pg_scoreboard.sql pg_scoreboard.sql

ifdef USE_PGXS
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
else
subdir = contrib/pg_scoreboard
top_builddir = ../..
include $(top_builddir)/src/Makefile.global
include $(top_srcdir)/contrib/contrib-global.mk
endif

