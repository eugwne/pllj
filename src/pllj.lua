require('pllj.pg.init_c')

local pllj = {}

local function_cache = {}

local ffi = require('ffi')


local NULL = ffi.NULL

local pgdef = require('pllj.pgdefines')

pllj._DESCRIPTION = "LuaJIT FFI postgres language extension"
pllj._VERSION = "pllj 0.1"


local C = ffi.C;

local spi = require('pllj.spi')

local throw_error = spi.throw_error

require('pllj.func') 
local env = require('pllj.env').env

local function error_xcall(err)
    if type(err) == "table" then
        if err.detail == nil then
            err.detail = debug.traceback()
        end
        return err
    else
        return { message = err, detail = debug.traceback() }
    end
end

local function exec(f)
    local status, err, ret = xpcall(f, error_xcall)

    if status ~= true then
        if type(err) == "table" then
            if err.detail == nil then
                err.detail = debug.traceback()
            end
            throw_error(err)
        else
            throw_error({ message = err, detail = debug.traceback() })
        end
    end
    return ret
end

local pllj_func = require('pllj.func')
local get_func_from_oid = pllj_func.get_func_from_oid
local need_update = pllj_func.need_update

local to_lua = require('pllj.io').to_lua
local to_pg = require('pllj.io').to_pg

local FunctionCallInfo = ffi.typeof('struct FunctionCallInfoData *')

local trigger_handler = require('pllj.trigger').trigger_handler

function pllj.validator(fn_oid)
    local f, err = get_func_from_oid(fn_oid)
    if not f then 
        error(err) 
    end
    function_cache[fn_oid] = f
end


function pllj.callhandler(fcinfo)
    spi.connect()
    fcinfo = ffi.cast(FunctionCallInfo, fcinfo)
    local fn_oid = fcinfo.flinfo.fn_oid
    local func_struct = function_cache[fn_oid]


    if not func_struct or need_update(func_struct) then
        local f, err = get_func_from_oid(fn_oid)
        if not f then 
            return throw_error(err) 
        end
        func_struct = f
        function_cache[fn_oid] = func_struct
    end

    local istrigger = C.lj_CALLED_AS_TRIGGER(fcinfo)
    if istrigger then
        local status, trg_result = trigger_handler(func_struct, fcinfo) --result_type
        if status then
            C.set_pllj_call_result(ffi.cast('Datum', trg_result))
            return spi.disconnect()
        end


        return spi.disconnect()
    end
    local args = {}
    for i = 0, fcinfo.nargs - 1 do
        if fcinfo.argnull[i] == true then
            table.insert(args, NULL)
        else
            local typeoid = func_struct.argtypes[i + 1]
            local converter_to_lua = to_lua(typeoid)

            if not converter_to_lua then
                return throw_error('no conversion for type ' .. typeoid)
            end
            table.insert(args, converter_to_lua(fcinfo.arg[i]))
        end
    end
    -- TODO pcall
    local result = func_struct.func(unpack(args))

    local iof = to_pg(func_struct.result_type)

    if not iof then
        --get_pg_typeinfo(func_struct.result_type)
        return throw_error('no conversion for type ' .. tostring(func_struct.result_type))
    end
    if not result or result == NULL then
        fcinfo.isnull = true
        return spi.disconnect()
    end

    C.set_pllj_call_result(iof(result))
    return spi.disconnect()
end

function pllj.inlinehandler(...)
    spi.connect()
    local text = select(1, ...)
    local f, err = loadstring(text, nil, "t", env)
    if (f) then
        exec(f)
    else
        return throw_error(err)
    end
    return spi.disconnect()
end

return pllj
