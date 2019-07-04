local pllj = {}

pllj._DESCRIPTION = "LuaJIT FFI postgres language extension"
pllj._VERSION = "pllj 0.1"

require('pllj.pg.init_c')

local ffi = require('ffi')
local NULL = ffi.NULL
local C = ffi.C;

local spi_opt = require('pllj.spi').opt
local env = require('pllj.env').env

local pllj_func = require('pllj.func')
local get_func_from_oid = pllj_func.get_func_from_oid
local need_update = pllj_func.need_update

local to_lua = require('pllj.io').to_lua
local to_pg = require('pllj.io').to_pg
local convert_to_lua_args = require('pllj.io').convert_to_lua_args

local FunctionCallInfo = ffi.typeof('FunctionCallInfo')
local RefLJFunctionData = ffi.typeof('LJFunctionData *')

local trigger_handler = require('pllj.trigger').trigger_handler

local function_cache = {}


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
            return error(err)
        else
            return error({ message = err, detail = debug.traceback() })
        end
    end
    return ret
end


function pllj.validator(fn_oid)
    spi_opt.readonly = true
    local f, err = get_func_from_oid(fn_oid)
    if not f then 
        error(err) 
    end
    function_cache[fn_oid] = f
end


function pllj.callhandler(ctx)

    ctx = ffi.cast(RefLJFunctionData, ctx)
    local fcinfo = ffi.cast(FunctionCallInfo, ctx.fcinfo)
    local ctx_result = ctx.result
    local fn_oid = fcinfo.flinfo.fn_oid
    local func_struct = function_cache[fn_oid]

    if not func_struct or need_update(func_struct) then
        spi_opt.readonly = true
        local f, err = get_func_from_oid(fn_oid)
        if not f then 
            return error(err) 
        end
        func_struct = f
        function_cache[fn_oid] = func_struct
    end

    local istrigger = C.ljm_CALLED_AS_TRIGGER(fcinfo)
    if istrigger then
        local status, trg_result = trigger_handler(func_struct, fcinfo) --result_type
        if status then
            ctx_result[0] = ffi.cast('Datum', trg_result)
            return 
        end
        return 
    end

    if func_struct.result_isset == true then
        return error('NYI')
    end

    local args = convert_to_lua_args(fcinfo, func_struct)
    -- TODO pcall?
    spi_opt.readonly = func_struct.readonly
    local result = func_struct.func(unpack(args))

    local iof = to_pg(func_struct.result_type)

    if not iof then
        return error('no conversion for type ' .. tostring(func_struct.result_type))
    end
    if not result or result == NULL then
        fcinfo.isnull = true
        return 
    end

    ctx_result[0] = ffi.cast('Datum', iof(result))

    return 
end


function pllj.inlinehandler(text)

    spi_opt.readonly = false
    local f, err = loadstring(text, nil, "t", env)
    if (f) then
        exec(f)
    else
        return error(err)
    end
    return 
end


pllj.validator_u = pllj.validator
pllj.callhandler_u = pllj.callhandler
pllj.inlinehandler_u = pllj.inlinehandler


return pllj
