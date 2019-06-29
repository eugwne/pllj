local ffi = require('ffi')
local C = ffi.C
local pg_error = require('pllj.pg.pg_error')
local macro = require('pllj.pg.macro')
local io = {}

local type_map = {}

local isNull = ffi.new("bool[?]", 1)

local get_pg_typeinfo = require('pllj.pg.type_info').get_pg_typeinfo
local table_new = require('table.new')

local composite_t = require('pllj.type.composite[T]')
local datum_t = require('pllj.type.datum[T]')

local to_lua
local to_pg

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


local function create_converter_tolua(oid)
    return datum_t.to_lua_T({oid = oid})
end

local function create_converter_topg(oid)
    return datum_t.to_datum_T({oid = oid})
end

local function forward(value)
    return value
end 
local function get_type(typeoid)
    local type_data = type_map[typeoid]
    if not type_data then
        local to_lua = create_converter_tolua(typeoid) or forward
        local to_datum = create_converter_topg(typeoid) or forward
        type_data = {
            to_lua = to_lua,
            to_datum = to_datum
        }
        type_map[typeoid] = type_data
    end
    return type_data
end

to_lua = function(typeoid)
    return get_type(tonumber(typeoid)).to_lua
end

to_pg = function(typeoid)
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
            --pg12 fcinfo.args[i].isnull
            if fcinfo.argnull[i] == true then
                table.insert(args, NULL)
            else
                local typeoid = func_struct.argtypes[i + 1]
                local converter_to_lua = to_lua(typeoid)
    
                if not converter_to_lua then
                    return error('no conversion for type ' .. typeoid)
                end
                --pg12 fcinfo.args[i].value
                table.insert(args, converter_to_lua(fcinfo.arg[i]))
            end
        end
        return args
    end
end

io.to_lua = to_lua
io.datumfor = datumfor
io.to_pg = to_pg
io.convert_to_lua_args = convert_to_lua_args

do
    composite_t.set_io(io)
    require('pllj.tuple_ops').set_io(io)
end

return io
