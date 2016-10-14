local band = require("bit").band

local ffi = require('ffi')
local C = ffi.C


local HEAP_XMIN_COMMITTED	=	0x0100	--/* t_xmin committed */
local HEAP_XMIN_INVALID	=	0x0200	--/* t_xmin invalid/aborted */
local HEAP_XMIN_FROZEN = band(HEAP_XMIN_COMMITTED,HEAP_XMIN_INVALID)

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


local function ObjectIdGetDatum(X)
  return ffi.cast('Datum', SET_4_BYTES(X))
end

local function HeapTupleHeaderXminFrozen(tup)
  --((tup)->t_infomask & (HEAP_XMIN_FROZEN)) == HEAP_XMIN_FROZEN 
  return (band(tup.t_infomask ,HEAP_XMIN_FROZEN) == HEAP_XMIN_FROZEN )
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

return {
  GETSTRUCT = GETSTRUCT,
  PG_DETOAST_DATUM = PG_DETOAST_DATUM,
  SET_4_BYTES = SET_4_BYTES,
  ObjectIdGetDatum = ObjectIdGetDatum,
  HeapTupleHeaderXminFrozen = HeapTupleHeaderXminFrozen,
  DatumGetArrayTypeP = DatumGetArrayTypeP,
  HeapTupleHeaderGetRawXmin = HeapTupleHeaderGetRawXmin,
  HeapTupleHeaderGetXmin = HeapTupleHeaderGetXmin
  }