local ffi = require('ffi')
local C = ffi.C

local band = require("bit").band
local lshift = require("bit").lshift


local function GETSTRUCT(TUP)
  local addr = ffi.cast("intptr_t", (TUP).t_data)
  return ffi.cast('char*',addr+(TUP.t_data.t_hoff))
end

local function PG_DETOAST_DATUM(datum)
  return C.pg_detoast_datum(ffi.cast('struct varlena*', ffi.cast('Pointer', datum)))
end

local function SET_4_BYTES(X)
  --(((Datum) (value)) & 0xffffffff)
  return (band(ffi.cast('Datum', X), 0xffffffff))
end

local function GET_2_BYTES(X)
  --(((Datum) (value)) & 0x0000ffff)
  return (band(ffi.cast('Datum', X), 0x0000ffff))
end

local function GET_4_BYTES(X)
    --(((Datum) (value)) & 0x0000ffff)
    return (band(ffi.cast('Datum', X), 0xffffffff))
end

local function DatumGetObjectId(X)
    return ffi.cast('Oid', GET_4_BYTES(X))
end


local function ObjectIdGetDatum(X)
  return ffi.cast('Datum', SET_4_BYTES(X))
end

local function HeapTupleHeaderXminFrozen(tup)
  --((tup)->t_infomask & (HEAP_XMIN_FROZEN)) == HEAP_XMIN_FROZEN 
  return (band(tup.t_infomask ,C.HEAP_XMIN_FROZEN) == C.HEAP_XMIN_FROZEN )
end

local function DatumGetArrayTypeP(X)
  return ffi.cast('ArrayType *', PG_DETOAST_DATUM(X))
end

local function HeapTupleHeaderGetRawXmin(tup)
  return tup.t_choice.t_heap.t_xmin
end

local TransactionId = ffi.typeof('TransactionId')
local FrozenTransactionId = ffi.cast(TransactionId, 2)
local function HeapTupleHeaderGetXmin(tup)
  if HeapTupleHeaderXminFrozen(tup) then
    return FrozenTransactionId
  end

  return HeapTupleHeaderGetRawXmin(tup)
end

local function SET_VARSIZE(PTR, len)
  local varattrib_4b = ffi.cast('varattrib_4b *', PTR)
  if (C.D_WORDS_BIGENDIAN == 0) then
    varattrib_4b.va_4byte.va_header = lshift(ffi.cast('uint32', len), 2)
  else
    varattrib_4b.va_4byte.va_header = band(len, 0x3FFFFFFF)
  end
end


local function PointerGetDatum(X) 
    return ffi.cast('Datum', X)
end

local function CStringGetDatum(X) 
    return PointerGetDatum(ffi.cast('const char *',X))
end

local function InitFunctionCallInfoData(Fcinfo, Flinfo, Nargs, Collation, Context, Resultinfo)
    (Fcinfo).flinfo = (Flinfo);
    (Fcinfo).context = (Context);
    (Fcinfo).resultinfo = (Resultinfo);
    (Fcinfo).fncollation = (Collation);
    (Fcinfo).isnull = false;
    (Fcinfo).nargs = (Nargs);
end

local function FunctionCallInvoke(fcinfo) --
    local fptr = ffi.cast('PGFunction', fcinfo.flinfo.fn_addr)
    --TODO: try catch ?
    return fptr(fcinfo)
end

local function ARR_NDIM(array)
    return array.ndim
end


local function ARR_DIMS(array)
    return ffi.cast('int*', (ffi.cast('char*', array) + C.SHIFT_ARR_DIMS))
end

--[[
    #define ARR_LBOUND(a) \
		((int *) (((char *) (a)) + sizeof(ArrayType) + \
				  sizeof(int) * ARR_NDIM(a)))
]]
local sz_ArrayType = ffi.sizeof('ArrayType')
local sz_int = ffi.sizeof('int')
local function ARR_LBOUND(array)
    return ffi.cast('int*', (ffi.cast('char*', array) + sz_ArrayType + sz_int * ARR_NDIM(array)))
end

local function get_typlenbyvalalign(typid)
    local typlen = ffi.new("int16[?]", 1)
    local typbyval = ffi.new("bool[?]", 1)
    local typalign = ffi.new("char[?]", 1)

    C.get_typlenbyvalalign(typid, typlen, typbyval, typalign)
end

return {
  GETSTRUCT = GETSTRUCT,
  PG_DETOAST_DATUM = PG_DETOAST_DATUM,
  SET_4_BYTES = SET_4_BYTES,
  ObjectIdGetDatum = ObjectIdGetDatum,
  HeapTupleHeaderXminFrozen = HeapTupleHeaderXminFrozen,
  DatumGetArrayTypeP = DatumGetArrayTypeP,
  HeapTupleHeaderGetRawXmin = HeapTupleHeaderGetRawXmin,
  HeapTupleHeaderGetXmin = HeapTupleHeaderGetXmin,
  GET_2_BYTES = GET_2_BYTES,
  SET_VARSIZE = SET_VARSIZE,
  GET_4_BYTES = GET_4_BYTES,
  DatumGetObjectId = DatumGetObjectId,
  CStringGetDatum = CStringGetDatum,
  InitFunctionCallInfoData = InitFunctionCallInfoData,
  FunctionCallInvoke = FunctionCallInvoke,
  ARR_NDIM = ARR_NDIM,
  ARR_DIMS = ARR_DIMS,
  ARR_LBOUND = ARR_LBOUND,
}