#include "postgres.h"
#include "executor/spi.h"
#include "commands/trigger.h"
#include "fmgr.h"
#include "access/heapam.h"
#include "utils/syscache.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"

#include "access/htup_details.h"
#include "access/xact.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <luajit.h>

#define out(...) ereport(INFO, (errmsg(__VA_ARGS__)))
#define warning(...) ereport(WARNING, (errmsg(__VA_ARGS__)))
#define pg_throw(...) ereport(ERROR, (errmsg(__VA_ARGS__)))
#define pg_throw_pllj_detail(err) do{\
    ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION), \
    errmsg("[pllj]: error"),\
    errdetail("%s", err)));\
    }while(0)

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

#define CODEBLOCK \
    ((InlineCodeBlock *) DatumGetPointer(PG_GETARG_DATUM(0)))->source_text

static void pllj_parse_error(lua_State *L, ErrorData *edata){
    edata->message = NULL;
    edata->sqlerrcode = 0;
    edata->detail = NULL;
    edata->hint = NULL;
    edata->context = NULL;
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

typedef struct
{
    ResourceOwner resowner;
    MemoryContext mcontext;

} SubTransactionBlock;
static void stb_enter(lua_State *L, SubTransactionBlock *block){
    if (!IsTransactionOrTransactionBlock())
        luaL_error(L, "out of transaction");

    block->resowner = CurrentResourceOwner;
    block->mcontext = CurrentMemoryContext;
    BeginInternalSubTransaction(NULL);
    /* Do not want to leave the previous memory context */
    MemoryContextSwitchTo(block->mcontext);
}

static void stb_exit(SubTransactionBlock *block, bool success){
    if (success)
        ReleaseCurrentSubTransaction();
    else
        RollbackAndReleaseCurrentSubTransaction();

    MemoryContextSwitchTo(block->mcontext);
    CurrentResourceOwner = block->resowner;

    /*
     * AtEOSubXact_SPI() should not have popped any SPI context, but just
     * in case it did, make sure we remain connected.
     */
    SPI_restore_connection();
}

static int luaP_subt_pcall (lua_State *L) {
    int status = 0;
    SubTransactionBlock subtran;
    subtran.mcontext = NULL;
    subtran.resowner = NULL;

    luaL_checkany(L, 1);

    stb_enter(L, &subtran);

    PG_TRY();{
        status = lua_pcall(L, lua_gettop(L) - 1, LUA_MULTRET, 0);
    }
    PG_CATCH();{
        ErrorData  *edata;
        edata = CopyErrorData();
        ereport(FATAL, (errmsg("Unhandled exception: %s", edata->message)));
    }
    PG_END_TRY();
    stb_exit(&subtran, status == 0);
    

    lua_pushboolean(L, (status == 0));
    lua_insert(L, 1);
    return lua_gettop(L);
}

static const luaL_Reg luaP_funcs[] = {
    {"subt_pcall", luaP_subt_pcall},
    {NULL, NULL}
};

extern ErrorData  *last_edata;
ErrorData  *last_edata = NULL;

extern bool ljm_CALLED_AS_TRIGGER (void* fcinfo);
bool ljm_CALLED_AS_TRIGGER (void* fcinfo) {
    return CALLED_AS_TRIGGER((FunctionCallInfo)fcinfo);
}

extern float4 ljm_DatumGetFloat4(Datum X);
float4 ljm_DatumGetFloat4(Datum X){
    return DatumGetFloat4(X);
}

extern Datum ljm_Float4GetDatum(float4 X);
Datum ljm_Float4GetDatum(float4 X) {
    return Float4GetDatum(X);
}

extern float8 ljm_DatumGetFloat8(Datum X);
float8 ljm_DatumGetFloat8(Datum X){
    return DatumGetFloat8(X);
}

extern Datum ljm_Float8GetDatum(float8 X);
Datum ljm_Float8GetDatum(float8 X) {
    return Float8GetDatum(X);
}


#define LJ_BEGIN_PG_TRY() MemoryContext oldcontext = CurrentMemoryContext; \
    PG_TRY(); \
    { last_edata = NULL;

#define LJ_END_PG_TRY(code)     }PG_CATCH(); { \
        MemoryContextSwitchTo(oldcontext); \
        last_edata = CopyErrorData(); \
        FlushErrorState(); \
        code \
    } PG_END_TRY();

extern Datum lj_InputFunctionCall(FmgrInfo *flinfo, char *str, Oid typioparam, int32 typmod);
Datum lj_InputFunctionCall(FmgrInfo *flinfo, char *str, Oid typioparam, int32 typmod){
    LJ_BEGIN_PG_TRY()
        return InputFunctionCall(flinfo, str, typioparam, typmod);
    LJ_END_PG_TRY()
    return 0;
}

extern Datum lj_FunctionCallInvoke(FunctionCallInfo fcinfo, bool* isok);
Datum lj_FunctionCallInvoke(FunctionCallInfo fcinfo, bool* isok) {
    LJ_BEGIN_PG_TRY()
        return FunctionCallInvoke(fcinfo);
    LJ_END_PG_TRY( {*isok = false;})
    return 0;
}

extern int lj_SPI_execute(const char *src, bool read_only, long tcount);
int lj_SPI_execute(const char *src, bool read_only, long tcount) {
    int result = 0;
    LJ_BEGIN_PG_TRY()
        result = SPI_execute(src, read_only, tcount);
    LJ_END_PG_TRY( {SPI_restore_connection();})

    return result;
}

extern int lj_SPI_execute_plan(SPIPlanPtr plan, Datum * values, const char * nulls,
                     bool read_only, long count);
int lj_SPI_execute_plan(SPIPlanPtr plan, Datum * values, const char * nulls,
                     bool read_only, long count) {
    int result = 0;
    LJ_BEGIN_PG_TRY()
        result = SPI_execute_plan(plan, values, nulls, read_only, count);
    LJ_END_PG_TRY( {SPI_restore_connection();})
    return result;
}



extern SPIPlanPtr lj_SPI_prepare_cursor(const char *src, int nargs, Oid *argtypes, int cursorOptions);
SPIPlanPtr lj_SPI_prepare_cursor(const char *src, int nargs, Oid *argtypes, int cursorOptions){
    LJ_BEGIN_PG_TRY()
        return SPI_prepare_cursor(src, nargs, argtypes, cursorOptions);
    LJ_END_PG_TRY()
    return 0;
}

extern ArrayType *
lj_construct_md_array(Datum *elems,
                    bool *nulls,
                    int ndims,
                    int *dims,
                    int *lbs,
                    Oid elmtype, int elmlen, bool elmbyval, char elmalign);
ArrayType *
lj_construct_md_array(Datum *elems,
                    bool *nulls,
                    int ndims,
                    int *dims,
                    int *lbs,
                    Oid elmtype, int elmlen, bool elmbyval, char elmalign) {
    LJ_BEGIN_PG_TRY()
        return construct_md_array(elems, nulls, ndims, dims,lbs,elmtype,elmlen, elmbyval, elmalign);
    LJ_END_PG_TRY()
    return 0;
}

static void luatable_report(lua_State *L, int elevel)
{
    ErrorData	edata;

    char *query = NULL;
    int position = 0;

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

#define SAVED_VM (10)
static lua_State *AL[SAVED_VM] = {NULL};
static int call_ref = 0;
static int inline_ref = 0;
static int validator_ref = 0;
extern volatile int call_depth;
volatile int call_depth = 0;

static lua_State * get_vm() {
    int status;
    lua_State *L = lua_open();

    LUAJIT_VERSION_SYM();
    lua_gc(L, LUA_GCSTOP, 0);
    luaL_openlibs(L);
    
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    luaL_setfuncs(L, luaP_funcs, 0);
    lua_settop(L, 0);

    lua_gc(L, LUA_GCRESTART, -1);

    lua_getglobal(L, "require");
    lua_pushstring(L, "pllj");
    status = lua_pcall(L, 1, 1, 0);
    //TODO close vm
    if( status == LUA_ERRRUN) {
        luapg_error(L);
    } else if (status == LUA_ERRMEM) {
        pg_throw("%s %s","Memory error:",lua_tostring(L, -1));
    } else if (status == LUA_ERRERR) {
        pg_throw("%s %s","Error:",lua_tostring(L, -1));
    }
    return L;
}

static lua_State *get_temp_state(){
    lua_State *L = get_vm();
    lua_getfield(L, 1, "inlinehandler");
    luaL_ref(L, LUA_REGISTRYINDEX);
    lua_getfield(L, 1, "callhandler");
    luaL_ref(L, LUA_REGISTRYINDEX);
    lua_getfield(L, 1, "validator");
    luaL_ref(L, LUA_REGISTRYINDEX);
    lua_settop(L, 0);
    return L;
}

static lua_State * push_vm() {
    ++call_depth;
    if(call_depth > SAVED_VM) {
        return get_temp_state(); //lua_newthread(L);
    } else {
        if (!AL[call_depth-1]) {
            AL[call_depth-1] = get_temp_state();
        }
        return AL[call_depth-1];
    }

}

static void pop_vm(lua_State * state){
    if(call_depth > SAVED_VM) {
        lua_close(state);
    }
    --call_depth;
}

typedef struct LJFunctionData {
    FunctionCallInfo fcinfo;
    Datum* result;
} LJFunctionData;


static Datum lj_call (FunctionCallInfo fcinfo, int *ref) {
    ErrorData edata;
    char *query = NULL;
    int position = 0;
    char *error_text = NULL;
    LJFunctionData* udata;
    Datum result = (Datum) 0;

    int status = 0;

    int rc;
    lua_State *L;

    if ((rc = SPI_connect()) != SPI_OK_CONNECT) {
        elog(ERROR, "SPI_connect failed: %s", SPI_result_code_string(rc));
    }

    L = push_vm();

    lua_settop(L, 0);
    lua_rawgeti(L, LUA_REGISTRYINDEX, *ref);

    if (ref == &call_ref) {
        udata = (LJFunctionData*) lua_newuserdata(L, sizeof(LJFunctionData));
        udata->fcinfo = fcinfo;
        udata->result = &result;
    } else if (ref == &inline_ref) {
        lua_pushstring(L, CODEBLOCK);
    } else if (ref == &validator_ref) {
        lua_pushnumber(L, PG_GETARG_OID(0));
    }

    PG_TRY();{
        status = lua_pcall(L, 1, 0, 0);

        if (status == LUA_ERRRUN) {
            if (lua_type(L, -1) == LUA_TSTRING){ 
                error_text = pstrdup(lua_tostring(L, -1));
                lua_pop(L, lua_gettop(L));
            }else {
                pllj_parse_error(L, &edata);
            }

        }
        else if (status == LUA_ERRMEM || status == LUA_ERRERR ) {
            error_text = pstrdup(lua_tostring(L, -1));
        }

        pop_vm(L);

    }PG_CATCH();{
        warning("TODO check vm is ok");
        pop_vm(L);
        if (ref != &validator_ref) {
            SPI_finish();
        }
        PG_RE_THROW();
    }PG_END_TRY();

    if (status == 0){

        if ((rc = SPI_finish()) != SPI_OK_FINISH) {
            elog(ERROR, "SPI_finish failed: %s", SPI_result_code_string(rc));
        }

        if (ref == &call_ref) {
            return result;
        }
        PG_RETURN_VOID();
    }

    if( status == LUA_ERRRUN) {
        if (error_text) {
            pg_throw_pllj_detail(error_text);
        }else{
            ereport(ERROR,
            (errcode(edata.sqlerrcode ? edata.sqlerrcode : ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
                errmsg_internal("%s", edata.message ? edata.message : "no exception data"),
                (edata.detail) ? errdetail_internal("%s", edata.detail) : 0,
                (edata.context) ? errcontext("%s", edata.context) : 0,
                (edata.hint) ? errhint("%s", edata.hint) : 0,
                (query) ? internalerrquery(query) : 0,
                (position) ? internalerrposition(position) : 0));
        }
    } else if (status == LUA_ERRMEM) {
        pg_throw("%s %s","Memory error:",error_text);
    } else if (status == LUA_ERRERR) {
        pg_throw("%s %s","Error:",error_text);
    }

    pg_throw("pllj unknown error");
}

static Datum lj_validator (FunctionCallInfo fcinfo) {
    return lj_call(fcinfo, &validator_ref);
}

static Datum lj_callhandler (FunctionCallInfo fcinfo) {
    return lj_call(fcinfo, &call_ref);
}

static Datum lj_inlinehandler (FunctionCallInfo fcinfo) {
    return lj_call(fcinfo, &inline_ref);
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
    AL[0] = get_vm();

    lua_getfield(AL[0], 1, "inlinehandler");
    inline_ref  = luaL_ref(AL[0], LUA_REGISTRYINDEX);
    lua_getfield(AL[0], 1, "callhandler");
    call_ref  = luaL_ref(AL[0], LUA_REGISTRYINDEX);
    lua_getfield(AL[0], 1, "validator");
    validator_ref  = luaL_ref(AL[0], LUA_REGISTRYINDEX);
    lua_settop(AL[0], 0);

    PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(_PG_fini);
Datum _PG_fini(PG_FUNCTION_ARGS) {
    for (int i = 0; i < SAVED_VM; ++i) {
        lua_close(AL[i]);
    }

    PG_RETURN_VOID();
}

PG_FUNCTION_INFO_V1(pllj_validator);
Datum pllj_validator(PG_FUNCTION_ARGS) {
    return lj_validator(fcinfo);
}

PG_FUNCTION_INFO_V1(pllj_call_handler);
Datum pllj_call_handler(PG_FUNCTION_ARGS) {
    return lj_callhandler(fcinfo);
}

PG_FUNCTION_INFO_V1(pllj_inline_handler);
Datum pllj_inline_handler(PG_FUNCTION_ARGS) {
    return lj_inlinehandler(fcinfo);
}

