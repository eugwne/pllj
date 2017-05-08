local ffi = require('ffi')
local C = ffi.C
require('pllj.pg.init_c')

local macro = require('pllj.pg.macro')
local syscache = require('pllj.pg.syscache')
local text_to_lua = require('pllj.pg.to_lua').typeto[C.TEXTOID]

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


return {
    get_func_from_oid = get_func_from_oid,
    need_update = need_update
}