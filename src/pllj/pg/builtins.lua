local ffi = require('ffi')

local C = ffi.C;

local macro = require('pllj.pg.macro')

local pg_type = require('pllj.pg.pg_type').pg_type

pg_type.text.tolua = function (datum) 
  local d = C.DirectFunctionCall1Coll(C.textout, 0, datum)
  return ffi.string(ffi.cast('Pointer', d))
end

pg_type.text.topg = function (v) 
  local length = #v
  local varsize = C.VARHDRSZ + length
  local out_ptr = C.SPI_palloc(varsize)
  macro.SET_VARSIZE(out_ptr, varsize)
  ffi.copy(ffi.cast('varattrib_4b *', out_ptr).va_4byte.va_data, v, length)
  --return ffi.string(ffi.cast('Pointer', d))
  return ffi.cast('Datum', out_ptr)
end

pg_type.int4.tolua = function (datum) 
  return tonumber(datum)
end

pg_type.int4.topg = function (v) 
  return ffi.cast('Datum',--[[SET_4_BYTES]](tonumber(v)))
end

pg_type.int2.tolua = function (datum) 
  return tonumber(macro.GET_2_BYTES(datum))
end

pg_type.int2.topg = function (v) 
  return ffi.cast('Datum', macro.GET_2_BYTES(tonumber(v)))
end

pg_type.int8.tolua = function (datum) 
  return tonumber(datum)
end

pg_type.int8.topg = function (v) 
  return ffi.cast('Datum', tonumber(v))
end

return pg_type