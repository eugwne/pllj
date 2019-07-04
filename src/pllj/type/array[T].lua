local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')
local NULL = ffi.NULL
local pg_error = require('pllj.pg.pg_error')

local table_new = require('table.new')

local function to_lua_T(T)
    local elmtype = assert(T.oid)
    local item_to_lua = assert(T.to_lua)
    local typ = macro.get_typlenbyvalalign(elmtype)

    local to_lua = function(datum)
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
   

        local elemsp = ffi.new("Datum*[?]", 1)
        local nullsp = ffi.new("bool*[?]", 1)
        C.deconstruct_array(arr, elmtype, typ.len, typ.byval, typ.align, elemsp, nullsp, dims);
        
        if dims[0] == 0 then
            return {}
        end
        dims = dims[0]

        local t = table_new(dims, 0)
        for i = 0, dims -1 do
            if nullsp[0][i] == true then
                t[lbound] = NULL
              else
                t[lbound] = item_to_lua(elemsp[0][i]);
              end
              lbound = lbound + 1
        end
        return t
    end
    return to_lua
end


local szArrayType = ffi.sizeof('ArrayType')
local szDatum = ffi.sizeof('Datum')

local function to_datum_T(T)
    local elmtype = assert(T.oid)
    local item_to_datum = assert(T.to_datum)
    local typ = macro.get_typlenbyvalalign(elmtype)

    local to_datum = function(lv)
        if lv == nil or lv == NULL then
            return ffi.cast('Datum', 0), true
        end
        local type_name = type(lv)
        if (type_name == 'table') then
            local ndims = -1
            local lbound, ubound
            local dims
            for k, _ in pairs(lv) do
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
                arr.elemtype = elmtype;
                return ffi.cast('Datum', arr)
            end
            local ndims = 1

            local d = ffi.cast('Datum *', C.SPI_palloc(szDatum * size));
            local nulls = ffi.new("bool[?]", size)
            local dims = ffi.new("int[?]", ndims)
            local lbs = ffi.new("int[?]", ndims)
            dims[0] = size
            lbs[0] = lbound

            local zidx = 0
            for i = lbound, ubound do
                local value = lv[i]
                if value == nil then
                    nulls[zidx] = true
                else
                    d[zidx] = item_to_datum(value);
                end
                zidx = zidx + 1
            end
    
            local prev = C.CurrentMemoryContext
            C.CurrentMemoryContext = C.CurTransactionContext
    
            local arr = C.lj_construct_md_array(d, nulls, ndims, dims, lbs, elmtype, typ.len, typ.byval, typ.align)
            C.CurrentMemoryContext = prev
            pg_error.throw_last_error("construct_md_array error: ")
    
            return ffi.cast('Datum', arr), false
    
        end
        return error('NYI')
    end
    return to_datum

end

return {
    to_lua_T = to_lua_T,
    to_datum_T = to_datum_T,
}
