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
    local rettype = procst.prorettype;
    local result_isset = procst.proretset;
    local readonly = (procst.provolatile ~= C.PROVOLATILE_VOLATILE)

    local arguments = ''
    local targtypes = {}
    local proname = ffi.string(procst.proname.data) --'anonymous'

    if nargs > 0 then
        local vararg = false
        local nnames = ffi.new("int[?]", 1)
        local argnames = C.SysCacheGetAttr(syscache.enum.PROCOID, proc,
            C.Anum_pg_proc_proargnames, isNull)
        if isNull[0] == false then
            local argname = ffi.new 'Datum *[1]'
            C.deconstruct_array(macro.DatumGetArrayTypeP(argnames), C.TEXTOID, -1, false,
                string.byte('i'), argname, nil, nnames)

            vararg = (nargs ~= nnames[0])
            local targ = {}
            local ttypes = {}
            if not vararg then
                for i = 0, nnames[0] - 1 do
                    local arg = text_to_lua(argname[0][i])
                    table.insert(targ, arg)
                    table.insert(ttypes, tonumber(argtypes[i]))

                    if #arg == 0 then
                        vararg = true
                        break
                    end
                end
            end

            arguments = '...'
            if not vararg then
                arguments = table.concat(targ, ', ')
                targtypes = ttypes
            end
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
        result_type = rettype,
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
        , init_args
        , prorettype
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

    if (procst.proretset) then
        error_text = "proretset NYI" 
        goto fail
    else
        fmgrInfo = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(funcoid, fmgrInfo, C.CurrentMemoryContext);
    end

    
    if C.PG_VERSION_NUM >= 120000 then
        --TODO argc
        local mem
        if argc == 0 then
            mem = ffi.new('LOCAL_FCINFO_0[1]')
        elseif argc == 1 then
            mem = ffi.new('LOCAL_FCINFO_1[1]')
        elseif argc == 2 then
            mem = ffi.new('LOCAL_FCINFO_2[1]')
        elseif argc == 3 then
            mem = ffi.new('LOCAL_FCINFO_3[1]')
        else
            mem = ffi.new('FCInfoMax[1]')
        end
        local fcinfo = mem[0].fcinfo
        finfo = ffi.cast('FunctionCallInfo', mem)
        if fmgrInfo[0].fn_strict == true then
            init_args = function(args)
                local ref_arg = fcinfo.args[i]
                for i = 0, argc - 1 do
                    ref_arg.value,  ref_arg.isnull = to_pg(argtypes[0][i])(args[i+1])
                    if ref_arg.isnull == true then return error('strict function null arg['..tostring(i)..']') end
                end
            end
        else
            init_args = function(args)
                for i = 0, argc - 1 do
                    fcinfo.args[i].value,  fcinfo.args[i].isnull = to_pg(argtypes[0][i])(args[i+1])
                end
            end
        end
    else --C.PG_VERSION_NUM < 120000
        finfo = ffi.new('struct FunctionCallInfoData')
        if fmgrInfo[0].fn_strict == true then
            init_args = function(args)
                ffi.fill(finfo.argnull, argc)
                for i = 0, argc - 1 do
                    finfo.arg[i], finfo.argnull[i] = to_pg(argtypes[0][i])(args[i+1])
                    if finfo.argnull[i] == true then return error('strict function null arg['..tostring(i)..']') end
                end
            end
        else
            init_args = function(args)
                ffi.fill(finfo.argnull, argc)
                for i = 0, argc - 1 do
                    finfo.arg[i], finfo.argnull[i] = to_pg(argtypes[0][i])(args[i+1])
                end
            end
        end
    end
    
    

    
    _isok = ffi.new("bool[?]", 1)
    func = function(...)
        local args = {...}
        macro.InitFunctionCallInfoData(finfo, fmgrInfo, argc, C.InvalidOid, nil, nil)
        init_args(args)

        --macro has no try catch
        --local result = macro.FunctionCallInvoke(finfo)
        _isok[0] = true
        local result = C.ljm_SPIFunctionCallInvoke(finfo, _isok)
        if _isok[0] == false then
            local e = pg_error.get_exception_text()
            return error("exec[".. (reg_name or funcoid).."] error:"..e)
        end
        if finfo.isnull == true then
            return nil
        end
        return to_lua(prorettype)(result)

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
