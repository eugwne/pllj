local ffi = require('ffi')
local C = ffi.C

local band = require("bit").band
local lshift = require("bit").lshift
local rshift = require("bit").rshift

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

local VARSIZE
local SET_VARSIZE
if (C.D_WORDS_BIGENDIAN == 0) then

    VARSIZE = function (PTR)
        local varattrib_4b = ffi.cast('varattrib_4b *', PTR)
        return band(rshift(varattrib_4b.va_4byte.va_header, 2), 0x3FFFFFFF)
    end
    SET_VARSIZE = function (PTR, len)
        local varattrib_4b = ffi.cast('varattrib_4b *', PTR)
        varattrib_4b.va_4byte.va_header = lshift(ffi.cast('uint32', len), 2)
    end

else

    VARSIZE = function (PTR)
        local varattrib_4b = ffi.cast('varattrib_4b *', PTR)
        return band(varattrib_4b.va_4byte.va_header, 0x3FFFFFFF)
    end
    SET_VARSIZE = function (PTR, len)
        local varattrib_4b = ffi.cast('varattrib_4b *', PTR)
        varattrib_4b.va_4byte.va_header = band(len, 0x3FFFFFFF)
    end
end

local function PointerGetDatum(X) 
    return ffi.cast('Datum', X)
end

local function CStringGetDatum(X) 
    return PointerGetDatum(ffi.cast('const char *',X))
end

local InitFunctionCallInfoData = function(Fcinfo, Flinfo, Nargs, Collation, Context, Resultinfo)
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
    local len = ffi.new("int16[?]", 1)
    local byval = ffi.new("bool[?]", 1)
    local align = ffi.new("char[?]", 1)

    C.get_typlenbyvalalign(typid, len, byval, align)
    return {len = len[0], byval = byval[0], align = align[0]}
end

local function ReleaseTupleDesc(tupdesc)
    if tupdesc.tdrefcount >= 0 then
        C.DecrTupleDescRefCount(tupdesc)
    end
end

local function HeapTupleHeaderGetTypeId(tup)
  return tup.t_choice.t_datum.datum_typeid
end

local function HeapTupleHeaderGetTypMod(tup)
  return tup.t_choice.t_datum.datum_typmod
end

local function HeapTupleHeaderGetDatumLength(tup)
  return VARSIZE(tup)
end

local SizeForFunctionCallInfo
if C.PG_VERSION_NUM >= 120000 then
    SizeForFunctionCallInfo = function (nargs)
        local size = ffi.offsetof('FunctionCallInfoBaseData', 'args') + ffi.sizeof('NullableDatum') * nargs
        return size
    end
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
  VARSIZE = VARSIZE,
  GET_4_BYTES = GET_4_BYTES,
  DatumGetObjectId = DatumGetObjectId,
  CStringGetDatum = CStringGetDatum,
  InitFunctionCallInfoData = InitFunctionCallInfoData,
  FunctionCallInvoke = FunctionCallInvoke,
  ARR_NDIM = ARR_NDIM,
  ARR_DIMS = ARR_DIMS,
  ARR_LBOUND = ARR_LBOUND,
  get_typlenbyvalalign = get_typlenbyvalalign,
  ReleaseTupleDesc = ReleaseTupleDesc,
  SizeForFunctionCallInfo = SizeForFunctionCallInfo,
  HeapTupleHeaderGetTypeId = HeapTupleHeaderGetTypeId,
  HeapTupleHeaderGetTypMod = HeapTupleHeaderGetTypMod,
  HeapTupleHeaderGetDatumLength = HeapTupleHeaderGetDatumLength,
}
