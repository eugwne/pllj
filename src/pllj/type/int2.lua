local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')

return { 

    oid = C.INT2OID,

    to_lua = function(datum)
        return tonumber(macro.GET_2_BYTES(datum))
    end,

    to_datum = function(lv)
        if (lv == NULL) then
            return ffi.cast('Datum', 0), true
        end
        return ffi.cast('Datum', macro.GET_2_BYTES(tonumber(lv))), false
    end,

}
