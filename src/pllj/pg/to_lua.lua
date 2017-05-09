local ffi = require('ffi')
local C = ffi.C
require('pllj.pg.init_c')
local macro = require('pllj.pg.macro')

local typeto = {}


typeto[C.TEXTOID] = function (datum)
    local d = C.DirectFunctionCall1Coll(C.textout, 0, datum)
    return ffi.string(ffi.cast('Pointer', d))
end


typeto[C.INT4OID] = function (datum)
    return tonumber(datum)
end

typeto[C.INT2OID] = function (datum)
    return tonumber(macro.GET_2_BYTES(datum))
end

typeto[C.INT8OID] = function (datum)
    return ffi.cast('int64_t', datum)
end

typeto[C.VOIDOID] = function ()
end


return {typeto = typeto}
