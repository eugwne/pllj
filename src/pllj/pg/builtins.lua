local ffi = require('ffi')

local C = ffi.C;

require('pllj.pg.fmgr')

ffi.cdef[[
Datum textout(FunctionCallInfo fcinfo);
]]

local function pg_text_tolua(datum) 
  local d = C.DirectFunctionCall1Coll(C.textout, 0, datum)
  return ffi.string(ffi.cast('Pointer', d))
end

local function pg_int_tolua(datum) 
  return tonumber(datum)
end

local function lua_int4pg(v) 
  return ffi.cast('Datum',--[[SET_4_BYTES]](tonumber(v)))
end

return {
  pg_text_tolua = pg_text_tolua, 
  pg_int_tolua = pg_int_tolua,

  lua_int4pg = lua_int4pg
}