local ffi = require('ffi')
local C = ffi.C

local get_io_func = require("pllj.pg.misc").get_io_func

local INPUT, OUTPUT = get_io_func(C.TEXTARRAYOID)

local to_lua_T = require('pllj.type.array[T]').to_lua_T
local to_datum_T = require('pllj.type.array[T]').to_datum_T

local text_t = require('pllj.type.text')

local to_datum = to_datum_T(text_t)

return {
    oid = C.TEXTARRAYOID,
    names = {'text[]'},

    to_lua = to_lua_T(text_t),
    to_datum = function(lv)
        if type(lv) == "string" then
            return INPUT(lv)
        end
        return to_datum(lv)
    end,

}
