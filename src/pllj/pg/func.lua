local ffi = require('ffi')
local C = ffi.C

local syscache = require('pllj.pg.syscache')
local macro = require('pllj.pg.macro')

local __finfo = ffi.new('struct FunctionCallInfoData')
local function call_pg_variadic(f, PG_FUNCTION_ARGS)
    for i = 0, #PG_FUNCTION_ARGS -1 do
        __finfo.arg[i] = PG_FUNCTION_ARGS[i+1]
    end
    return f(__finfo)
end

local function find_lang_oid(str)
    local tuple = C.SearchSysCache(syscache.enum.LANGNAME, macro.CStringGetDatum(str), 0, 0, 0);
    if tuple == nil then
        return 0
    end
    local langtupoid = C.ljm_HeapTupleGetOid(tuple)
    C.ReleaseSysCache(tuple)
    return langtupoid
end

return { 
    find_lang_oid = find_lang_oid,
    call_pg_variadic = call_pg_variadic,
}