local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')

return { 

    oid = C.INT4OID,

    names = {'integer', 'int4', 'int'},

    to_lua = function(datum)
        return tonumber(macro.GET_4_BYTES(datum))
    end,

    to_datum = function(lv)
        return ffi.cast('Datum', macro.SET_4_BYTES(tonumber(lv)))
    end,

}