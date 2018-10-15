require('pllj.pg.init_c')

local pllj = {}

local function_cache = {}

local ffi = require('ffi')


local NULL = ffi.NULL

local pgdef = require('pllj.pgdefines')

pllj._DESCRIPTION = "LuaJIT FFI postgres language extension"
pllj._VERSION = "pllj 0.1"


local C = ffi.C;

local spi_opt = require('pllj.spi').opt

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
            return error(err)
        else
            return error({ message = err, detail = debug.traceback() })
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
local RefLJFunctionData = ffi.typeof('LJFunctionData *')

local trigger_handler = require('pllj.trigger').trigger_handler

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
    fcinfo = ffi.cast(FunctionCallInfo, ctx.fcinfo)
    local fn_oid = fcinfo.flinfo.fn_oid
    local func_struct = function_cache[fn_oid]


    if not func_struct or need_update(func_struct) then
        local f, err = get_func_from_oid(fn_oid)
        if not f then 
            return error(err) 
        end
        func_struct = f
        function_cache[fn_oid] = func_struct
    end

    local istrigger = C.lj_CALLED_AS_TRIGGER(fcinfo)
    if istrigger then
        local status, trg_result = trigger_handler(func_struct, fcinfo) --result_type
        if status then
            ctx.result[0] = ffi.cast('Datum', trg_result)
            return 
        end
        return 
    end

    local args = {}
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
    -- TODO pcall?
    spi_opt.readonly = func_struct.readonly
    local result = func_struct.func(unpack(args))

    local iof = to_pg(func_struct.result_type)

    if not iof then
        --get_pg_typeinfo(func_struct.result_type)
        return error('no conversion for type ' .. tostring(func_struct.result_type))
    end
    if not result or result == NULL then
        fcinfo.isnull = true
        return 
    end

    ctx.result[0] = ffi.cast('Datum', iof(result))

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

return pllj
