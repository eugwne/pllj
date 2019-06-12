local ffi = require('ffi')
local C = ffi.C

local int8arrayoid = 1016 

local to_lua_T = require('pllj.type.array[T]').to_lua_T
local to_datum_T = require('pllj.type.array[T]').to_datum_T

local int8_t = require('pllj.type.int8')

--'bigint[]','int8[]'
return {

    oid = int8arrayoid,

    to_lua = to_lua_T(int8_t),
    
    to_datum = to_datum_T(int8_t),

}
