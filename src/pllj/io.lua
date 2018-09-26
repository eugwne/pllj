local ffi = require('ffi')
local C = ffi.C

local typeto = require('pllj.pg.to_lua').typeto
local datumfor = require('pllj.pg.to_pg').datumfor

local get_pg_typeinfo = require('pllj.pg.type_info').get_pg_typeinfo

local raw_datum = {
    __tostring = function(self)
        local charPtr = C.OutputFunctionCall(self.output, self.datum)
        return ffi.string(charPtr)
    end
}

local function create_converter_tolua(oid)
    local typeinfo = get_pg_typeinfo(oid)
    local free = typeinfo._free;
    typeinfo = typeinfo.data
    local result
    if typeinfo.typtype == C.TYPTYPE_BASE then

        local input = ffi.new("FmgrInfo[?]", 1)
        local output = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(typeinfo.typinput, input, C.TopMemoryContext);
        C.fmgr_info_cxt(typeinfo.typoutput, output, C.TopMemoryContext);

        result = function (datum)
            local value = {
                datum = datum,
                oid = oid,
                typeinfo = typeinfo,
                input = input,
                output = output
            }
            setmetatable(value, raw_datum)

            return value
        end
    end
    free()
    return result

end

local function create_converter_topg(oid)
    local typeinfo = get_pg_typeinfo(oid)
    local free = typeinfo._free;
    typeinfo = typeinfo.data
    local result
    if typeinfo.typtype == C.TYPTYPE_BASE then

        local input = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(typeinfo.typinput, input, C.TopMemoryContext);

        result = function (value)
            if (type(value) == "string") then
                local inoid = oid
                if typeinfo.typelem ~=0 then
                    inoid = typeinfo.typelem
                end
                local text = tostring(value)
                local prev = C.CurrentMemoryContext
                C.CurrentMemoryContext = C.CurTransactionContext
                local datum = C.InputFunctionCall(input, ffi.cast('char*', text), inoid, -1)
                C.CurrentMemoryContext = prev

                return datum
            elseif (type(value) == "table" and getmetatable(value) == raw_datum) then
                return value.datum
            end
        end
    end
    free()
    return result

end

local function to_lua(typeoid)
    local to_lua = typeto[typeoid]
    if not to_lua then
        to_lua = create_converter_tolua(typeoid) or function(datum) return datum end
        typeto[typeoid] = to_lua
    end
    return to_lua
end

local function to_pg(typeoid)
    local to_pg = datumfor[typeoid]
    if not to_pg then
        to_pg = create_converter_topg(typeoid) or function(datum) return datum end
        datumfor[typeoid] = to_pg
    end
    return to_pg
end

--local function datum_to_value(datum, atttypid)
--
--    local func = typeto[atttypid]
--    if (func) then
--        return func(datum)
--    end
--    return datum --TODO other types
--    --print("SC = "..tonumber(syscache.enum.TYPEOID))
--    --type = C.SearchSysCache(syscache.enum.TYPEOID, ObjectIdGetDatum(oid), 0, 0, 0);
--end

return {
    to_lua = to_lua,
    datumfor = datumfor,
    to_pg = to_pg
}