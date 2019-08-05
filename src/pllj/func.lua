local ffi = require('ffi')
local C = ffi.C

local macro = require('pllj.pg.macro')
local syscache = require('pllj.pg.syscache')
local text_to_lua = require('pllj.type.text').to_lua
local text_to_pg = require('pllj.type.text').to_datum

local to_pg = require('pllj.io').to_pg
local to_lua = require('pllj.io').to_lua
local call_pg_c_variadic = require('pllj.pg.func').call_pg_c_variadic
local find_lang_name = require('pllj.pg.func').find_lang_name
local pg_error = require('pllj.pg.pg_error')

local Deferred = require('pllj.misc').Deferred

local env = require('pllj.env').env
local env_add = require('pllj.env').add

local function get_func_from_oid(oid)
    local isNull = ffi.new("bool[?]", 1)
    local proc = C.SearchSysCache(syscache.enum.PROCOID, macro.ObjectIdGetDatum(oid), 0, 0, 0);

    local procst = ffi.cast('Form_pg_proc', macro.GETSTRUCT(proc));

    local nargs = procst.pronargs;
    local argtypes = procst.proargtypes.values;
    local prorettype = procst.prorettype;
    local result_isset = procst.proretset;
    local readonly = (procst.provolatile ~= C.PROVOLATILE_VOLATILE)

    local arguments = ''
    local targtypes = {}
    local proname = ffi.string(procst.proname.data) --'anonymous'

    if nargs > 0 then

        local argtypes
            , argnames
            , argmodes
            , argc

        argtypes = ffi.new("Oid *[?]", 1)
        argnames = ffi.new("char **[?]", 1)
        argmodes = ffi.new("char *[?]", 1)
        argc = C.get_func_arg_info(proc, argtypes, argnames, argmodes);
        
        if argmodes[0] == nil then
            nargs = argc
        else
            nargs = 0
            for i = 0, argc-1 do
                if argmodes[0][i] ~= string.byte('o') and argmodes[0][i] ~= string.byte('t')  then 
                    --PROARGMODE_OUT && PROARGMODE_TABLE
                    nargs = nargs + 1
                end
            end
        end
        local targ = {}
        local ttypes = {}
        local idx = 0
        --TODO ?
        local vararg = false
        for i = 0, argc-1 do
            if not (argmodes[0] ~= nil and (argmodes[0][i] == string.byte('o') or argmodes[0][i] == string.byte('t')))  then 
                local arg = ffi.string(argnames[0][idx])

                if #arg == 0 then
                    vararg = true
                    break
                end

                local oid = argtypes[0][idx]

                table.insert(targ, arg)
                table.insert(ttypes, tonumber(oid))
                idx = idx + 1
            end
        end

        arguments = '...'
        if not vararg then
            arguments = table.concat(targ, ', ')
            targtypes = ttypes
        end

    end

    local prosrc = C.SysCacheGetAttr(syscache.enum.PROCOID, proc, C.Anum_pg_proc_prosrc, isNull);
    prosrc = text_to_lua(prosrc)
    if (isNull[0] == true) then
        return nil, ("null prosrc for function " .. oid);
    end

    local fntext = {
        'local ', proname, '\n', proname, ' = function (', arguments, ')\n',
        prosrc, '\nend\nreturn ', proname
    }

    fntext = table.concat(fntext)

    local xmin = tonumber(macro.HeapTupleHeaderGetXmin(proc.t_data))
    local tid = proc.t_self;
    local user_id = C.GetUserId()

    C.ReleaseSysCache(proc)

    local fn, err = loadstring(fntext, nil, "t", env)

    if not fn then
        return nil, ({ message = err, context = fntext })
    end


    return {
        func = fn(),
        xmin = xmin,
        tid = tid,
        user_id = user_id,
        result_isset = result_isset,
        prorettype = prorettype,
        argtypes = targtypes,
        oid = oid,
        readonly = readonly,
        --__fntext = fntext
    }
end

local function need_update(cached)
    if not cached then
        return true
    end

    local oid = cached.oid
    --TODO cache function for userid
    local user_id = C.GetUserId()

    if user_id ~= cached.user_id then
        return true
    end

    local proc = C.SearchSysCache(syscache.enum.PROCOID, macro.ObjectIdGetDatum(oid), 0, 0, 0)
    local xmin = tonumber(macro.HeapTupleHeaderGetXmin(proc.t_data))
    local tid = proc.t_self;

    if xmin ~= cached.xmin or tid ~= cached.tid then
        C.ReleaseSysCache(proc)
        return true
    end

    C.ReleaseSysCache(proc)
    return false
end

local function set_memorycontext(m)
    C.CurrentMemoryContext = m
end

local function gc_check_callback(raw)
    local finfo = ffi.cast('FunctionCallInfo', raw)
    local resultinfo = finfo.resultinfo
    if resultinfo ~= nil then 
        resultinfo = ffi.cast('ReturnSetInfo*', resultinfo)
        local ecxt_callback = resultinfo.econtext.ecxt_callbacks
        if ecxt_callback ~= nil then
            ecxt_callback['function'](ecxt_callback.arg)
        end
    end
    C.pfree(raw)
end

local FunctionCallInfo_create
local strict_init_args
local not_strict_init_args
if --[[------------------------------------------------------------]] C.PG_VERSION_NUM >= 120000 then
    strict_init_args = function(args, argc, argtypes, info, argmodes)
        for i = 0, argc - 1 do
            local ref_arg = info.args[i]
            ref_arg.value,  ref_arg.isnull = to_pg(argtypes[0][i])(args[i+1])
            if ref_arg.isnull == true then 
                if not (argmodes[0] ~= nil and argmodes[0][i] == string.byte('o')) then
                    return error('strict function null arg['..tostring(i)..']') 
                end
            end
        end
    end

    not_strict_init_args = function(args, argc, argtypes, info)
        for i = 0, argc - 1 do
            info.args[i].value,  info.args[i].isnull = to_pg(argtypes[0][i])(args[i+1])
        end
    end

    FunctionCallInfo_create = function(argc)
        local raw = top_alloc(macro.SizeForFunctionCallInfo(argc)) --ffi.new('char[?]', macro.SizeForFunctionCallInfo(argc))
        local finfo = ffi.gc(ffi.cast('FunctionCallInfo', raw), gc_check_callback)
        return finfo
    end

elseif --[[------------------------------------------------------------]] C.PG_VERSION_NUM < 120000 then
    strict_init_args = function(args, argc, argtypes, info)
        ffi.fill(info.argnull, argc)
        for i = 0, argc - 1 do
            info.arg[i], info.argnull[i] = to_pg(argtypes[0][i])(args[i+1])
            if info.argnull[i] == true then 
                if not (argmodes[0] ~= nil and argmodes[0][i] == string.byte('o')) then
                    return error('strict function null arg['..tostring(i)..']') 
                end
            end
        end
    end

    not_strict_init_args = function(args, argc, argtypes, info)
        ffi.fill(info.argnull, argc)
        for i = 0, argc - 1 do
            info.arg[i], info.argnull[i] = to_pg(argtypes[0][i])(args[i+1])
        end
    end

    FunctionCallInfo_create = function(argc)
        local raw = top_alloc(ffi.sizeof('struct FunctionCallInfoData'))
        local finfo = ffi.gc(ffi.cast('FunctionCallInfo', raw), gc_check_callback)
        return finfo
    end
end

local function init_arguments(strict)
    if strict then
        return strict_init_args
    else
        return not_strict_init_args
    end
end


local enum_NodeTag = ffi.new('struct enum_NodeTag');
local function srf_result_info_new()
                    
    local fcontext = ffi.new('pgfunc_srf')
    ffi.fill(fcontext.econtext, ffi.sizeof('ExprContext'))
    fcontext.econtext.ecxt_per_query_memory = C.CurrentMemoryContext;
    local rsinfo = fcontext.rsinfo;
    rsinfo.type = enum_NodeTag.T_ReturnSetInfo;
    rsinfo.econtext = fcontext.econtext;
    rsinfo.allowedModes = 1; --SFRM_ValuePerCall
    rsinfo.returnMode = 1; --SFRM_ValuePerCall;
    rsinfo.setResult = nil;
    rsinfo.setDesc = nil;

    return fcontext
end

local function find_function( value, opt )
    local prev = C.CurrentMemoryContext
    local d = Deferred.create()
    local opt = opt or {}
    local funcoid = C.InvalidOid

    local error_text
        , reg_name
        , argtypes
        , argnames
        , argmodes
        , argc
        , finfo
        , func
        , prorettype
        , fn_init_args
    local fmgrInfo = 0
    local _isok
    if type(value) == 'number' then
        funcoid = value
    elseif type(value) == 'string' then
        reg_name = value
        --this needs try catch:
        --funcoid = tonumber(macro.DatumGetObjectId(C.DirectFunctionCall1Coll(C.regprocedurein, 0, macro.CStringGetDatum(value))));
        funcoid = tonumber(macro.DatumGetObjectId(call_pg_c_variadic(C.to_regprocedure, {text_to_pg(value)})));
    end
    if funcoid == C.InvalidOid then
        if reg_name then
            return error("failed to register ".. reg_name);
        end
        return error("failed to register function with oid ".. funcoid);
    end

    local proc = C.SearchSysCache(syscache.enum.PROCOID, macro.ObjectIdGetDatum(funcoid), 0, 0, 0);

    -- body
    if proc == nil then --cdata ptr
        return error("cache lookup failed for function ".. funcoid);
    end
    ---no throw_error, only goto fail----------------------------------------------------------------------
    d:add {C.ReleaseSysCache, proc} 

    local procst = ffi.cast('Form_pg_proc', macro.GETSTRUCT(proc));

    local luasrc = (find_lang_name(procst.prolang) == 'pllj')
    if luasrc then
        error_text = "luasrc NYI";
        goto fail
    end

    if ( opt.only_internal and (procst.prolang ~= C.INTERNALlanguageId) and( not luasrc) ) then
        error_text = "supported only SQL/internal functions";
        goto fail
    end
    prorettype = procst.prorettype
    
    C.CurrentMemoryContext = C.TopMemoryContext
    d:add {set_memorycontext, prev} 

    argtypes = ffi.new("Oid *[?]", 1)
    argnames = ffi.new("char **[?]", 1)
    argmodes = ffi.new("char *[?]", 1)
    
    argc = C.get_func_arg_info(proc, argtypes, argnames, argmodes);

    if not procst.proretset then
        fmgrInfo = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(funcoid, fmgrInfo, C.CurrentMemoryContext);
        fn_init_args = init_arguments(fmgrInfo[0].fn_strict == true)
        finfo = FunctionCallInfo_create(argc)

        _isok = ffi.new("bool[?]", 1)
        func = function(...)
            local args = {...}

            macro.InitFunctionCallInfoData(finfo, fmgrInfo, argc, C.InvalidOid, nil, nil)
            fn_init_args(args, argc, argtypes, finfo, argmodes)

            _isok[0] = true
            local result = imported.FunctionCallInvoke(finfo, _isok)
            if _isok[0] == false then
                local e = pg_error.get_exception_text()
                return error("exec[".. (reg_name or funcoid).."] error:"..e)
            end
            if finfo.isnull == true then
                return nil
            end
            return to_lua(prorettype)(result)

        end
    else

        func = function(...)

            local finfo = FunctionCallInfo_create(argc)

            local fmgrInfo = ffi.new("FmgrInfo[?]", 1)
            C.fmgr_info_cxt(funcoid, fmgrInfo, C.CurrentMemoryContext);
            local fn_init_args = init_arguments(fmgrInfo[0].fn_strict == true)

            local args = {...}
            local result_info = srf_result_info_new()

            macro.InitFunctionCallInfoData(finfo, fmgrInfo, argc, C.InvalidOid, nil
                , ffi.cast('struct Node *', result_info.rsinfo))
            fn_init_args(args, argc, argtypes, finfo, argmodes)

            local _isok = ffi.new("bool[?]", 1)
            local iter = function()

                _isok[0] = true
                local result = imported.FunctionCallInvoke(finfo, _isok)
                if _isok[0] == false then
                    local e = pg_error.get_exception_text()
                    return error("exec[".. (reg_name or funcoid).."] error:"..e)
                end

                if result_info.rsinfo.isDone == 2 then --ExprEndResult = 2,
                    return nil
                end
                if finfo.isnull == true then
                    return NULL
                end
                return to_lua(prorettype)(result)
            end
            return iter

        end

    end


    do
        d:call()
        return func
    end

    ::fail:: 
    do
        d:call()
        return error(error_text)
    end

end
env_add("find_function", find_function)

--TODO: change it
local _saved_functions = {}

local function load_function(value)
    local found = _saved_functions[value]
    if found then return found end
    local result = find_function(value, opt)
    _saved_functions[value] = result
    return result
end
env_add("load_function", load_function)


return {
    find_function = find_function,
    get_func_from_oid = get_func_from_oid,
    need_update = need_update,
    load_function = load_function,
}
