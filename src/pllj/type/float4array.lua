local ffi = require('ffi')
local C = ffi.C

local to_lua_T = require('pllj.type.array[T]').to_lua_T
local to_datum_T = require('pllj.type.array[T]').to_datum_T

local float4_t = require('pllj.type.float4')

return {
    oid = C.FLOAT4ARRAYOID,

    to_lua = to_lua_T(float4_t),
    to_datum = to_datum_T(float4_t),

}