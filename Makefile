#PG_CONFIG ?= /usr/local/pgsql/bin/pg_config
PG_CONFIG ?= pg_config
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
	mkdir -p $(LUA_DIR)/pllj/pg
	cp src/pllj.lua $(LUA_DIR)/pllj.lua
	cp src/pllj/pgdefines.lua $(LUA_DIR)/pllj/pgdefines.lua
	cp src/pllj/func.lua $(LUA_DIR)/pllj/func.lua
	cp src/pllj/trigger.lua $(LUA_DIR)/pllj/trigger.lua
	cp src/pllj/spi.lua $(LUA_DIR)/pllj/spi.lua
	cp src/pllj/pg/i.lua $(LUA_DIR)/pllj/pg/i.lua
	cp src/pllj/pg/macro.lua $(LUA_DIR)/pllj/pg/macro.lua
	cp src/pllj/pg/pg_error.lua $(LUA_DIR)/pllj/pg/pg_error.lua
	cp src/pllj/pg/syscache.lua $(LUA_DIR)/pllj/pg/syscache.lua
	cp src/pllj/pg/init_c.lua $(LUA_DIR)/pllj/pg/init_c.lua
	cp src/pllj/pg/to_lua.lua $(LUA_DIR)/pllj/pg/to_lua.lua
	cp src/pllj/pg/to_pg.lua $(LUA_DIR)/pllj/pg/to_pg.lua
	cp src/pllj/pg/c.lua $(LUA_DIR)/pllj/pg/c.lua
	cp src/pllj/io.lua $(LUA_DIR)/pllj/io.lua 
	cp src/pllj/tuple_ops.lua $(LUA_DIR)/pllj/tuple_ops.lua 
