local ffi = require('ffi')
local C = ffi.C;
local NULL = ffi.NULL


local SRF = {}
local srf_index = 0

local spi_opt = require('pllj.spi').opt

local to_pg = require('pllj.io').to_pg
local convert_to_lua_args = require('pllj.io').convert_to_lua_args

local function SRF_IS_FIRSTCALL(fcinfo) 
    return fcinfo.flinfo.fn_extra == nil
end

local function SRF_FIRSTCALL_INIT(fcinfo)
    return C.ljm_SRF_FIRSTCALL_INIT(fcinfo);
end

local function SRF_PERCALL_SETUP(fcinfo)
    return C.ljm_SRF_PERCALL_SETUP(fcinfo);
end

local function SRF_RETURN_DONE(fcinfo, funcctx)
    return C.ljm_SRF_RETURN_DONE(fcinfo, funcctx);
end

local function SRF_RETURN_NEXT(fcinfo, funcctx)
    return C.ljm_SRF_RETURN_NEXT(fcinfo, funcctx);
end

local function srf_handler(func_struct, fcinfo, ctx_result)
    local funcctx
    if SRF_IS_FIRSTCALL(fcinfo) then
        funcctx = SRF_FIRSTCALL_INIT(fcinfo);
        assert(funcctx ~= nil)
        local prev = C.CurrentMemoryContext
        C.CurrentMemoryContext = funcctx.multi_call_memory_ctx

        srf_index = srf_index + 1
        funcctx.user_fctx = ffi.cast('void*', srf_index)
        
        local iof = to_pg(func_struct.result_type)

        if not iof then
            return error('no conversion for type ' .. tostring(func_struct.result_type))
        end

        SRF[srf_index] = {coroutine.create(func_struct.func), convert_to_lua_args(fcinfo, func_struct), iof}

        C.CurrentMemoryContext = prev
    end
    funcctx = SRF_PERCALL_SETUP(fcinfo);
    local coindex = tonumber(ffi.cast('int',funcctx.user_fctx))
    local co = SRF[coindex][1]
    spi_opt.readonly = func_struct.readonly

    if coroutine.status(co) ==  "suspended" then --(funcctx.call_cntr < funcctx.max_calls)   
        local srf_data = SRF[srf_index]
        local args
        local status, result
        local iof = srf_data[3]
        if srf_data[2] then
            args = srf_data[2]
            srf_data[2] = nil
            status, result = coroutine.resume(co, unpack(args))
        else
            status, result = coroutine.resume(co)
        end 
        if status == true then
            if coroutine.status(co) ==  "dead" then
                SRF[coindex] = nil
                ctx_result[0] =  SRF_RETURN_DONE(fcinfo, funcctx);
                return
            end
            if not result or result == NULL then
                fcinfo.isnull = true
            else
                ctx_result[0] = ffi.cast('Datum', iof(result))
            end

            SRF_RETURN_NEXT(fcinfo, funcctx)
            return
        else
            SRF[coindex] = nil
            return error(result)
        end

    else
        --not expected to be here
        SRF[coindex] = nil
        ctx_result[0] =  SRF_RETURN_DONE(fcinfo, funcctx);
        return
    end
end

return {
    srf_handler = srf_handler
}
