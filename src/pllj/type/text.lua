local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')

local call_pg_variadic = require('pllj.pg.func').call_pg_variadic

return { 

    oid = C.TEXTOID,

    names = {'text'},

    to_lua = function(datum)
        local d = call_pg_variadic(C.textout, {datum})
        return ffi.string(ffi.cast('Pointer', d))
    end,

    to_datum = function(lv, p_isnull)
        if lv == nil or lv == NULL then
            if (p_isnull ~=nil) then
                p_isnull[0] = true
            end
    
            return ffi.cast('Datum', 0)
        end
        local length = #lv
        local varsize = C.VARHDRSZ + length
        local out_ptr = C.SPI_palloc(varsize)
        macro.SET_VARSIZE(out_ptr, varsize)
        ffi.copy(ffi.cast('varattrib_4b *', out_ptr).va_4byte.va_data, lv, length)
        --return ffi.string(ffi.cast('Pointer', d))
        return ffi.cast('Datum', out_ptr)
    end,

}