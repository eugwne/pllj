local ffi = require('ffi')
local C = ffi.C
require('pllj.pg.init_c')
local macro = require('pllj.pg.macro')
local call_pg_variadic = require('pllj.pg.func').call_pg_variadic
local table_new = require('table.new')
local NULL = ffi.NULL

local typeto = {}


typeto[C.INT4ARRAYOID] = function (datum)
    assert(datum ~= nil)
    local arr = ffi.cast('ArrayType *', macro.DatumGetArrayTypeP(datum)) 
    local ndim = macro.ARR_NDIM(arr)
    if ndim == 0 then
        return {}
    end
    assert(ndim == 1)
    local dims = macro.ARR_DIMS(arr)
    if dims[0] == 0 then
        return {}
    end
    local lbound = macro.ARR_LBOUND(arr)[0]
    local typid = C.INT4OID --ARR_ELEMTYPE(arr);
    local typlen = ffi.new("int16[?]", 1)
    local typbyval = ffi.new("bool[?]", 1)
    local typalign = ffi.new("char[?]", 1)

    C.get_typlenbyvalalign(typid, typlen, typbyval, typalign)
    local elemsp = ffi.new("Datum*[?]", 1)
    local nullsp = ffi.new("bool*[?]", 1)
    C.deconstruct_array(arr, typid, typlen[0], typbyval[0], typalign[0], elemsp, nullsp, dims);
    
    if dims[0] == 0 then
        return {}
    end
    dims = dims[0]
    local DatumGetInt32 = typeto[C.INT4OID]
    local t = table_new(dims, 0)
    for i = 0, dims -1 do
        if nullsp[0][i] == true then
            t[lbound] = NULL
          else
            t[lbound] = DatumGetInt32(elemsp[0][i]);
          end
          lbound = lbound + 1
    end
    return t

end

typeto[C.TEXTOID] = function (datum)
    --local d = C.DirectFunctionCall1Coll(C.textout, C.InvalidOid, datum)
    local d = call_pg_variadic(C.textout, {datum})
    return ffi.string(ffi.cast('Pointer', d))
end


typeto[C.INT4OID] = function (datum)
    return tonumber(macro.GET_4_BYTES(datum))
end

typeto[C.INT2OID] = function (datum)
    return tonumber(macro.GET_2_BYTES(datum))
end

typeto[C.INT8OID] = function (datum)
    return ffi.cast('int64_t', datum)
end

typeto[C.VOIDOID] = function ()
end


return {typeto = typeto}
