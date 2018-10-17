local ffi = require('ffi')
local C = ffi.C

return { 

    oid = C.FLOAT4OID,

    to_lua = function(datum)
        return tonumber(C.ljm_DatumGetFloat4(datum))
    end,

    to_datum = function(lv)
        return C.ljm_Float4GetDatum(ffi.cast('float4',tonumber(lv)))
    end,

}