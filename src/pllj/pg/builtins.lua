local ffi = require('ffi')

require('pllj.pg.fmgr')

ffi.cdef[[
Datum textout(FunctionCallInfo fcinfo);
]]

return {}