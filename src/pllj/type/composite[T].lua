local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')
local NULL = ffi.NULL
local pg_error = require('pllj.pg.pg_error')

local lua_table_to_tuple_2 = require('pllj.tuple_ops').lua_table_to_tuple_2
local table_new = require('table.new')
--TODO remake
local _private = require('pllj.misc').private

local isNull = ffi.new("bool[?]", 1)

local get_rtti = require('pllj.type.rtti').get_rtti

local to_lua
local function set_io(io)
    to_lua = assert(io.to_lua)
end

local string_to_rawdatum_rtti
local function set_datum_ops(ops)
    string_to_rawdatum_rtti = assert(ops.string_to_rawdatum_rtti)
end


local typtype_composite_mt 

local mm__composite_tostring
local mm__composite_index
local mm__composite_newindex


local function composite_unbox(self)
    local composite = rawget(self, -3)
    local rtti = rawget(self, -2)
    local fields_info = rtti[4][2]
    local field_values = composite[1]
    local size = rtti[4][3]
    local t = table_new(0, size)
    local t2 = table_new(0, size)
    for i = 1, size do
        local attname = fields_info[i][1]
        local atttypid = fields_info[i][2]

        local value = field_values[i][1]
        local isnull = field_values[i][2]
        t[attname] = isnull and NULL or to_lua(atttypid)(value)
        t2[attname] = t[attname]
    end
    composite[1] = nil
    composite[2] = {t, t2}
end

local composite_to_datum
composite_to_datum = function (self)
    local rtti = rawget(self, -2)
    local composite = rawget(self, -3)
    local updated = false
    local fields_info = rtti[4][2]
    local pair_old_new = composite[2]
    if not pair_old_new then
        return rawget(self, -1)
    end
    local size = rtti[4][3]
    local t = pair_old_new[1]
    local t2 = pair_old_new[2]
    for i = 1, size do
        local attname = fields_info[i][1]
        local atttypid = fields_info[i][2]
        local old_value = t[attname]
        local new_value = t2[attname]
        if old_value ~= new_value then
            updated = true
        end
        if (type(new_value) == "table") and rawget(new_value, -3) then
            --TODO check if old or new is NULL
            local datum = composite_to_datum(new_value)
            rawset(new_value, -1, datum)
            updated = true
        end
    end
    if updated then
        local tuple_desc = rtti[4][1]

        rawset(self, -1, C.HeapTupleHeaderGetDatum(
                    C.SPI_copytuple(lua_table_to_tuple_2(tuple_desc, t2, fields_info)).t_data
                ))
    end

    return rawget(self, -1)
end

local function table_to_datum_rtti(value, rtti)
    assert(type(value) == "table")
    local tuple_desc = rtti[4][1]
    local fields_info = rtti[4][2]
    local datum = C.HeapTupleHeaderGetDatum(
        C.SPI_copytuple(lua_table_to_tuple_2(tuple_desc, value, fields_info)).t_data
    )
    return datum
end


local untrusted_composite_index = function(self, key)

    local composite = rawget(self, -3)
    
    if not composite[2] then
        composite_unbox(self)
    end
    return composite[2][2][key]
end

local untrusted_composite_newindex = function(self, key, value)

    local composite = rawget(self, -3)

    if not composite[2] then
        composite_unbox(self)
    end
    local rtti = rawget(self, -2)
    local field_name_oid = rtti[4][4]

    local foid = field_name_oid[key]
    local field_rtti = get_rtti(foid)
    if (field_rtti[4]) then
        if type(value) == "string" then
            local datum = string_to_rawdatum_rtti(field_rtti, value)
            value = to_lua(foid)(datum)
        end
        if type(value) == "table" then
            local rtti = rawget(value, -2)
            if not rtti then
                local datum = table_to_datum_rtti(value, field_rtti)
                value = to_lua(foid)(datum)
            end
        end
        --TODO composite assign other types
        
    end
    composite[2][2][key] = value
end

if __untrusted__ then
    mm__composite_tostring = function(self)
        local value = self
        local datum = composite_to_datum(value)
        local rtti = rawget(value, -2)
        local charPtr = C.OutputFunctionCall(rtti[3][1], datum)
        return ffi.string(charPtr)
    end

    mm__composite_index = untrusted_composite_index

    mm__composite_newindex = untrusted_composite_newindex

else ----------TRUSTED


    mm__composite_tostring = function(self)
        local value = _private[self]
        local datum = composite_to_datum(value)
        local rtti = rawget(value, -2)
        local charPtr = C.OutputFunctionCall(rtti[3][1], datum)
        return ffi.string(charPtr)
    end

    mm__composite_index = function(self, key)
        local value = _private[self]
        return untrusted_composite_index(value, key)
    end

    mm__composite_newindex = function(self, key, value)
        local obj = _private[self]
        return untrusted_composite_newindex(obj, key, value)
    end

end

typtype_composite_mt = {
    __tostring = mm__composite_tostring,
    __index = mm__composite_index,
    __newindex = mm__composite_newindex,
}

local function to_lua_T(T)
    local oid = assert(T.oid)
    local rtti = get_rtti(oid)
    
    local form_pg_type = rtti[2]
    local result

    assert(form_pg_type.typtype == C.TYPTYPE_COMPOSITE)

    local field_count = rtti[4][3]

    result = function (datum)

        local field_values = table_new(field_count, 0)
        local tup = ffi.cast('HeapTupleHeader', macro.PG_DETOAST_DATUM(datum))

        for k = 1, field_count do
            local value = C.GetAttributeByNum(tup, k, isNull)
            local item = (isNull[0] == false) and value or NULL
            table.insert(field_values, {item, isNull[0]})
        end

        return {
            [-1] = datum,
            [-2] = rtti,
            [-3] = {field_values, nil} 
        }

    end

    return result, typtype_composite_mt
end

return {
    unbox = composite_unbox,
    to_datum = composite_to_datum,
    mt = typtype_composite_mt,
    to_lua_T = to_lua_T,
    table_to_datum_rtti = table_to_datum_rtti,

    set_io = set_io,
    set_datum_ops = set_datum_ops,
}
