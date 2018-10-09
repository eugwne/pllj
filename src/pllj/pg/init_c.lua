local ffi = require('ffi')
local C = ffi.C
local all_types = require('pllj.pg.i').all_types
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
Datum lj_FunctionCallInvoke(FunctionCallInfoData* fcinfo, bool* isok);
SPIPlanPtr lj_SPI_prepare_cursor(const char *src, int nargs, Oid *argtypes, int cursorOptions);
int lj_SPI_execute_plan(SPIPlanPtr plan, Datum * values, const char * nulls, bool read_only, long count);

bool lj_CALLED_AS_TRIGGER (void* fcinfo);
Oid lj_HeapTupleGetOid(HeapTuple pht);

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
