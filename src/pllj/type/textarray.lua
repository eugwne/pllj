local ffi = require('ffi')
local C = ffi.C

local get_io_func = require("pllj.pg.misc").get_io_func

local INPUT, OUTPUT = get_io_func(C.TEXTARRAYOID)

local to_lua_T = require('pllj.type.array[T]').to_lua_T
local to_datum_T = require('pllj.type.array[T]').to_datum_T

local text_t = require('pllj.type.text')

local to_datum = to_datum_T(text_t)

--text[]
return {

    oid = C.TEXTARRAYOID,

    to_lua = to_lua_T(text_t),

    to_datum = function(lv)
        if lv == NULL then
            return ffi.cast('Datum', 0), true
        end
        if type(lv) == "string" then
            return INPUT(lv), false
        end
        return to_datum(lv)
    end,

}
