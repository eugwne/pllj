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

static void pllj_parse_error(lua_State *L, ErrorData *edata){
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

extern ErrorData  *last_edata;
ErrorData  *last_edata = NULL;
#define THROW_NUMBER (-1000)

extern Oid lj_HeapTupleGetOid(HeapTuple pht); 
Oid lj_HeapTupleGetOid(HeapTuple pht){
    return HeapTupleGetOid(pht);
}

extern Datum lj_FunctionCallInvoke(FunctionCallInfoData* fcinfo, bool* isok);
Datum lj_FunctionCallInvoke(FunctionCallInfoData* fcinfo, bool* isok) {
    MemoryContext oldcontext = CurrentMemoryContext;
    PG_TRY();
    {
        return FunctionCallInvoke(fcinfo);
    }PG_CATCH(); {
        MemoryContextSwitchTo(oldcontext);
        *isok = false;
        last_edata = CopyErrorData();
        FlushErrorState();
    } PG_END_TRY();
    return 0;
}

extern int lj_SPI_execute(const char *src, bool read_only, long tcount);
int lj_SPI_execute(const char *src, bool read_only, long tcount) {
    volatile int result = 0;
    MemoryContext oldcontext = CurrentMemoryContext;
    PG_TRY();
    {
        result = SPI_execute(src, read_only, tcount);
    }PG_CATCH();    {
        MemoryContextSwitchTo(oldcontext);
        last_edata = CopyErrorData();
        FlushErrorState();
        result = THROW_NUMBER;
        SPI_restore_connection();
    }PG_END_TRY();
    return result;
}

extern int lj_SPI_execute_plan(SPIPlanPtr plan, Datum * values, const char * nulls,
                     bool read_only, long count);
int lj_SPI_execute_plan(SPIPlanPtr plan, Datum * values, const char * nulls,
                     bool read_only, long count) {
    volatile int result = 0;
    MemoryContext oldcontext = CurrentMemoryContext;
    PG_TRY();
    {
        result = SPI_execute_plan(plan, values, nulls, read_only, count);
    }PG_CATCH();    {
        MemoryContextSwitchTo(oldcontext);
        last_edata = CopyErrorData();
        FlushErrorState();
        result = THROW_NUMBER;
        SPI_restore_connection();
    }PG_END_TRY();
    return result;
}



extern SPIPlanPtr lj_SPI_prepare_cursor(const char *src, int nargs, Oid *argtypes, int cursorOptions);
SPIPlanPtr lj_SPI_prepare_cursor(const char *src, int nargs, Oid *argtypes, int cursorOptions){
    MemoryContext oldcontext = CurrentMemoryContext;
    PG_TRY();
    {
        return SPI_prepare_cursor(src, nargs, argtypes, cursorOptions);
    }PG_CATCH();	{
        MemoryContextSwitchTo(oldcontext);
        last_edata = CopyErrorData();
        FlushErrorState();
    }PG_END_TRY();
    return 0;
}

extern bool lj_CALLED_AS_TRIGGER (void* fcinfo);
extern bool lj_CALLED_AS_TRIGGER (void* fcinfo) {
	return CALLED_AS_TRIGGER((FunctionCallInfo)fcinfo);
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

	pllj_parse_error(L, &edata);
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
static int validator_ref = 0;
extern int call_depth;
int call_depth = 0;

static Datum lj_validator (Oid oid) {
	int status = 0;
	lua_State *L1 = L;
	++call_depth;
	if(call_depth > 1) {
		L1 = lua_newthread(L);
	}
	lua_settop(L1, 0);
	lua_rawgeti(L1, LUA_REGISTRYINDEX, validator_ref);
	lua_pushnumber(L1, oid);
	PG_TRY();{
		status = lua_pcall(L1, 1, 0, 0);
		--call_depth;
	}PG_CATCH();{
		--call_depth;
		PG_RE_THROW();
	}PG_END_TRY();

	if (status == 0){
		PG_RETURN_VOID();
	}
	if( status == LUA_ERRRUN) {
		luapg_error(L1);
	} else if (status == LUA_ERRMEM) {
		pg_throw("%s %s","Memory error:",lua_tostring(L1, -1));
	} else if (status == LUA_ERRERR) {
		pg_throw("%s %s","Error:",lua_tostring(L1, -1));
	}

	pg_throw("pllj unknown error");
}

static volatile Datum call_result;
extern void set_pllj_call_result(Datum result);
void set_pllj_call_result(Datum result){
	call_result = result;
}

static lua_State *get_temp_state(){
	int status;
	lua_State *LT;

	LT = lua_open();

	LUAJIT_VERSION_SYM();
	lua_gc(LT, LUA_GCSTOP, 0);
	luaL_openlibs(LT);
	lua_gc(LT, LUA_GCRESTART, -1);

	lua_getglobal(LT, "require");
	lua_pushstring(LT, "pllj");
	status = lua_pcall(LT, 1, 1, 0);
	if( status == LUA_ERRRUN) {
		luapg_error(LT);
	} else if (status == LUA_ERRMEM) {
		pg_throw("%s %s","Memory error:",lua_tostring(LT, -1));
	} else if (status == LUA_ERRERR) {
		pg_throw("%s %s","Error:",lua_tostring(LT, -1));
	}
	lua_getfield(LT, 1, "inlinehandler");
	luaL_ref(LT, LUA_REGISTRYINDEX);
	lua_getfield(LT, 1, "callhandler");
	luaL_ref(LT, LUA_REGISTRYINDEX);
	lua_getfield(LT, 1, "validator");
	luaL_ref(LT, LUA_REGISTRYINDEX);
	lua_settop(LT, 0);
	return LT;
}


static Datum lj_callhandler (FunctionCallInfo fcinfo) {
	int status = 0;
	char	*error_text = NULL;
	lua_State *L1 = L;
	++call_depth;
	call_result = (Datum) 0;
	if(call_depth > 1) {
		L1 = get_temp_state();//lua_newthread(L);
	}
	lua_settop(L1, 0);
	lua_rawgeti(L1, LUA_REGISTRYINDEX, call_ref);
	lua_pushlightuserdata(L1, (void *)fcinfo);
	PG_TRY();{
		status = lua_pcall(L1, 1, 0, 0);
		if (status == LUA_ERRMEM || status == LUA_ERRERR) {
			error_text = pstrdup(lua_tostring(L1, -1));
		}
		if(call_depth > 1) {
			lua_close(L1);
		}
		--call_depth;
	}PG_CATCH();{
		if(call_depth > 1) {
			lua_close(L1);
		}
		--call_depth;
		PG_RE_THROW();
	}PG_END_TRY();

	if (status == 0){
		//PG_RETURN_VOID();
		return call_result;
	}

	if( status == LUA_ERRRUN) {
		if (call_depth > 0) {
			pg_throw("FIXME! error not converted");//luapg_error(L1);
		}else{
			luapg_error(L1);
		}
	} else if (status == LUA_ERRMEM) {
		pg_throw("%s %s","Memory error:",error_text);
	} else if (status == LUA_ERRERR) {
		pg_throw("%s %s","Error:",error_text);
	}

	pg_throw("pllj unknown error");
}
static Datum lj_inlinehandler (const char *source) {
	int status = 0;
	++call_depth;
	lua_settop(L, 0);
	lua_rawgeti(L, LUA_REGISTRYINDEX, inline_ref);
	lua_pushstring(L, source);
	PG_TRY();{
		status = lua_pcall(L, 1, 0, 0);
		--call_depth;
	}PG_CATCH();{
		--call_depth;
		PG_RE_THROW();
	}PG_END_TRY();

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
PGDLLEXPORT Datum pllj_inline_handler(PG_FUNCTION_ARGS);


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
	lua_getfield(L, 1, "validator");
	validator_ref  = luaL_ref(L, LUA_REGISTRYINDEX);
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

#define CODEBLOCK \
	((InlineCodeBlock *) DatumGetPointer(PG_GETARG_DATUM(0)))->source_text


PG_FUNCTION_INFO_V1(pllj_inline_handler);
Datum pllj_inline_handler(PG_FUNCTION_ARGS) {
	return lj_inlinehandler(CODEBLOCK);
}

