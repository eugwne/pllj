local ffi = require('ffi')
local C = ffi.C

return { 

    oid = C.FLOAT8OID,

    to_lua = function(datum)
        return tonumber(C.ljm_DatumGetFloat8(datum))
    end,

    to_datum = function(lv)
        return C.ljm_Float8GetDatum(ffi.cast('float8',tonumber(lv)))
    end,

}