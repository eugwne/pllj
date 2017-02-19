local pllj = {}

local function_cache = {}

local ffi = require('ffi')
local all_types = require('pllj.pg.i').all_types
ffi.cdef(all_types)


local NULL = require('pllj.pg.c').NULL

local pgdef = require('pllj.pgdefines')

pllj._DESCRIPTION = "LuaJIT FFI postgres language extension"
pllj._VERSION = "pllj 0.1"



ffi.cdef [[
void set_pllj_call_result(Datum result);
]]
local C = ffi.C;

print = function(text)
    C.errstart(pgdef.elog["INFO"], "", 0, nil, nil)
    C.errfinish(C.errmsg(tostring(text)))
end

local spi = require('pllj.spi')


local pllj_func = require('pllj.func')
local get_func_from_oid = pllj_func.get_func_from_oid
local need_update = pllj_func.need_update


local to_lua = require('pllj.io').to_lua
local datumfor = require('pllj.io').datumfor

local FunctionCallInfo = ffi.typeof('struct FunctionCallInfoData *')


function pllj.validator(fn_oid)

    function_cache[fn_oid] = get_func_from_oid(fn_oid)
end


function pllj.callhandler(fcinfo)
    spi.connect()
    fcinfo = ffi.cast(FunctionCallInfo, fcinfo)
    local fn_oid = fcinfo.flinfo.fn_oid
    local func_struct = function_cache[fn_oid]


    if not func_struct or need_update(func_struct) then
        func_struct = get_func_from_oid(fn_oid)
        function_cache[fn_oid] = func_struct
    end

    --[[istrigger = CALLED_AS_TRIGGER(fcinfo)]]
    local args = {}
    for i = 0, fcinfo.nargs - 1 do
        if fcinfo.argnull[i] == true then
            table.insert(args, NULL)
        else
            local typeoid = func_struct.argtypes[i + 1]
            local converter_to_lua = to_lua(typeoid)

            if not converter_to_lua then
                spi.disconnect()
                error('no conversion for type ' .. typeoid)
            end
            table.insert(args, converter_to_lua(fcinfo.arg[i]))
        end
    end
    -- TODO pcall
    local result = func_struct.func(unpack(args))
    local iof = datumfor[func_struct.result_type]

    if not iof then
        spi.disconnect()
        --get_pg_typeinfo(func_struct.result_type)
        error('no conversion for type ' .. tostring(func_struct.result_type))
    end
    if not result or result == NULL then
        fcinfo.isnull = true
        return spi.disconnect()
    end

    C.set_pllj_call_result(iof(result))
    spi.disconnect()
end

function pllj.inlinehandler(...)
    spi.connect()
    local text = select(1, ...)
    local f, err = loadstring(text)
    if (f) then
        local status, err = xpcall(f, function(err)
            if type(err) == "table" then
                if err.detail == nil then
                    err.detail = debug.traceback()
                end
                return err
            else
                return { message = err, detail = debug.traceback() }
            end
        end)
        spi.disconnect()
        if status ~= true then
            if type(err) == "table" then
                if err.detail == nil then
                    err.detail = debug.traceback()
                end
                error(err)
            else
                error({ message = err, detail = debug.traceback() })
            end
        end


    else
        spi.disconnect()
        error(err)
    end
end

return pllj
