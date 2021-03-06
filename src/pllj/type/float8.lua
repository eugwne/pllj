local ffi = require('ffi')
local C = ffi.C

return { 

    oid = C.FLOAT8OID,

    to_lua = function(datum)
        return tonumber(imported.DatumGetFloat8(datum))
    end,

    to_datum = function(lv)
        if (lv == NULL) then
            return ffi.cast('Datum', 0), true
        end
        return imported.Float8GetDatum(ffi.cast('float8',tonumber(lv))), false
    end,

}
