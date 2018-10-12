local ffi = require('ffi')
local C = ffi.C

return { 

    oid = C.VOIDOID,

    names = {'void'},

    to_lua = function(datum)
    end,

    to_datum = function()
        return ffi.cast('Datum', 0)
    end,

}