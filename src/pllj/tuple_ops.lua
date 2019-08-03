local ffi = require('ffi')
local C = ffi.C
local NULL = ffi.NULL
local table_new = require('table.new')

local to_lua
local to_pg
local function set_io(io)
    to_lua = assert(io.to_lua)
    to_pg = assert(io.to_pg)
end

local isNull = ffi.new("bool[?]", 1)
local function tuple_to_lua_1array(tupleDesc, tuple)
    local natts = tupleDesc.natts
    local row = table_new(natts, 0)
    
    for k = 0, natts-1 do
        local attr = tupleDesc.attrs[k]

        local val = imported.heap_getattr(tuple, attr.attnum, tupleDesc,  isNull)
        local not_null = isNull[0] == false
        if not_null then
            row[k+1] = to_lua(attr.atttypid)(val)
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

        local columnName =  (ffi.string(ffi.cast('const char *', attr.attname)))

        local value = imported.heap_getattr(tuple, attr.attnum, tupleDesc,  isNull)
        local not_null = isNull[0] == false
        if not_null then
            row[columnName] = to_lua(attr.atttypid)(value)
        else
            row[columnName] = NULL
        end

    end
    return row
end


local function table_to_tuple(getter, tupleDesc, table, field_info)

    local natts = tonumber(tupleDesc.natts)
    local values = ffi.cast('Datum*', C.palloc(C.SIZEOF_DATUM * natts))
    local nulls = ffi.cast('bool*', C.palloc(C.SIZEOF_BOOL * natts))
    local attrs = tupleDesc.attrs
    for k = 0, natts-1 do
        local attr = attrs[k]
        if (attr.attisdropped) then
            values[k] = 0
            nulls[k] = true;
        else

            local table_value, atttypid = getter(table, k, attr, field_info)
            local iof = to_pg(atttypid)
            local isnull = (table_value == nil)

            if iof and not isnull then
                values[k], isnull = iof(table_value)
                nulls[k] = isnull or false
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

local function get_array_value(table, cindex, attr)
    return table[cindex+1], attr.atttypid
end

local function get_table_value(table, cindex, attr)
    local key = (ffi.string(ffi.cast('const char *', attr.attname)))
    return table[key], attr.atttypid
end

local function get_table_value_info(table, cindex, attr, field_info)
    local field = field_info[cindex+1]
    local key = field[1]
    local atttypid = field[2]
    return table[key], atttypid
end

local function lua_table_to_tuple(tupleDesc, table)
    return table_to_tuple(get_table_value, tupleDesc, table)
end

local function lua_1array_to_tuple(tupleDesc, table)
    return table_to_tuple(get_array_value, tupleDesc, table)
end

local function lua_table_to_tuple_2(tupleDesc, table, field_info)
    return table_to_tuple(get_table_value_info, tupleDesc, table, field_info)
end

return {
    tuple_to_lua_1array = tuple_to_lua_1array,
    tuple_to_lua_table = tuple_to_lua_table,
    lua_table_to_tuple = lua_table_to_tuple,
    lua_table_to_tuple_2 = lua_table_to_tuple_2,
    lua_1array_to_tuple = lua_1array_to_tuple,
    set_io = set_io,
}
