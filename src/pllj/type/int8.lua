local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')

return { 

    oid = C.INT8OID,

    names = {'bigint', 'int8'},

    to_lua = function(datum)
        return ffi.cast('int64_t', datum)
    end,

    to_datum = function(lv)
        if type(lv) == "cdata" and ffi.istype('int64_t', lv) then
            return ffi.cast('Datum', lv)
        end
    
        return ffi.cast('Datum', tonumber(lv))
    end,

}