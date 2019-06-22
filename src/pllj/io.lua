local ffi = require('ffi')
local C = ffi.C
local pg_error = require('pllj.pg.pg_error')

local type_map = {}

local get_pg_typeinfo = require('pllj.pg.type_info').get_pg_typeinfo
local table_new = require('table.new')

local function add_io(type)
    type_map[tonumber(type.oid)] = { 
        to_lua = type.to_lua or type.OUTPUT,
        to_datum = type.to_datum or type.INPUT 
    }
end

add_io(require('pllj.type.void'))
add_io(require('pllj.type.text'))
add_io(require('pllj.type.int2'))
add_io(require('pllj.type.int4'))
add_io(require('pllj.type.int8'))
add_io(require('pllj.type.float4'))
add_io(require('pllj.type.float8'))
add_io(require('pllj.type.float4array'))
add_io(require('pllj.type.float8array'))
add_io(require('pllj.type.int2array'))
add_io(require('pllj.type.int4array'))
add_io(require('pllj.type.int8array'))
add_io(require('pllj.type.textarray'))

--[[{
    datum = 1,
    oid = 2,
    typeinfo = 3,
    input = 4,
    output = 5
}]]
local _private = setmetatable({}, {__mode = "k"}) 

local raw_datum_mt 
local wrap_datum
local unwrap_datum

if __untrusted__ then
    raw_datum_mt =  {
        __tostring = function(self)
            local value = self
            local charPtr = C.OutputFunctionCall(value[5], value[1])
            return ffi.string(charPtr)
        end
    }
    wrap_datum = function(obj)
        setmetatable(obj, raw_datum_mt)
        return obj
    end
    unwrap_datum = function(obj)
        return obj
    end
else
    raw_datum_mt =  {
        __tostring = function(self)
            local value = _private[self]
            local charPtr = C.OutputFunctionCall(value[5], value[1])
            return ffi.string(charPtr)
        end
    }
    wrap_datum = function(obj)
        local value = {}
        _private[value] = obj
        setmetatable(value, raw_datum_mt)
        return value
    end
    unwrap_datum = function(obj)
        return _private[obj]
    end
end

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

            return wrap_datum({
                datum,
                oid,
                typeinfo,
                input,
                output
            })
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
            elseif (type(value) == "table" and getmetatable(value) == raw_datum_mt) then
                return unwrap_datum(value)
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
    return get_type(tonumber(typeoid)).to_lua
end

local function to_pg(typeoid)
    return get_type(tonumber(typeoid)).to_datum
end

local convert_to_lua_args

if C.PG_VERSION_NUM >= 120000 then
    convert_to_lua_args = function(fcinfo, func_struct)
        local args = table_new(fcinfo.nargs, 0)
        for i = 0, fcinfo.nargs - 1 do
            if fcinfo.args[i].isnull == true then
                table.insert(args, NULL)
            else
                local typeoid = func_struct.argtypes[i + 1]
                local converter_to_lua = to_lua(typeoid)
    
                if not converter_to_lua then
                    return error('no conversion for type ' .. typeoid)
                end
                table.insert(args, converter_to_lua(fcinfo.args[i].value))
            end
        end
        return args
    end
else
    convert_to_lua_args = function(fcinfo, func_struct)
        local args = table_new(fcinfo.nargs, 0)
        for i = 0, fcinfo.nargs - 1 do
            if fcinfo.argnull[i] == true then
                table.insert(args, NULL)
            else
                local typeoid = func_struct.argtypes[i + 1]
                local converter_to_lua = to_lua(typeoid)
    
                if not converter_to_lua then
                    return error('no conversion for type ' .. typeoid)
                end
                table.insert(args, converter_to_lua(fcinfo.arg[i]))
            end
        end
        return args
    end
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
    to_pg = to_pg,
    convert_to_lua_args = convert_to_lua_args,
}