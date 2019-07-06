local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')

return { 

    oid = C.INT8OID,

    to_lua = function(datum)
        return ffi.cast('int64_t', datum)
    end,

    to_datum = function(lv)
        if (lv == NULL) then
            return ffi.cast('Datum', 0), true
        end

        if type(lv) == "cdata" and ffi.istype('int64_t', lv) then
            return ffi.cast('Datum', lv), false
        end
        
        return ffi.cast('Datum', tonumber(lv)), false
    end,

}
