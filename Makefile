PG_CONFIG ?= pg_config #/usr/local/pgsql/bin/pg_config
PKG_LIBDIR := $(shell $(PG_CONFIG) --pkglibdir)

LUA_INCDIR ?= /usr/local/include/luajit-2.1
LUALIB ?= -L/usr/local/lib -lluajit-5.1
LUA_DIR ?= /usr/local/share/lua/5.1

MODULE_big = pllj
EXTENSION = pllj
DATA = pllj--0.1.sql

REGRESS = \
plljtest 

OBJS = \
pllj.o 

PG_CPPFLAGS = -I$(LUA_INCDIR)
SHLIB_LINK = $(LUALIB)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

install-module:
	mkdir -p $(LUA_DIR)/pllj
	cp src/pllj.lua $(LUA_DIR)/pllj.lua
	cp src/pllj/pgdefines.lua $(LUA_DIR)/pllj/pgdefines.lua
	cp src/pllj/spi.lua $(LUA_DIR)/pllj/spi.lua
