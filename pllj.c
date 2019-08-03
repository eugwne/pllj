#include <uthash.h> //HASH_FUNCTION macro conflict
#undef uthash_malloc
#undef uthash_free
#define uthash_malloc(sz) MemoryContextAlloc(TopMemoryContext, sz)
#define uthash_free(ptr,sz) pfree(ptr)

#include "postgres.h"
#include "executor/spi.h"
#include "commands/trigger.h"
#include "fmgr.h"
#include "access/heapam.h"
#include "utils/syscache.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_type.h"
#include "utils/memutils.h"
#include "utils/guc.h"

#include "access/htup_details.h"
#include "access/xact.h"
#include "funcapi.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <luajit.h>

#define out(...) ereport(INFO, (errmsg_internal(__VA_ARGS__)))
#define warning(...) ereport(WARNING, (errmsg_internal(__VA_ARGS__)))
#define pg_throw(...) ereport(ERROR, (errmsg_internal(__VA_ARGS__)))
#define pg_throw_pllj_detail(err) do{\
    ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION), \
    errmsg_internal("[pllj]: error"),\
    errdetail("%s", err)));\
    }while(0)

#define luapg_error(L)do{\
    if (lua_type(L, -1) == LUA_TSTRING){ \
    const char *err = pstrdup( lua_tostring((L), -1)); \
    lua_pop(L, lua_gettop(L));\
    ereport(ERROR, (errcode(ERRCODE_DATA_EXCEPTION), \
    errmsg_internal("[pllj]: error"),\
    errdetail("%s", err)));\
    }else {\
    luatable_report(L, ERROR);\
    }\
    }while(0)

#define CODEBLOCK \
    ((InlineCodeBlock *) DatumGetPointer(PG_GETARG_DATUM(0)))->source_text

static char *_on_init = NULL;
#ifdef PLLJ_UNTRUSTED
static char *_on_untrusted_init = NULL;
#else
static char *_on_trusted_init = NULL;
#endif


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
        ereport(FATAL, (errmsg_internal("Unhandled exception: %s", edata->message)));
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

static ErrorData  *last_edata = NULL;

static Datum e_heap_getattr(HeapTuple tuple, int16_t attnum, TupleDesc tupleDesc, bool *isnull){
    Datum value = heap_getattr(tuple, attnum, tupleDesc, isnull);
    return value;
}

static bool e_CALLED_AS_TRIGGER (void* fcinfo) {
    return CALLED_AS_TRIGGER((FunctionCallInfo)fcinfo);
}

static float4 e_DatumGetFloat4(Datum X){
    return DatumGetFloat4(X);
}

static Datum e_Float4GetDatum(float4 X) {
    return Float4GetDatum(X);
}

static float8 e_DatumGetFloat8(Datum X){
    return DatumGetFloat8(X);
}

static Datum e_Float8GetDatum(float8 X) {
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

static Datum e_InputFunctionCall(FmgrInfo *flinfo, char *str, Oid typioparam, int32 typmod){
    LJ_BEGIN_PG_TRY()
        return InputFunctionCall(flinfo, str, typioparam, typmod);
    LJ_END_PG_TRY()
    return 0;
}

static Datum e_FunctionCallInvoke(FunctionCallInfo fcinfo, bool* isok) {
    LJ_BEGIN_PG_TRY()
        return FunctionCallInvoke(fcinfo);
    LJ_END_PG_TRY( {*isok = false;})
    return 0;
}

static Datum e_SPIFunctionCallInvoke(FunctionCallInfo fcinfo, bool* isok) {
#if PG_VERSION_NUM < 100000
    Datum result;
    SPI_push();
    LJ_BEGIN_PG_TRY()
        result = FunctionCallInvoke(fcinfo);
        SPI_pop();
        return result;
    LJ_END_PG_TRY( {SPI_pop();*isok = false;})
    return 0;
#else
    return e_FunctionCallInvoke(fcinfo, isok);
#endif
}

static int e_SPI_execute(const char *src, bool read_only, long tcount) {
    int result = 0;
    LJ_BEGIN_PG_TRY()
        result = SPI_execute(src, read_only, tcount);
    LJ_END_PG_TRY( {SPI_restore_connection();})

    return result;
}

static int e_SPI_execute_plan(SPIPlanPtr plan, Datum * values, const char * nulls,
                     bool read_only, long count) {
    int result = 0;
    LJ_BEGIN_PG_TRY()
        result = SPI_execute_plan(plan, values, nulls, read_only, count);
    LJ_END_PG_TRY( {SPI_restore_connection();})
    return result;
}

static SPIPlanPtr e_SPI_prepare_cursor(const char *src, int nargs, Oid *argtypes, int cursorOptions){
    LJ_BEGIN_PG_TRY()
        return SPI_prepare_cursor(src, nargs, argtypes, cursorOptions);
    LJ_END_PG_TRY()
    return 0;
}

static Portal
e_SPI_cursor_open_with_args(const char *name,
                            const char *src,
                            int nargs, Oid *argtypes,
                            Datum *Values, const char *Nulls,
                            bool read_only, int cursorOptions)
{
    LJ_BEGIN_PG_TRY()
        return SPI_cursor_open_with_args(name, src, nargs, argtypes, Values, Nulls, read_only, cursorOptions);
    LJ_END_PG_TRY()
    return 0;
}

static ArrayType *
e_construct_md_array(Datum *elems,
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


static FuncCallContext *e_SRF_FIRSTCALL_INIT(FunctionCallInfo fcinfo)
{
    LJ_BEGIN_PG_TRY()
        return SRF_FIRSTCALL_INIT();
    LJ_END_PG_TRY()
    return 0;
}

static FuncCallContext *e_SRF_PERCALL_SETUP(FunctionCallInfo fcinfo)
{
    return SRF_PERCALL_SETUP();
}

static Datum e_SRF_RETURN_DONE(FunctionCallInfo fcinfo, FuncCallContext *funcctx)
{
    SRF_RETURN_DONE(funcctx);
}

static Datum e_SRF_RETURN_NEXT(FunctionCallInfo fcinfo, FuncCallContext *funcctx)
{
    SRF_RETURN_NEXT(funcctx, 0);
}

static void e_ItemPointerSetInvalid(ItemPointerData* pointer)
{
    ItemPointerSetInvalid(pointer);
}

static void e_SPI_scroll_cursor_fetch(Portal portal, FetchDirection direction, long count)
{

    LJ_BEGIN_PG_TRY()
       SPI_scroll_cursor_fetch(portal, direction, count);
    LJ_END_PG_TRY( {SPI_restore_connection();})
}

static void e_SPI_scroll_cursor_move(Portal portal, FetchDirection direction, long count)
{

    LJ_BEGIN_PG_TRY()
       SPI_scroll_cursor_move(portal, direction, count);
    LJ_END_PG_TRY( {SPI_restore_connection();})
}

static Portal e_SPI_cursor_open(const char *name, SPIPlanPtr plan, Datum *Values, const char *Nulls, bool read_only)
{
    LJ_BEGIN_PG_TRY()
       return SPI_cursor_open(name, plan, Values, Nulls, read_only);
    LJ_END_PG_TRY( {SPI_restore_connection();})
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

typedef struct shared_data_struct_t {
    const char *key;
    void* value;
    UT_hash_handle hh; /* makes this structure hashable */
} shared_data_struct_t;

static shared_data_struct_t *shared_plan = NULL;
static shared_data_struct_t *shared_portal = NULL;

#define __UTHASH_add(htable, key, value) \
do { \
    shared_data_struct_t *s, *tmp; \
    HASH_FIND_STR(htable, key, tmp); \
    if (tmp) return false; \
    s = (shared_data_struct_t *)MemoryContextAlloc(TopMemoryContext, sizeof(shared_data_struct_t)); \
    s->key = MemoryContextStrdup(TopMemoryContext, key); \
    s->value = value; \
    HASH_ADD_KEYPTR(hh, htable, s->key, strlen(s->key), s); \
    return true; \
} while (0)

#define __UTHASH_find(htable, key) \
do { \
    shared_data_struct_t *s; \
    HASH_FIND_STR(htable, key, s); \
    if (!s) return NULL; \
    return s->value; \
} while (0)

//caller should free value
#define  __UTHASH_remove(htable, key) \
do { \
    shared_data_struct_t *entry = NULL; \
    void* value = NULL; \
    HASH_FIND_STR(htable, key, entry); \
    if (!entry) return NULL; \
    HASH_DELETE(hh, htable, entry); \
    pfree((void*)entry->key); \
    value = entry->value; \
    pfree((void*)entry); \
    return value; \
} while (0) 

static int call_ref = 0;
static int inline_ref = 0;
static int validator_ref = 0;
static volatile int call_depth = 0;

static bool uthash_add(const char* key, void* value)
{
    __UTHASH_add(shared_plan, key, value);
}

static void* uthash_find(const char* key)
{
    __UTHASH_find(shared_plan, key);
}

static void* uthash_remove(const char* key)
{
    __UTHASH_remove(shared_plan, key);
}


static bool uthash_portal_add(const char* key, void* value)
{
    __UTHASH_add(shared_portal, key, value);
}

static void* uthash_portal_find(const char* key)
{
    __UTHASH_find(shared_portal, key);
}

static void* uthash_portal_remove(const char* key)
{
    __UTHASH_remove(shared_portal, key);
}


static unsigned uthash_count(void)
{
    return HASH_COUNT(shared_plan);
}

static void uthash_iter(void (*cb_key) (const char *name))
{
    shared_data_struct_t *s, *tmp;
    HASH_ITER(hh, shared_plan, s, tmp) {
        cb_key(s->key);
    }
}

static struct {
  const char *name;
  void *ptr;
  const char *tname;
} exp_data[] = {
    {"SPI_cursor_open_with_args", e_SPI_cursor_open_with_args, "Portal (*)(const char *, const char *, int, Oid *, Datum *, const char *, bool, int)"},
    {"SPI_cursor_open", e_SPI_cursor_open, "Portal(*)(const char *, SPIPlanPtr, Datum *, const char *, bool)"},
    {"SPI_scroll_cursor_move", e_SPI_scroll_cursor_move, "void(*) (Portal, enum FetchDirection, long)"},
    {"SPI_scroll_cursor_fetch", e_SPI_scroll_cursor_fetch, "void(*) (Portal, enum FetchDirection, long)"},
    {"ItemPointerSetInvalid", e_ItemPointerSetInvalid, "void(*) (ItemPointerData*)"},

    {"uthash_add", uthash_add, "bool (*) (const char*, void*)"},
    {"uthash_find", uthash_find, "void* (*) (const char*)"},
    {"uthash_remove", uthash_remove, "void* (*) (const char*)"},
    {"uthash_iter", uthash_iter, "void (*)(void (*cb_key) (const char *))"},
    {"uthash_count", uthash_count, "unsigned (*) ()"},
    
    {"uthash_portal_add", uthash_portal_add, "bool (*) (const char*, void*)"},
    {"uthash_portal_find", uthash_portal_find, "void* (*) (const char*)"},
    {"uthash_portal_remove", uthash_portal_remove, "void* (*) (const char*)"},

    {"SRF_FIRSTCALL_INIT", e_SRF_FIRSTCALL_INIT, "FuncCallContext* (*) (FunctionCallInfo)"},
    {"SRF_PERCALL_SETUP", e_SRF_PERCALL_SETUP, "FuncCallContext* (*) (FunctionCallInfo)"},
    {"SRF_RETURN_DONE", e_SRF_RETURN_DONE, "Datum (*) (FunctionCallInfo, FuncCallContext*)"},
    {"SRF_RETURN_NEXT", e_SRF_RETURN_NEXT, "Datum (*) (FunctionCallInfo, FuncCallContext*)"},

    {"CALLED_AS_TRIGGER", e_CALLED_AS_TRIGGER, "bool (*) (void*)"},
    {"DatumGetFloat4", e_DatumGetFloat4, "float4 (*) (Datum)"},
    {"Float4GetDatum", e_Float4GetDatum, "Datum (*) (float4)"},
    {"DatumGetFloat8", e_DatumGetFloat8, "float8 (*) (Datum)"},
    {"Float8GetDatum", e_Float8GetDatum, "Datum (*) (float8)"},
    {"construct_md_array", e_construct_md_array, "ArrayType* (*) (Datum *, bool *, int, int *, int *, Oid , int , bool , char )"},
    {"InputFunctionCall", e_InputFunctionCall, "Datum (*) (FmgrInfo *, char *, Oid, int32)"},

    {"heap_getattr", e_heap_getattr, "Datum (*) (HeapTuple, int16_t, TupleDesc, bool *)"},
    {"FunctionCallInvoke", e_SPIFunctionCallInvoke, "Datum (*) (FunctionCallInfo, bool*)"},
    {"SPI_prepare_cursor", e_SPI_prepare_cursor, "SPIPlanPtr (*) (const char *, int, Oid *, int)"},
    {"SPI_execute_plan", e_SPI_execute_plan, "int (*) (SPIPlanPtr, Datum *, const char *, bool, long)"},

    {"SPI_execute", e_SPI_execute, "int (*) (const char *, bool, long)"},

    {"last_e", &last_edata, "struct {ErrorData* data;}*"},
    {"_on_init", &_on_init, "s_char_data_ptr"},

#ifdef PLLJ_UNTRUSTED
    {"_on_untrusted_init", &_on_untrusted_init, "s_char_data_ptr"},
#else
    {"_on_trusted_init", &_on_trusted_init, "s_char_data_ptr"},
#endif

    {NULL, NULL}
};


#define MAX(a,b) (((a)>(b))?(a):(b))
static lua_State * get_vm() {
    int status;
    void** udata;
    lua_State *L = lua_open();

#ifndef PLLJ_SKIP_LJVER_CHECK
    LUAJIT_VERSION_SYM();
#endif
    lua_gc(L, LUA_GCSTOP, 0);
    luaL_openlibs(L);
    
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    luaL_setfuncs(L, luaP_funcs, 0);
#ifdef PLLJ_UNTRUSTED
    lua_pushboolean(L, 1);
#else
    lua_pushboolean(L, 0);
#endif
    lua_setglobal(L, "__untrusted__");
    udata = (void**) lua_newuserdata(L, sizeof(void*));
    *udata = exp_data;
    lua_setglobal(L, "__exp__");

    lua_pushinteger(L, MAX(0, call_depth-1));
    lua_setglobal(L, "__depth__");

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
#ifdef PLLJ_UNTRUSTED
    lua_getfield(L, 1, "inlinehandler_u");
    luaL_ref(L, LUA_REGISTRYINDEX);
    lua_getfield(L, 1, "callhandler_u");
    luaL_ref(L, LUA_REGISTRYINDEX);
    lua_getfield(L, 1, "validator_u");
    luaL_ref(L, LUA_REGISTRYINDEX);
#else
    lua_getfield(L, 1, "inlinehandler");
    luaL_ref(L, LUA_REGISTRYINDEX);
    lua_getfield(L, 1, "callhandler");
    luaL_ref(L, LUA_REGISTRYINDEX);
    lua_getfield(L, 1, "validator");
    luaL_ref(L, LUA_REGISTRYINDEX);
#endif
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

PGDLLEXPORT Datum _PG_init(PG_FUNCTION_ARGS);
PGDLLEXPORT Datum _PG_fini(PG_FUNCTION_ARGS);
#ifdef PLLJ_UNTRUSTED
PGDLLEXPORT Datum pllj_validator_u(PG_FUNCTION_ARGS);
PGDLLEXPORT Datum pllj_call_handler_u(PG_FUNCTION_ARGS);
PGDLLEXPORT Datum pllj_inline_handler_u(PG_FUNCTION_ARGS);
#else
PGDLLEXPORT Datum pllj_validator(PG_FUNCTION_ARGS);
PGDLLEXPORT Datum pllj_call_handler(PG_FUNCTION_ARGS);
PGDLLEXPORT Datum pllj_inline_handler(PG_FUNCTION_ARGS);
#endif

PG_FUNCTION_INFO_V1(_PG_init);
Datum _PG_init(PG_FUNCTION_ARGS) {
    DefineCustomStringVariable("pllj.on_init_all", "pllj/pllju preinitialization code", NULL, &_on_init, NULL, PGC_SIGHUP, 0, NULL, NULL, NULL);
#ifdef PLLJ_UNTRUSTED
    DefineCustomStringVariable("pllju.on_init", "pllju preinitialization code", NULL, &_on_untrusted_init, NULL, PGC_SUSET, 0, NULL, NULL, NULL);
#else
    DefineCustomStringVariable("pllj.on_init", "pllj preinitialization code", NULL, &_on_trusted_init, NULL, PGC_SUSET, 0, NULL, NULL, NULL);
#endif

    AL[0] = get_vm();
#ifdef PLLJ_UNTRUSTED
    lua_getfield(AL[0], 1, "inlinehandler_u");
    inline_ref  = luaL_ref(AL[0], LUA_REGISTRYINDEX);
    lua_getfield(AL[0], 1, "callhandler_u");
    call_ref  = luaL_ref(AL[0], LUA_REGISTRYINDEX);
    lua_getfield(AL[0], 1, "validator_u");
    validator_ref  = luaL_ref(AL[0], LUA_REGISTRYINDEX);
#else    
    lua_getfield(AL[0], 1, "inlinehandler");
    inline_ref  = luaL_ref(AL[0], LUA_REGISTRYINDEX);
    lua_getfield(AL[0], 1, "callhandler");
    call_ref  = luaL_ref(AL[0], LUA_REGISTRYINDEX);
    lua_getfield(AL[0], 1, "validator");
    validator_ref  = luaL_ref(AL[0], LUA_REGISTRYINDEX);
#endif
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

#ifdef PLLJ_UNTRUSTED
PG_FUNCTION_INFO_V1(pllj_validator_u);
Datum pllj_validator_u(PG_FUNCTION_ARGS) {
    return lj_validator(fcinfo);
}

PG_FUNCTION_INFO_V1(pllj_call_handler_u);
Datum pllj_call_handler_u(PG_FUNCTION_ARGS) {
    return lj_callhandler(fcinfo);
}

PG_FUNCTION_INFO_V1(pllj_inline_handler_u);
Datum pllj_inline_handler_u(PG_FUNCTION_ARGS) {
    return lj_inlinehandler(fcinfo);
}
#else
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
#endif
