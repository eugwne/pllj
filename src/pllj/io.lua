local ffi = require('ffi')
local C = ffi.C
local pg_error = require('pllj.pg.pg_error')

local type_map = {}

local get_pg_typeinfo = require('pllj.pg.type_info').get_pg_typeinfo

local function add_io(type)
    type_map[type.oid] = { 
        to_lua = type.to_lua or type.OUTPUT,
        to_datum = type.to_datum or type.INPUT 
    }
end

add_io(require('pllj.type.void'))
add_io(require('pllj.type.text'))
add_io(require('pllj.type.int2'))
add_io(require('pllj.type.int4'))
add_io(require('pllj.type.int8'))
add_io(require('pllj.type.int2array'))
add_io(require('pllj.type.int4array'))
add_io(require('pllj.type.int8array'))
add_io(require('pllj.type.textarray'))

local _private = setmetatable({}, {__mode = "k"}) 

local raw_datum = {
    __tostring = function(self)
        local value = _private[self]
        local charPtr = C.OutputFunctionCall(value.output, value.datum)
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
            local value = {}
            _private[value] = {
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

                local datum = C.lj_InputFunctionCall(input, ffi.cast('char*', text), inoid, -1)
                pg_error.throw_last_error();
                C.CurrentMemoryContext = prev

                return datum
            elseif (type(value) == "table" and getmetatable(value) == raw_datum) then
                return _private[value].datum
            else 
                error('NYI')
            end
        end
    end
    free()
    return result

end

local function get_type(typeoid)
    local type_data = type_map[typeoid]
    if not type_data then
        local to_lua = create_converter_tolua(typeoid) or function(datum) return datum end
        local to_datum = create_converter_topg(typeoid) or function(datum) return datum end
        type_data = {
            to_lua = to_lua,
            to_datum = to_datum
        }
        type_map[typeoid] = type_data
    end
    return type_data
end

local function to_lua(typeoid)
    return get_type(typeoid).to_lua
end

local function to_pg(typeoid)
    return get_type(typeoid).to_datum
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