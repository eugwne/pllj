local ffi = require('ffi')
local C = ffi.C
require('pllj.pg.init_c')
local macro = require('pllj.pg.macro')
local N = tonumber

local datumfor = {}

datumfor[N(C.TEXTOID)] = function (v)
    local length = #v
    local varsize = C.VARHDRSZ + length
    local out_ptr = C.SPI_palloc(varsize)
    macro.SET_VARSIZE(out_ptr, varsize)
    ffi.copy(ffi.cast('varattrib_4b *', out_ptr).va_4byte.va_data, v, length)
    --return ffi.string(ffi.cast('Pointer', d))
    return ffi.cast('Datum', out_ptr)
end


datumfor[N(C.INT4OID)] = function (v)
    return ffi.cast('Datum',--[[SET_4_BYTES]](tonumber(v)))
end

datumfor[N(C.INT2OID)] = function (v)
    return ffi.cast('Datum', macro.GET_2_BYTES(tonumber(v)))
end

datumfor[N(C.INT8OID)] = function (v)
    if type(v) == "cdata" and ffi.istype('int64_t', v) then
        return ffi.cast('Datum', v)
    end

    return ffi.cast('Datum', tonumber(v))
end

datumfor[N(C.VOIDOID)] = function ()
    return ffi.cast('Datum', 0)
end

return {datumfor=datumfor}

