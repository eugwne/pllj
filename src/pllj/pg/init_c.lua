local ffi = require('ffi')
local C = ffi.C

ffi.cdef[[
const char *
GetConfigOption(const char *name, bool missing_ok, bool restrict_privileged)
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

bool uthash_add(const char* key, void* value);
void* uthash_find(const char* key);
void* uthash_remove(const char* key);
void uthash_iter(void (*cb_key) (const char *name));
unsigned uthash_count(void);

]]

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


print = function(text)
    C.errstart(C.INFO, "", 0, nil, nil)
    C.errfinish(C.errmsg(tostring(text)))
end
