#include "postgres.h"
#include "executor/spi.h"
#include "commands/trigger.h"
#include "fmgr.h"
#include "access/heapam.h"
#include "utils/syscache.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"

#include "access/htup_details.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <luajit.h>

#define out(...) ereport(INFO, (errmsg(__VA_ARGS__)))

static lua_State *L = NULL;
static int inline_ref = 0;

static Datum lj_validator (Oid oid) {
	PG_RETURN_VOID();
}

static Datum lj_callhandler (FunctionCallInfo fcinfo) {
	PG_RETURN_VOID();
}
static Datum lj_inlinehandler (const char *source) {
	lua_rawgeti(L, LUA_REGISTRYINDEX, inline_ref);
	lua_pushstring(L, source);
	lua_pcall(L, 1, 0, 0);

	PG_RETURN_VOID();
}

extern Datum pllj_heap_getattr(HeapTuple tuple, int16_t attnum, TupleDesc tupleDesc, bool *isnull);
Datum pllj_heap_getattr(HeapTuple tuple, int16_t attnum, TupleDesc tupleDesc, bool *isnull){
    Datum value = heap_getattr(tuple, attnum, tupleDesc, isnull);
    return value;
}

PGDLLEXPORT Datum _PG_init(PG_FUNCTION_ARGS);
PGDLLEXPORT Datum _PG_fini(PG_FUNCTION_ARGS);
PGDLLEXPORT Datum pllj_validator(PG_FUNCTION_ARGS);
PGDLLEXPORT Datum pllj_call_handler(PG_FUNCTION_ARGS);

#if PG_VERSION_NUM >= 90000
PGDLLEXPORT Datum pllj_inline_handler(PG_FUNCTION_ARGS);
#endif

PG_FUNCTION_INFO_V1(_PG_init);
Datum _PG_init(PG_FUNCTION_ARGS) {
	int status;

	L = lua_open();

	LUAJIT_VERSION_SYM();
	lua_gc(L, LUA_GCSTOP, 0);
	luaL_openlibs(L);
	lua_gc(L, LUA_GCRESTART, -1);

	lua_getglobal(L, "require");
	lua_pushstring(L, "pllj");
	status = lua_pcall(L, 1, 1, 0);
	if (status)
		return 1;
	lua_getfield(L, 1, "inlinehandler");
	inline_ref  = luaL_ref(L, LUA_REGISTRYINDEX);
	lua_settop(L, 0);

	PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(_PG_fini);
Datum _PG_fini(PG_FUNCTION_ARGS) {
	lua_close(L);
	PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(pllj_validator);
Datum pllj_validator(PG_FUNCTION_ARGS) {
	return lj_validator(PG_GETARG_OID(0));
}

PG_FUNCTION_INFO_V1(pllj_call_handler);
Datum pllj_call_handler(PG_FUNCTION_ARGS) {
	return lj_callhandler(fcinfo);
}

#if PG_VERSION_NUM >= 90000
#define CODEBLOCK \
	((InlineCodeBlock *) DatumGetPointer(PG_GETARG_DATUM(0)))->source_text


PG_FUNCTION_INFO_V1(pllj_inline_handler);
Datum pllj_inline_handler(PG_FUNCTION_ARGS) {
	return lj_inlinehandler(CODEBLOCK);
}
#endif
