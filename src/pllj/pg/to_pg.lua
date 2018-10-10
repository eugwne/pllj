local ffi = require('ffi')
local C = ffi.C
require('pllj.pg.init_c')
local macro = require('pllj.pg.macro')
local NULL = ffi.NULL

local datumfor = {}

local szArrayType = ffi.sizeof('ArrayType')
local szDatum = ffi.sizeof('Datum')
datumfor[C.INT4ARRAYOID] = function (v)
    if v == nil or v == NULL then
        return ffi.cast('Datum', 0)
    end
    local type_name = type(v)
    if (type_name == 'table') then
        local ndims = -1
        local lbound, ubound
        local dims
        for k, _ in pairs(v) do
            if type(k) == 'number' then
                if lbound then
                    lbound = math.min(lbound, k)
                    ubound = math.max(ubound, k)
                 else
                    lbound, ubound = k, k
                 end
            end
        end

        local size = 0
        if ubound and lbound then
            size = ubound - lbound + 1
        end
        if size == 0 then
            local arr = ffi.cast('ArrayType*', C.SPI_palloc(szArrayType));
            macro.SET_VARSIZE(arr, szArrayType);
            arr.ndim = 0;
            arr.dataoffset = 0;
            arr.elemtype = C.INT4OID;
            return ffi.cast('Datum', arr)
        end
        local ndims = 1
        local elmtype = C.INT4OID
        local d = ffi.cast('Datum *', C.SPI_palloc(szDatum * size));
        local nulls = ffi.new("bool[?]", size)
        local dims = ffi.new("int[?]", ndims)
        local lbs = ffi.new("int[?]", ndims)
        dims[0] = size
        lbs[0] = lbound

        local Int32GetDatum = datumfor[C.INT4OID]
        local zidx = 0
        for i = lbound, ubound do
            local value = v[i]
            if value == nil then
                nulls[zidx] = true
            else
                d[zidx] = Int32GetDatum(value);
            end
            zidx = zidx + 1
        end
        local typlen = ffi.new("int16[?]", 1)
        local typbyval = ffi.new("bool[?]", 1)
        local typalign = ffi.new("char[?]", 1)
    
        C.get_typlenbyvalalign(elmtype, typlen, typbyval, typalign)

        local prev = C.CurrentMemoryContext
        C.CurrentMemoryContext = C.CurTransactionContext
        --TODO try catch
        local arr = C.construct_md_array(d, nulls, ndims, dims, lbs, elmtype, typlen[0], typbyval[0], typalign[0])
        C.CurrentMemoryContext = prev

        return ffi.cast('Datum', arr)

    end
    return error('NYI')
end

datumfor[C.TEXTOID] = function (v , p_isnull)
    if v == nil or v == NULL then
        if (p_isnull ~=nil) then
            p_isnull[0] = true
        end

        return ffi.cast('Datum', 0)
    end
    local length = #v
    local varsize = C.VARHDRSZ + length
    local out_ptr = C.SPI_palloc(varsize)
    macro.SET_VARSIZE(out_ptr, varsize)
    ffi.copy(ffi.cast('varattrib_4b *', out_ptr).va_4byte.va_data, v, length)
    --return ffi.string(ffi.cast('Pointer', d))
    return ffi.cast('Datum', out_ptr)
end

datumfor[C.INT4OID] = function (v)
    return ffi.cast('Datum',--[[SET_4_BYTES]](tonumber(v)))
end

datumfor[C.INT2OID] = function (v)
    return ffi.cast('Datum', macro.GET_2_BYTES(tonumber(v)))
end

datumfor[C.INT8OID] = function (v)
    if type(v) == "cdata" and ffi.istype('int64_t', v) then
        return ffi.cast('Datum', v)
    end

    return ffi.cast('Datum', tonumber(v))
end

datumfor[C.VOIDOID] = function ()
    return ffi.cast('Datum', 0)
end

return {datumfor=datumfor}

