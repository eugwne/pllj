local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')
local NULL = ffi.NULL

local pg_error = require('pllj.pg.pg_error')


local composite_t = require('pllj.type.composite[T]')

local get_rtti = require('pllj.type.rtti').get_rtti

local _private = require('pllj.misc').private

local typtype_base_mt


local wrap_datum
local unwrap_datum
local mm__tostring

if __untrusted__ then
    mm__tostring = function(self)
        local value = self
        local rtti = rawget(value, -2)
        local charPtr = C.OutputFunctionCall(rtti[3][1], rawget(value, -1))
        return ffi.string(charPtr)
    end

    wrap_datum = function(obj, mt)
        setmetatable(obj, mt)
        return obj
    end
    unwrap_datum = function(obj)
        return obj
    end
else ----------TRUSTED
    mm__tostring = function(self)
        local value = _private[self]
        local rtti = rawget(value, -2)
        local charPtr = C.OutputFunctionCall(rtti[3][1], rawget(value, -1))
        return ffi.string(charPtr)
    end

    wrap_datum = function(self, mt)
        local value = {}
        _private[value] = self
        setmetatable(value, mt)
        return value
    end
    unwrap_datum = function(self)
        return _private[self]
    end
end

typtype_base_mt = {
    __tostring = mm__tostring
}


local function to_lua_T(T)
    local oid = assert(T.oid)
    local rtti = get_rtti(oid)

    local form_pg_type = rtti[2]
    local result
    if form_pg_type.typtype == C.TYPTYPE_BASE then

        result = function (datum)

            return wrap_datum({
                [-1] = datum,
                [-2] = rtti,
            }, typtype_base_mt)
        end

    elseif form_pg_type.typtype == C.TYPTYPE_COMPOSITE then
        local to_lua, mt = composite_t.to_lua_T({oid = oid})
        result = function(datum)
            return wrap_datum(to_lua(datum), mt)
        end
    end

    return result
end 

local function string_to_rawdatum_rtti(rtti, value)
    local form_pg_type = rtti[2]
    assert (type(value) == "string")
    local inoid = rtti[1]
    if form_pg_type.typelem ~=0 then
        inoid = form_pg_type.typelem
    end
    local text = tostring(value)
    local prev = C.CurrentMemoryContext
    C.CurrentMemoryContext = C.CurTransactionContext

    local datum = imported.InputFunctionCall(rtti[3][0], ffi.cast('char*', text), inoid, -1)
    pg_error.throw_last_error();
    C.CurrentMemoryContext = prev

    return datum
end

local function string_to_datum_T(T)
    local oid = assert(T.oid)
    local rtti = assert(get_rtti(oid))

    local form_pg_type = rtti[2]
    local result

    result = function (value)
        assert (type(value) == "string")
        local inoid = oid
        if form_pg_type.typelem ~=0 then
            inoid = form_pg_type.typelem
        end
        local text = tostring(value)
        local prev = C.CurrentMemoryContext
        C.CurrentMemoryContext = C.CurTransactionContext

        local datum = imported.InputFunctionCall(rtti[3][0], ffi.cast('char*', text), inoid, -1)
        pg_error.throw_last_error();
        C.CurrentMemoryContext = prev

        return datum

    end

    return result

end 

local function to_datum_T(T)
    local oid = assert(T.oid)

    local string_to_datum = string_to_datum_T({oid = oid})

    result = function (value)
        if (type(value) == "string") then
            return string_to_datum(value)
        elseif (type(value) == "table") then
            local mt = getmetatable(value)
            if (mt == typtype_base_mt ) then
                return rawget(unwrap_datum(value), -1)
            elseif( mt == composite_t.mt) then
                return composite_t.to_datum(unwrap_datum(value))
            else
                local rtti = get_rtti(oid)
                if (rtti[4]~=nil) then --composite data
                    return composite_t.table_to_datum_rtti(value, rtti)
                end
            end
            return error('NYI')
        else 
            return error('NYI')
        end
    end

    return result
end

composite_t.set_datum_ops({
    string_to_rawdatum_rtti = string_to_rawdatum_rtti,
})

return {
    to_lua_T = to_lua_T,
    string_to_datum_T = string_to_datum_T,
    to_datum_T = to_datum_T,
}
