local ffi = require('ffi')
local all_types = require('pllj.pg.i').all_types
ffi.cdef(all_types)

local NULL = ffi.new("void*")

ffi.NULL = NULL

ffi.cdef[[
int lj_SPI_execute(const char *src, bool read_only, long tcount);
int call_depth;
Datum pllj_heap_getattr(HeapTuple tuple, int16_t attnum, TupleDesc tupleDesc, bool *isnull);
Datum lj_FunctionCallInvoke(FunctionCallInfoData* fcinfo, bool* isok);
SPIPlanPtr lj_SPI_prepare_cursor(const char *src, int nargs, Oid *argtypes, int cursorOptions);
int lj_SPI_execute_plan(SPIPlanPtr plan, Datum * values, const char * nulls, bool read_only, long count);
]]