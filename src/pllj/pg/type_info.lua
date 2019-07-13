local ffi = require('ffi')
local C = ffi.C
local NULL = ffi.NULL

local table_new = require('table.new')

local syscache = require('pllj.pg.syscache')
local macro = require('pllj.pg.macro')

local function get_oid_from_name(sptr)
    local typeId = ffi.new("Oid[?]", 1)
    local typmod = ffi.new("int32[?]", 1)
    C.parseTypeString(sptr, typeId, typmod, true)
    return tonumber(typeId[0])
end

local function tupdesc_info_copy(tupdesc)
    local prev = C.CurrentMemoryContext
    C.CurrentMemoryContext = C.TopMemoryContext

    local tuple_desc = ffi.gc(C.CreateTupleDescCopyConstr(tupdesc), C.pfree);
    C.CurrentMemoryContext = prev
    C.BlessTupleDesc(tuple_desc);
    

    local field_count = tuple_desc.natts
    local field_info = table_new(field_count, 0)
    local field_name_oid = table_new(0, field_count)
    for k = 0, field_count-1 do
        local attr = tuple_desc.attrs[k]
        local attname = (ffi.string(ffi.cast('const char *', attr.attname)))
        local atttypid = tonumber(attr.atttypid)
        table.insert(field_info, {
            attname, --1
            atttypid,
        });
        field_name_oid[attname] = atttypid
    end
    return {tuple_desc, field_info, field_count, field_name_oid}
end

local function get_pg_typeinfo(oid)
    local t = C.SearchSysCache(syscache.enum.TYPEOID, --[[ObjectIdGetDatum]] oid, 0, 0, 0);
    local form_pg_type = ffi.cast('Form_pg_type', macro.GETSTRUCT(t));
    local composite

    if (form_pg_type.typtype == C.TYPTYPE_COMPOSITE) then
        local tdesc = C.lookup_rowtype_tupdesc_noerror(oid, form_pg_type.typtypmod, true)
        if tdesc ~= NULL then
            composite = tupdesc_info_copy(tdesc)
            macro.ReleaseTupleDesc(tdesc);
        end

    end
    local result = {
        form_pg_type = form_pg_type,
        composite = composite,
        _free = function() C.ReleaseSysCache(t) end
    }

    return result;
end

return {
    get_oid_from_name = get_oid_from_name,
    get_pg_typeinfo = get_pg_typeinfo,
    tupdesc_info_copy = tupdesc_info_copy,
}
