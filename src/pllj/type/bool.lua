local ffi = require('ffi')
local C = ffi.C

return { 

    oid = C.BOOLOID,

    to_lua = function(datum)
        return datum ~= 0
    end,

    to_datum = function(lv)
        return ffi.cast('Datum', lv and 1 or 0)
    end,

}
