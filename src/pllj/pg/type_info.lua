local ffi = require('ffi')
local C = ffi.C
require('pllj.pg.init_c')

local syscache = require('pllj.pg.syscache')
local macro = require('pllj.pg.macro')

local function get_oid_from_name(sptr)
    local typeId = ffi.new("Oid[?]", 1)
    local typmod = ffi.new("int32[?]", 1)
    C.parseTypeString(sptr, typeId, typmod, true)
    return tonumber(typeId[0])
end

local function get_pg_typeinfo(oid)
    local t = C.SearchSysCache(syscache.enum.TYPEOID, --[[ObjectIdGetDatum]] oid, 0, 0, 0);
    local tstruct = ffi.cast('Form_pg_type', macro.GETSTRUCT(t));
    --    local result = {
    --        typlen = tstruct.typlen,
    --        typtype = tstruct.typtype,
    --        typalign = tstruct.typalign,
    --        typbyval = tstruct.typbyval,
    --        typelem = tstruct.typelem,
    --        typinput = tstruct.typinput,
    --        typoutput = tstruct.typoutput
    --    }
    if (tstruct.typtype == C.TYPTYPE_COMPOSITE) then
        print('TODO')
    end
    local result = {
        data = tstruct,
        _free = function() C.ReleaseSysCache(t) end
    }

    return result;
end

return {
    get_oid_from_name = get_oid_from_name,
    get_pg_typeinfo = get_pg_typeinfo
}

