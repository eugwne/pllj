local ffi = require('ffi')
local C = ffi.C
local to_lua = require('pllj.io').to_lua
local NULL = require('pllj.pg.c').NULL

local isNull = ffi.new("bool[?]", 1)
local function tuple_to_lua_1array(tupleDesc, tuple)
        local row = {}
        local natts = tupleDesc.natts
        for k = 0, natts-1 do
            --local attname = tupleDesc.attrs[k].attname;
            --local columnName =  (ffi.string(attname, NAMEDATALEN))
            local attnum = tupleDesc.attrs[k].attnum;
            local atttypid = tupleDesc.attrs[k].atttypid;
            --local val = C.SPI_getbinval(tuple, tupleDesc, k, isNull)
            --print(tuple, attnum, tupleDesc,  isNull)
            local val = C.pllj_heap_getattr(tuple, attnum, tupleDesc,  isNull)
            val = to_lua(atttypid)(val)

            row[k+1] = isNull[0] == false and val or NULL

        end
        return row
end


local function tuple_to_lua_table(tupleDesc, tuple)
    local row = {}
    local natts = tupleDesc.natts
    for k = 0, natts-1 do
        local attname = tupleDesc.attrs[k].attname;
        --local columnName =  (ffi.string(attname, C.NAMEDATALEN))
        local columnName =  (ffi.string(ffi.cast('const char *', attname)))

        local attnum = tupleDesc.attrs[k].attnum;
        local atttypid = tupleDesc.attrs[k].atttypid;

        local val = C.pllj_heap_getattr(tuple, attnum, tupleDesc,  isNull)
        val = to_lua(atttypid)(val)

        row[columnName] = isNull[0] == false and val or NULL

    end
    return row
end

return {
    tuple_to_lua_1array = tuple_to_lua_1array,
    tuple_to_lua_table = tuple_to_lua_table
}