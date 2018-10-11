local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')

return { 

    oid = C.INT2OID,

    names = {'smallint', 'int2'},

    to_lua = function(datum)
        return tonumber(macro.GET_2_BYTES(datum))
    end,

    to_datum = function(lv)
        return ffi.cast('Datum', macro.GET_2_BYTES(tonumber(lv)))
    end,

}