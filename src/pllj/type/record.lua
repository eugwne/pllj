local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')
--local tupdesc_info_copy = require('pllj.pg.type_info').tupdesc_info_copy
local tuple_to_lua_table = require('pllj.tuple_ops').tuple_to_lua_table
local macro = require('pllj.pg.macro')
local lua_1array_to_tuple = require('pllj.tuple_ops').lua_1array_to_tuple

return { 

    oid = C.RECORDOID,

    to_lua = function(datum)
        local header = ffi.cast('HeapTupleHeader', macro.PG_DETOAST_DATUM(datum))
        local oid = macro.HeapTupleHeaderGetTypeId(header) 
        local typtypmod = macro.HeapTupleHeaderGetTypMod(header)

        local tdesc = C.lookup_rowtype_tupdesc_noerror(oid, typtypmod, true)

        local tuple = ffi.new('HeapTupleData');
        tuple.t_len = macro.HeapTupleHeaderGetDatumLength(header);
        tuple.t_tableOid = C.InvalidOid;
        tuple.t_data = header;
        C.ljm_ItemPointerSetInvalid(tuple.t_self);
 
        local row = tuple_to_lua_table(tdesc, tuple)
        macro.ReleaseTupleDesc(tdesc);

        return row

    end,

    to_datum = function(lv, tuple_desc)
        if (lv == NULL) then
            return ffi.cast('Datum', 0), true
        end

        local datum = C.HeapTupleHeaderGetDatum(
                            C.SPI_copytuple(lua_1array_to_tuple(tuple_desc, lv)).t_data
                        )

        return datum, false
    end,

}
