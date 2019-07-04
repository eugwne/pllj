local ffi = require('ffi')
local C = ffi.C

 local __rtti = {}

 local get_pg_typeinfo = require('pllj.pg.type_info').get_pg_typeinfo

 local function get_rtti(oid)
    local found = __rtti[oid]
    if found then return found end 

    local typeinfo = get_pg_typeinfo(oid)
    local free = typeinfo._free;

    local form_pg_type = typeinfo.form_pg_type

    if form_pg_type.typtype == C.TYPTYPE_BASE then

        local in_out = ffi.new("FmgrInfo[?]", 2)
        C.fmgr_info_cxt(form_pg_type.typinput, in_out[0], C.TopMemoryContext);
        C.fmgr_info_cxt(form_pg_type.typoutput, in_out[1], C.TopMemoryContext);
        found = {
            [1] = oid,
            [2] = form_pg_type,
            [3] = in_out
        }
        __rtti[oid] = found


    elseif form_pg_type.typtype == C.TYPTYPE_COMPOSITE then


        local composite = typeinfo.composite 
        local tuple_desc = composite[1] 
        local field_info = composite[2]
        local field_count = composite[3]

        local in_out = ffi.new("FmgrInfo[?]", 2)
        C.fmgr_info_cxt(form_pg_type.typinput, in_out[0], C.TopMemoryContext);
        C.fmgr_info_cxt(form_pg_type.typoutput, in_out[1], C.TopMemoryContext);

        found = {
            [1] = oid,
            [2] = form_pg_type,
            [3] = in_out,
            [4] = {tuple_desc, field_info, field_count}
        }
        __rtti[oid] = found
    end
    free()
    return found


 end

 return {
    get_rtti = get_rtti
}
