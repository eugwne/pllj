local ffi = require('ffi')
local C = ffi.C

--local INPUT, OUTPUT = get_io_func(C.INT2ARRAYOID)

local to_lua_T = require('pllj.type.array[T]').to_lua_T
local to_datum_T = require('pllj.type.array[T]').to_datum_T

local int2_t = require('pllj.type.int2')

return {
    oid = C.INT2ARRAYOID,
    names = {'integer[]','int4[]','int[]'},

    to_lua = to_lua_T(int2_t),
    to_datum = to_datum_T(int2_t),

}
