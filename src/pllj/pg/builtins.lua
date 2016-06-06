local ffi = require('ffi')

require('pllj.pg.fmgr')

ffi.cdef[[
Datum textout(FunctionCallInfo fcinfo);
]]

local function pg_text_tolua(datum) 
    local d = ffi.C.DirectFunctionCall1Coll(ffi.C.textout, 0, datum)
    return ffi.string(ffi.cast('Pointer', d))
  end

return {pg_text_tolua = pg_text_tolua}