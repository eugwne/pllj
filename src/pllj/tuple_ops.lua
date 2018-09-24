local ffi = require('ffi')
local C = ffi.C
local to_lua = require('pllj.io').to_lua
local to_pg =require('pllj.io').to_pg
local NULL = ffi.NULL
local table_new = require('table.new')

local isNull = ffi.new("bool[?]", 1)
local function tuple_to_lua_1array(tupleDesc, tuple)
    local natts = tupleDesc.natts
    local row = table_new(natts, 0)
    
    for k = 0, natts-1 do
        local attnum = tupleDesc.attrs[k].attnum;
        local atttypid = tupleDesc.attrs[k].atttypid;
        --local val = C.SPI_getbinval(tuple, tupleDesc, k, isNull)
        --print(tuple, attnum, tupleDesc,  isNull)
        local val = C.pllj_heap_getattr(tuple, attnum, tupleDesc,  isNull)
        local not_null = isNull[0] == false
        if not_null then
            row[k+1] = to_lua(atttypid)(val)
        else
            row[k+1] = NULL
        end

    end
    return row
end


local function tuple_to_lua_table(tupleDesc, tuple)

    local natts = tupleDesc.natts
    local row = table_new(0, natts)
    
    for k = 0, natts-1 do
        local attr = tupleDesc.attrs[k]

        --local columnName =  (ffi.string(attname, C.NAMEDATALEN))
        local columnName =  (ffi.string(ffi.cast('const char *', attr.attname)))

        local value = C.pllj_heap_getattr(tuple, attr.attnum, tupleDesc,  isNull)
        local not_null = isNull[0] == false
        if not_null then
            row[columnName] = to_lua(attr.atttypid)(value)
        else
            row[columnName] = NULL
        end

    end
    return row
end

local function lua_table_to_tuple(tupleDesc, table)

    local natts = tupleDesc.natts
    local values = ffi.cast('Datum*', C.palloc(C.SIZEOF_DATUM * natts))
    local nulls = ffi.cast('bool*', C.palloc(C.SIZEOF_BOOL * natts))
    for k = 0, natts-1 do
        local attr = tupleDesc.attrs[k]
        if (attr.attisdropped) then
            values[k] = 0
            nulls[k] = true;

        else

            local key = (ffi.string(ffi.cast('const char *', attr.attname)))

            local iof = to_pg(attr.atttypid)
            local table_value = table[key]
            local isnull = (table_value == nil or table_value == NULL)

            if iof and not isnull then
                values[k] = iof(table_value)
                nulls[k] = false
            else
                values[k] = 0
                nulls[k] = true
            end
        end
    end

    local result = C.heap_form_tuple(tupleDesc, values, nulls)
    C.pfree(values)
    C.pfree(nulls)
    return result

end

return {
    tuple_to_lua_1array = tuple_to_lua_1array,
    tuple_to_lua_table = tuple_to_lua_table,
    lua_table_to_tuple = lua_table_to_tuple
}