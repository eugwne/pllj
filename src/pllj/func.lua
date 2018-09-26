local ffi = require('ffi')
local C = ffi.C

local macro = require('pllj.pg.macro')
local syscache = require('pllj.pg.syscache')
local text_to_lua = require('pllj.pg.to_lua').typeto[C.TEXTOID]
local text_to_pg = require('pllj.pg.to_pg').datumfor[C.TEXTOID]

local to_pg = require('pllj.io').to_pg
local to_lua = require('pllj.io').to_lua
local call_pg_variadic = require('pllj.pg.func').call_pg_variadic
local lj_lang_oid = require('pllj.pg.func').find_lang_oid('pllj')
local make_cleanup = require('pllj.misc').execute_list

local Deferred = require('pllj.misc').Deferred

local throw_error = require('pllj.spi').throw_error

local function get_func_from_oid(oid)
    local isNull = ffi.new("bool[?]", 1)
    local proc = C.SearchSysCache(syscache.enum.PROCOID, macro.ObjectIdGetDatum(oid), 0, 0, 0);

    local procst = ffi.cast('Form_pg_proc', macro.GETSTRUCT(proc));

    local nargs = procst.pronargs;
    local argtypes = procst.proargtypes.values;
    local rettype = procst.prorettype;
    local result_isset = procst.proretset;
    --  print(procst)
    --  print(argtypes)
    --  print(nargs)
    --  print('rettype  '..rettype)

    --  for i = 0, nargs-1 do
    --    print('argtype '..tostring(argtypes[i]))
    --    get_pg_typeinfo(argtypes[i])
    --  end
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
            --proname = ffi.string(procst.proname.data)

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

    local fn, err = loadstring(fntext)

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
        --__fntext = fntext
    }
end

local function need_update(cached)
    if not cached then
        return true
    end

    local oid = cached.oid
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
    local error_text
    local d = Deferred.create()
    local opt = opt or {}
    local funcoid = C.InvalidOid
    local reg_name
    local argtypes, argnames, argmodes, argc, lf, finfo, func
    if type(value) == 'number' then
        funcoid = value
    elseif type(value) == 'string' then
        reg_name = value
        --this needs try catch:
        --funcoid = tonumber(macro.DatumGetObjectId(C.DirectFunctionCall1Coll(C.regprocedurein, 0, macro.CStringGetDatum(value))));
        funcoid = tonumber(macro.DatumGetObjectId(call_pg_variadic(C.to_regprocedure, {text_to_pg(value)})));
    end
    if funcoid == C.InvalidOid then
        if reg_name then
            return throw_error("failed to register ".. reg_name);
        end
        return throw_error("failed to register function with oid ".. funcoid);
    end

    local proc = C.SearchSysCache(syscache.enum.PROCOID, macro.ObjectIdGetDatum(funcoid), 0, 0, 0);

    -- body
    if proc == nil then --cdata ptr
        return throw_error("cache lookup failed for function ".. funcoid);
    end
    ---no throw_error, only goto fail----------------------------------------------------------------------
    d:add {C.ReleaseSysCache, proc} 

    local procst = ffi.cast('Form_pg_proc', macro.GETSTRUCT(proc));

    local luasrc = (procst.prolang == lj_lang_oid)
    if luasrc then
        error_text = "luasrc NYI";
        goto fail
    end

    if ( opt.only_internal and (procst.prolang ~= INTERNALlanguageId) and( not luasrc) ) then
        error_text = "supported only SQL/internal functions";
        goto fail
    end

    
    C.CurrentMemoryContext = C.TopMemoryContext
    d:add {set_memorycontext, prev} 

    argtypes = ffi.new("Oid *[?]", 1)
    argnames = ffi.new("char **[?]", 1)
    argmodes = ffi.new("char *[?]", 1)
    
    argc = C.get_func_arg_info(proc, argtypes, argnames, argmodes);

    lf = {
        prorettype = procst.prorettype,
        funcoid = funcoid,
        options = opt,
        fi = 0,
        argc = argc
    }

    if (procst.proretset) then
        error_text = "proretset NYI" 
        goto fail
    else
        local fi = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(funcoid, fi, C.CurrentMemoryContext);
        lf.fi = fi
    end

    finfo = ffi.new('struct FunctionCallInfoData')
    
    func = function(...)
        macro.InitFunctionCallInfoData(finfo, lf.fi, argc, C.InvalidOid, nil, nil)
        for i = 0, lf.argc - 1 do
            local value = select(i+1, ...)
            finfo.arg[i] = to_pg(argtypes[0][i])(value, finfo.argnull, i)
        end

        --TODO: try catch
        local result = macro.FunctionCallInvoke(finfo)
        if finfo.isnull == true then
            return nil
        end
        return to_lua(lf.prorettype)(result)

    end


    do
        d:call()
        return func
    end

    ::fail:: 
    do
        d:call()
        return throw_error(error_text)
    end

end


return {
    find_function = find_function,
    get_func_from_oid = get_func_from_oid,
    need_update = need_update
}