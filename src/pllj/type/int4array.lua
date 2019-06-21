local ffi = require('ffi')
local C = ffi.C

--local INPUT, OUTPUT = get_io_func(C.INT4ARRAYOID)

local to_lua_T = require('pllj.type.array[T]').to_lua_T
local to_datum_T = require('pllj.type.array[T]').to_datum_T

local int4_t = require('pllj.type.int4')

return {

    oid = C.INT4ARRAYOID,

    to_lua = to_lua_T(int4_t),
    
    to_datum = to_datum_T(int4_t),

}
