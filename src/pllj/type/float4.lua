local ffi = require('ffi')
local C = ffi.C

return { 

    oid = C.FLOAT4OID,

    to_lua = function(datum)
        return tonumber(imported.DatumGetFloat4(datum))
    end,

    to_datum = function(lv)
        if (lv == NULL) then
            return ffi.cast('Datum', 0), true
        end
        return imported.Float4GetDatum(ffi.cast('float4',tonumber(lv)))
    end,

}
