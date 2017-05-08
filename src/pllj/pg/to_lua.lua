local ffi = require('ffi')
local C = ffi.C
require('pllj.pg.init_c')
local macro = require('pllj.pg.macro')
local N = tonumber

local typeto = {}


typeto[N(C.TEXTOID)] = function (datum)
    local d = C.DirectFunctionCall1Coll(C.textout, 0, datum)
    return ffi.string(ffi.cast('Pointer', d))
end


typeto[N(C.INT4OID)] = function (datum)
    return tonumber(datum)
end

typeto[N(C.INT2OID)] = function (datum)
    return tonumber(macro.GET_2_BYTES(datum))
end

typeto[N(C.INT8OID)] = function (datum)
    return ffi.cast('int64_t', datum)
end

typeto[N(C.VOIDOID)] = function ()
end


return {typeto = typeto}
