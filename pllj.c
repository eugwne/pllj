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
#define pg_throw(...) ereport(ERROR, (errmsg(__VA_ARGS__)))

#define luapg_error(L)do{\
  if (lua_type(L, -1) == LUA_TSTRING){ \
    const char *err = pstrdup( lua_tostring((L), -1)); \
    lua_pop(L, lua_gettop(L));\
    ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION), \
      errmsg("[pllj]: error"),\
      errdetail("%s", err)));\
  }else {\
	luatable_report(L, ERROR);\
  }\
}while(0)


static void pllua_parse_error(lua_State *L, ErrorData *edata){
	lua_pushnil(L);
	while (lua_next(L, -2) != 0) {
	if (lua_type(L, -2) == LUA_TSTRING){
		const char *key = lua_tostring(L, -2);
		if (lua_type(L, -1) == LUA_TSTRING){
			if (strcmp(key, "message") == 0){
				edata->message = pstrdup( lua_tostring(L, -1) );
			} else if (strcmp(key, "detail") == 0){
				edata->detail = pstrdup( lua_tostring(L, -1) );
			}  else if (strcmp(key, "hint") == 0){
				edata->hint = pstrdup( lua_tostring(L, -1) );
			} else if (strcmp(key, "context") == 0){
				edata->context = pstrdup( lua_tostring(L, -1) );
			}

		}else if (lua_type(L, -1) == LUA_TNUMBER){
			if (strcmp(key, "sqlerrcode") == 0){
				edata->sqlerrcode = (int)( lua_tonumber(L, -1) );
			}
		}
	}
	lua_pop(L, 1);
	}
}

static void luatable_report(lua_State *L, int elevel)
{
	ErrorData	edata;

	char *query = NULL;
	int position = 0;

	edata.message = NULL;
	edata.sqlerrcode = 0;
	edata.detail = NULL;
	edata.hint = NULL;
	edata.context = NULL;

	pllua_parse_error(L, &edata);
	lua_pop(L, lua_gettop(L));

	elevel = Min(elevel, ERROR);

	ereport(elevel,
	        (errcode(edata.sqlerrcode ? edata.sqlerrcode : ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
	         errmsg_internal("%s", edata.message ? edata.message : "no exception data"),
	         (edata.detail) ? errdetail_internal("%s", edata.detail) : 0,
	         (edata.context) ? errcontext("%s", edata.context) : 0,
	         (edata.hint) ? errhint("%s", edata.hint) : 0,
	         (query) ? internalerrquery(query) : 0,
	         (position) ? internalerrposition(position) : 0));
}

static lua_State *L = NULL;
static int call_ref = 0;
static int inline_ref = 0;

static Datum lj_validator (Oid oid) {
	PG_RETURN_VOID();
}

static volatile Datum call_result;
extern void set_pllj_call_result(Datum result);
void set_pllj_call_result(Datum result){
	call_result = result;
}

static Datum lj_callhandler (FunctionCallInfo fcinfo) {
	int status = 0;
	call_result = (Datum) 0;
	lua_settop(L, 0);
	lua_rawgeti(L, LUA_REGISTRYINDEX, call_ref);
	lua_pushlightuserdata(L, (void *)fcinfo);
	status = lua_pcall(L, 1, 0, 0);

	if (status == 0){
		//PG_RETURN_VOID();
		return call_result;
	}

	if( status == LUA_ERRRUN) {
		luapg_error(L);
	} else if (status == LUA_ERRMEM) {
		pg_throw("%s %s","Memory error:",lua_tostring(L, -1));
	} else if (status == LUA_ERRERR) {
		pg_throw("%s %s","Error:",lua_tostring(L, -1));
	}

	pg_throw("pllj unknown error");
}
static Datum lj_inlinehandler (const char *source) {
	int status = 0;
	lua_settop(L, 0);
	lua_rawgeti(L, LUA_REGISTRYINDEX, inline_ref);
	lua_pushstring(L, source);
	status = lua_pcall(L, 1, 0, 0);

	if (status == 0){
		PG_RETURN_VOID();
	}

	if( status == LUA_ERRRUN) {
		luapg_error(L);
	} else if (status == LUA_ERRMEM) {
		pg_throw("%s %s","Memory error:",lua_tostring(L, -1));
	} else if (status == LUA_ERRERR) {
		pg_throw("%s %s","Error:",lua_tostring(L, -1));
	}

	pg_throw("pllj unknown error");
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
	if( status == LUA_ERRRUN) {
		luapg_error(L);
	} else if (status == LUA_ERRMEM) {
		pg_throw("%s %s","Memory error:",lua_tostring(L, -1));
	} else if (status == LUA_ERRERR) {
		pg_throw("%s %s","Error:",lua_tostring(L, -1));
	}
	lua_getfield(L, 1, "inlinehandler");
	inline_ref  = luaL_ref(L, LUA_REGISTRYINDEX);
	lua_getfield(L, 1, "callhandler");
	call_ref  = luaL_ref(L, LUA_REGISTRYINDEX);
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
