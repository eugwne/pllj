#PG_CONFIG ?= /usr/local/pgsql/bin/pg_config
PG_CONFIG ?= pg_config
PKG_LIBDIR := $(shell $(PG_CONFIG) --pkglibdir)

LUA_INCDIR ?= /usr/local/include/luajit-2.1
LUALIB ?= -L/usr/local/lib -lluajit-5.1
LUA_DIR ?= /usr/local/share/lua/5.1

ifeq ($(PLLJ_UNTRUSTED), 1)
    MODULE_big = pllju
    EXTENSION = pllju
    DATA = pllju--0.1.sql
REGRESS = \
plljutest \
ucomposite \
usetof

ifneq ($(PLLJ_SKIP_LONG_TEST), 1)
REGRESS += ustackdepth 
endif

else
    MODULE_big = pllj
    EXTENSION = pllj
    DATA = pllj--0.1.sql

REGRESS = \
plljtest \
type_string_conv \
functional \
arraytest \
composite \
setof \
inout \
hstoretest \
ereport

endif


OBJS = \
pllj.o 

PG_CPPFLAGS = -I$(LUA_INCDIR) 

ifeq ($(PLLJ_UNTRUSTED), 1)
    PG_CPPFLAGS += -DPLLJ_UNTRUSTED
endif

ifeq ($(PLLJ_SKIP_LJVER_CHECK), 1)
    PG_CPPFLAGS += -PLLJ_SKIP_LJVER_CHECK
endif

SHLIB_LINK = $(LUALIB)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

install-module:
	mkdir -p $(LUA_DIR)/pllj
	mkdir -p $(LUA_DIR)/pllj/pg
	mkdir -p $(LUA_DIR)/pllj/type
	cp src/pllj.lua $(LUA_DIR)/pllj.lua
	cp src/pllj/env.lua $(LUA_DIR)/pllj/env.lua
	cp src/pllj/func.lua $(LUA_DIR)/pllj/func.lua
	cp src/pllj/io.lua $(LUA_DIR)/pllj/io.lua 
	cp src/pllj/misc.lua $(LUA_DIR)/pllj/misc.lua
	cp src/pllj/spi.lua $(LUA_DIR)/pllj/spi.lua
	cp src/pllj/srf.lua $(LUA_DIR)/pllj/srf.lua
	cp src/pllj/trigger.lua $(LUA_DIR)/pllj/trigger.lua
	cp src/pllj/tuple_ops.lua $(LUA_DIR)/pllj/tuple_ops.lua 
	cp src/pllj/pg/api_*.lua $(LUA_DIR)/pllj/pg
	cp src/pllj/pg/func.lua $(LUA_DIR)/pllj/pg/func.lua
	cp src/pllj/pg/init_c.lua $(LUA_DIR)/pllj/pg/init_c.lua
	cp src/pllj/pg/macro.lua $(LUA_DIR)/pllj/pg/macro.lua
	cp src/pllj/pg/misc.lua $(LUA_DIR)/pllj/pg/misc.lua
	cp src/pllj/pg/pg_error.lua $(LUA_DIR)/pllj/pg/pg_error.lua
	cp src/pllj/pg/syscache.lua $(LUA_DIR)/pllj/pg/syscache.lua
	cp src/pllj/pg/type_info.lua $(LUA_DIR)/pllj/pg/type_info.lua
	cp src/pllj/type/array[T].lua $(LUA_DIR)/pllj/type/array[T].lua
	cp src/pllj/type/composite[T].lua $(LUA_DIR)/pllj/type/composite[T].lua
	cp src/pllj/type/datum[T].lua $(LUA_DIR)/pllj/type/datum[T].lua
	cp src/pllj/type/void.lua $(LUA_DIR)/pllj/type/void.lua
	cp src/pllj/type/text.lua $(LUA_DIR)/pllj/type/text.lua
	cp src/pllj/type/bool.lua $(LUA_DIR)/pllj/type/bool.lua
	cp src/pllj/type/int2.lua $(LUA_DIR)/pllj/type/int2.lua
	cp src/pllj/type/int4.lua $(LUA_DIR)/pllj/type/int4.lua
	cp src/pllj/type/int8.lua $(LUA_DIR)/pllj/type/int8.lua
	cp src/pllj/type/float4.lua $(LUA_DIR)/pllj/type/float4.lua
	cp src/pllj/type/float8.lua $(LUA_DIR)/pllj/type/float8.lua
	cp src/pllj/type/float4array.lua $(LUA_DIR)/pllj/type/float4array.lua
	cp src/pllj/type/float8array.lua $(LUA_DIR)/pllj/type/float8array.lua
	cp src/pllj/type/int2array.lua $(LUA_DIR)/pllj/type/int2array.lua
	cp src/pllj/type/int4array.lua $(LUA_DIR)/pllj/type/int4array.lua
	cp src/pllj/type/int8array.lua $(LUA_DIR)/pllj/type/int8array.lua
	cp src/pllj/type/textarray.lua $(LUA_DIR)/pllj/type/textarray.lua
	cp src/pllj/type/record.lua $(LUA_DIR)/pllj/type/record.lua
	cp src/pllj/type/hstore.lua $(LUA_DIR)/pllj/type/hstore.lua
	cp src/pllj/type/rtti.lua $(LUA_DIR)/pllj/type/rtti.lua

