local ffi = require('ffi')

local NULL = ffi.new("void*")

ffi.cdef[[
int lj_SPI_execute(const char *src, bool read_only, long tcount);
int call_depth;
Datum pllj_heap_getattr(HeapTuple tuple, int16_t attnum, TupleDesc tupleDesc, bool *isnull);
]]

return {NULL = NULL}