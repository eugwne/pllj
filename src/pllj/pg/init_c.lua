local ffi = require('ffi')
local C = ffi.C

local table_new = require('table.new')

ffi.cdef[[
const char *
GetConfigOption(const char *name, bool missing_ok, bool restrict_privileged);
struct PortalData;
]]
local api_version = ffi.string(C.GetConfigOption('server_version_num', true, false))


local all_types = (require('pllj.pg.api_'..api_version) or require('pllj.pg.i')).all_types
ffi.cdef(all_types)

ffi.cdef[[
typedef  struct null_s{} null_s;

typedef struct LJFunctionData {
    void* fcinfo;
    Datum* result;
} LJFunctionData;

int lj_SPI_execute(const char *src, bool read_only, long tcount);
int call_depth;
Datum pllj_heap_getattr(HeapTuple tuple, int16_t attnum, TupleDesc tupleDesc, bool *isnull);
Datum lj_FunctionCallInvoke(FunctionCallInfo fcinfo, bool* isok);
Datum ljm_SPIFunctionCallInvoke(FunctionCallInfo fcinfo, bool* isok);
SPIPlanPtr lj_SPI_prepare_cursor(const char *src, int nargs, Oid *argtypes, int cursorOptions);
int lj_SPI_execute_plan(SPIPlanPtr plan, Datum * values, const char * nulls, bool read_only, long count);

bool ljm_CALLED_AS_TRIGGER (void* fcinfo);
float4 ljm_DatumGetFloat4(Datum X);
Datum ljm_Float4GetDatum(float4 X);

float8 ljm_DatumGetFloat8(Datum X);
Datum ljm_Float8GetDatum(float8 X);

ArrayType *
lj_construct_md_array(Datum *elems,
                    bool *nulls,
                    int ndims,
                    int *dims,
                    int *lbs,
                    Oid elmtype, int elmlen, bool elmbyval, char elmalign);

Datum lj_InputFunctionCall(FmgrInfo *flinfo, char *str, Oid typioparam, int32 typmod);

FuncCallContext *ljm_SRF_FIRSTCALL_INIT(FunctionCallInfo fcinfo);
FuncCallContext *ljm_SRF_PERCALL_SETUP(FunctionCallInfo fcinfo);
Datum ljm_SRF_RETURN_DONE(FunctionCallInfo fcinfo, FuncCallContext *funcctx);
Datum ljm_SRF_RETURN_NEXT(FunctionCallInfo fcinfo, FuncCallContext *funcctx);

bool uthash_add(const char* key, void* value);
void* uthash_find(const char* key);
void* uthash_remove(const char* key);
void uthash_iter(void (*cb_key) (const char *name));
unsigned uthash_count(void);

bool uthash_portal_add(const char* key, void* value);
void* uthash_portal_find(const char* key);
void* uthash_portal_remove(const char* key);

typedef struct{
    ExprContext econtext;
    ReturnSetInfo rsinfo;
} pgfunc_srf;

void ljm_ItemPointerSetInvalid(ItemPointerData* pointer);

Portal
ljm_SPI_cursor_open_with_args(const char *name,
                            const char *src,
                            int nargs, Oid *argtypes,
                            Datum *Values, const char *Nulls,
                            bool read_only, int cursorOptions);

void ljm_SPI_scroll_cursor_fetch(Portal portal, enum FetchDirection direction, long count);
void ljm_SPI_scroll_cursor_move(Portal portal, enum FetchDirection direction, long count);
Portal ljm_SPI_cursor_open(const char *name, SPIPlanPtr plan, Datum *Values, const char *Nulls, bool read_only);
]]

local function __top_alloc(size)
    return C.MemoryContextAlloc(C.TopMemoryContext, size)
end


local null_t, NULL, nullptr
local null_mt = {
  __tostring = function() return 'NULL' end,
   __eq = function( left, right ) 
            local t = type(left)
            if not (t == 'nil' or t == 'cdata') then 
                return false 
            end

            if ffi.cast('void*', left) == nullptr then
                left = right
            end
            t = type(left)
            if not (t == 'nil' or t == 'cdata') then 
                return false 
            end
            local ptr = ffi.cast('void*', left)

            return ((ptr == nil) or (ptr == nullptr))
        end
}
null_t = ffi.metatype("null_s", null_mt)
NULL = null_t()
nullptr = ffi.cast('void*', NULL)

--NULL = ffi.new("void*")
ffi.NULL = NULL

local function __report(elevel, data)
    local elevel = math.min(elevel, C.WARNING)
    local message 
    local sqlerrcode
    local detail
    local hint
    local query
    local position
    local schema_name
    local table_name
    local column_name
    local datatype_name
    local constraint_name
    
    local t = type(data)
    if t == "table" then
        message = data.message and tostring(data.message) or ""
        sqlerrcode = tonumber(data.sqlerrcode)
        detail = data.detail
        hint = data.hint
        query = data.query
        position = tonumber(data.position)
        schema_name = data.schema_name
        table_name = data.table_name
        column_name = data.column_name
        datatype_name = data.datatype_name
        constraint_name = data.constraint_name
    elseif type(data) == "string" then
        message = data
    else
        message = data and tostring(data) or ""
    end 

    C.errstart(elevel, "", 0, nil, nil)
    C.errfinish(C.errcode(sqlerrcode and sqlerrcode or C.ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
        C.errmsg_internal(message),
        detail and C.errdetail_internal(tostring(detail)) or 0,
        --TODO context
        hint and  C.errhint(tostring(hint)) or 0,
        query and C.internalerrquery(tostring(query)) or 0,
        position and C.internalerrposition(position) or 0,
        schema_name and C.err_generic_string(string.byte('s'), tostring(schema_name)) or 0,--PG_DIAG_SCHEMA_NAME,
        table_name and C.err_generic_string(string.byte('t'), tostring(table_name)) or 0,--PG_DIAG_TABLE_NAME,
        column_name and C.err_generic_string(string.byte('c'), tostring(column_name)) or 0,--PG_DIAG_COLUMN_NAME,
        datatype_name and C.err_generic_string(string.byte('d'), tostring(datatype_name)) or 0,--PG_DIAG_DATATYPE_NAME,
        constraint_name and C.err_generic_string(string.byte('n'), tostring(constraint_name)) or 0--PG_DIAG_CONSTRAINT_NAME,
    )
end 

local function __log(data)
    __report(C.LOG, data)
end

local function __info(data)
    __report(C.INFO, data)
end

local function __notice(data)
    __report(C.NOTICE, data)
end

local function __warning(data)
    __report(C.WARNING, data)
end

local __pg_print
__pg_print = function(...)
    local args = {...}
    local argc = #args

    if argc < 2 then
        local text = args[1]
        C.errstart(C.INFO, "", 0, nil, nil)
        C.errfinish(C.errmsg_internal(tostring(text)))
        return __pg_print
    end
    local tmp = table_new(argc * 2, 0)
    table.insert(tmp, tostring(args[1]))
    for k = 2, argc  do
        table.insert(tmp, ' ')
        table.insert(tmp, tostring(args[k]))
    end
    local output = table.concat(tmp)
    C.errstart(C.INFO, "", 0, nil, nil)
    C.errfinish(C.errmsg_internal(tostring(output)))
    return __pg_print
end

top_alloc = __top_alloc
print = __pg_print
info = __info
log = __log
notice = __notice
warning = __warning
