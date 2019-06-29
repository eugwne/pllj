local ffi = require('ffi')
local C = ffi.C

local syscache = require('pllj.pg.syscache')
local macro = require('pllj.pg.macro')

local call_pg_c_variadic
if C.PG_VERSION_NUM >= 120000 then
    local __finfo = ffi.new('FCInfoMax[1]')

    call_pg_c_variadic = function (cf, PG_FUNCTION_ARGS)
        local argc = #PG_FUNCTION_ARGS
        local fcinfo = __finfo[0].fcinfo
        for i = 0, argc - 1 do
            local ref_arg = fcinfo.args[i]
            ref_arg.value = PG_FUNCTION_ARGS[i+1]
        end
        return cf(ffi.cast('FunctionCallInfo', __finfo))
    end
else
    local __finfo = ffi.new('struct FunctionCallInfoData')
    call_pg_c_variadic = function (cf, PG_FUNCTION_ARGS)
        local argc = #PG_FUNCTION_ARGS
        for i = 0, argc -1 do
            __finfo.arg[i] = PG_FUNCTION_ARGS[i+1]
        end
        return cf(__finfo)
    end
end

--deprecated
--local function find_lang_oid(str)
--    local tuple = C.SearchSysCache(syscache.enum.LANGNAME, macro.CStringGetDatum(str), 0, 0, 0);
--    if tuple == nil then
--        return 0
--    end
--    local langtupoid = C.ljm_HeapTupleGetOid(tuple)
--    C.ReleaseSysCache(tuple)
--    return langtupoid
--end

local function find_lang_name(oid)
    local result = C.get_language_name(oid, true)
    local name = result == nil and "" or ffi.string(result)
    return name
end

return { 
    --find_lang_oid = find_lang_oid,
    find_lang_name = find_lang_name,
    call_pg_c_variadic = call_pg_c_variadic,
}
