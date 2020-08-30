local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')

assert(0 == C.WJB_DONE)
assert(1 == C.WJB_KEY)
assert(2 == C.WJB_VALUE)
assert(3 == C.WJB_ELEM)
assert(4 == C.WJB_BEGIN_ARRAY)
assert(5 == C.WJB_END_ARRAY)
assert(6 == C.WJB_BEGIN_OBJECT)
assert(7 == C.WJB_END_OBJECT)

assert(0 == C.jbvNull)
assert(1 == C.jbvString)
assert(2 == C.jbvNumeric)
assert(3 == C.jbvBool)
assert(16 == C.jbvArray)
assert(17 == C.jbvObject)
assert(18 == C.jbvBinary)

if C.PG_VERSION_NUM >= 130000 then
    assert(32 == C.jbvDatetime)
end

local call_pg_c_variadic = require('pllj.pg.func').call_pg_c_variadic
local text_to_pg = require('pllj.type.text').to_datum

local tmp = ffi.new('JsonbValue [?]', 1 );

local jsb_tolua

local function jsb_container_tolua(jsonb)
    local it = ffi.new('JsonbIterator *[?]', 1)
    --TODO try_catch
    it[0] = C.JsonbIteratorInit(jsonb);
    local v = ffi.new('JsonbValue [?]', 1 );
    local r = C.JsonbIteratorNext(it, v, true);

    if r == 4 then -- WJB_BEGIN_ARRAY
        local jbv = v[0]
        if (jbv.val.array.rawScalar == true) then
            local r = C.JsonbIteratorNext(it, v, true);
            if r == 3 then --WJB_ELEM
                r = C.JsonbIteratorNext(it, tmp, true);
                if r == 5 then --WJB_END_ARRAY
                    r = C.JsonbIteratorNext(it, tmp, true);
                    if r == 0 then --WJB_DONE
                        return jsb_tolua(v[0])
                    end
                end
            end
            return error('unexpected jsonb token: ' ..tostring(r))
        else
            local result = {}
            while true do
                local r = C.JsonbIteratorNext(it, v, true);
                if r == 0 then --WJB_DONE
                    break
                end
                if r == 3 then --WJB_ELEM
                    table.insert(result, jsb_tolua(v[0]))
                end

            end
            return result
        end

    elseif r == 6 then --WJB_BEGIN_OBJECT
        local result = {}
        while true do
            local r = C.JsonbIteratorNext(it, v, true);
            if r == 0 then --WJB_DONE
                break
            end

            if r == 1 then --WJB_KEY
                local jbv = v[0]
                assert(jbv.type == 1) --jbvString
                local jstring = jbv.val.string
                local key = ffi.string(jstring.val, jstring.len);
                if not key then
                    return NULL
                end

                local r = C.JsonbIteratorNext(it, v, true);
                if r ~= 2 then --WJB_VALUE
                    return error('unexpected jsonb token: ' ..tostring(r))
                end
                result[key] = jsb_tolua(v[0])
            end

        end
        return result
    else
        return error('unexpected jsonb token:' ..tostring(r))
    end
end


jsb_tolua = function(jsonbValue)
    local t = jsonbValue.type
    if t == 0 then --jbvNull
        return NULL
    elseif t == 1 then --jbvString
        local jstring = jsonbValue.val.string
        return ffi.string(jstring.val, jstring.len);
    elseif t == 2 then --jbvNumeric
        local num = ffi.cast('Datum', jsonbValue.val.numeric)
        local d = ffi.cast('const char *', call_pg_c_variadic(C.numeric_out, {num}))
        return tonumber(ffi.string(d))
    elseif t == 3 then --jbvBool
        return jsonbValue.val.boolean == true
    elseif t == 18 then --jbvBinary
        return jsb_container_tolua(jsonbValue.val.binary.data);
    else
        return error('unexpected jsonb value type: '..tostring(t))
    end
end


local object_ToJsonbValue
local number_ToJsonbValue
local mapping_ToJsonbValue
local string_ToJsonbValue
local sequence_ToJsonbValue

sequence_ToJsonbValue = function(lv, jsonb_state)
    C.pushJsonbValue(jsonb_state, 4, nil); --WJB_BEGIN_ARRAY
    for _, v in ipairs(lv) do
        object_ToJsonbValue(v, jsonb_state, true);
    end
    return C.pushJsonbValue(jsonb_state, 5, nil); --WJB_END_ARRAY
end

mapping_ToJsonbValue = function(lv, jsonb_state)
    C.pushJsonbValue(jsonb_state, 6, nil); --WJB_BEGIN_OBJECT
    for k, v in pairs(lv) do
        string_ToJsonbValue(tostring(k), tmp[0])
        C.pushJsonbValue(jsonb_state, 1, tmp); --WJB_KEY
        object_ToJsonbValue(v, jsonb_state, false);
    end
    return C.pushJsonbValue(jsonb_state, 7, nil); --WJB_END_OBJECT
end


number_ToJsonbValue = function(lv, jbvNum)
    local v = tostring(lv)

    local d = call_pg_c_variadic(C.numeric_in,  {
                                                    macro.CStringGetDatum(v), 
                                                    macro.ObjectIdGetDatum(0),
                                                    ffi.cast('Datum', -1)
                                                });
    local num = ffi.cast('Numeric', macro.PG_DETOAST_DATUM(d))

    jbvNum.type = 2 --jbvNumeric;
    jbvNum.val.numeric = num;
    
    return jbvNum
end


string_ToJsonbValue = function(lv, jbvElem)
    local length = #lv

    local str_ptr = C.palloc(length + 1)
    ffi.copy(str_ptr, lv, length + 1)

    jbvElem.type = 1 --jbvString
    local ref = jbvElem.val.string
    ref.val = str_ptr
    ref.len = length
end


object_ToJsonbValue = function(lv, jsonb_state, is_elem)

    if (type(lv) == "table") then
        if #lv == 0 then
            return mapping_ToJsonbValue(lv, jsonb_state)
        else
            return sequence_ToJsonbValue(lv, jsonb_state)
        end
    end

    local out_ptr = ffi.cast('JsonbValue*', C.palloc(ffi.sizeof('JsonbValue')))

    if (lv == NULL) then
        --nil returned as pg::NULL (checked earlier)
        --ffi.NULL returned as json::null
        out_ptr.type = 0 --jbvNull
    elseif (type(lv) == "string") then
        string_ToJsonbValue(lv, out_ptr)
    elseif (type(lv) == "boolean") then 
        out_ptr.type = 3 --jbvBool
        out_ptr.val.boolean = lv and 1 or 0
    elseif (type(lv) == "number") then
        out_ptr = number_ToJsonbValue(lv, out_ptr);
    else
        return error('cannot be transformed to jsonb: '..tostring(lv))
    end

    if (jsonb_state[0] == nil) then
        return out_ptr
    end

    return C.pushJsonbValue(jsonb_state, is_elem and 3 or 2 --[[WJB_ELEM : WJB_VALUE]] , out_ptr)

end


return { 

    oid = C.JSONBOID,

    to_lua = function(datum)
        local _in = ffi.cast('Jsonb*', macro.PG_DETOAST_DATUM(datum))
        local lv = jsb_container_tolua(_in.root)
        return lv
    end,

    to_datum = function(lv)
        local jsonb_state = ffi.new('JsonbParseState* [?]', 1 );

        local out_ptr = object_ToJsonbValue(lv, jsonb_state, true);
        local prev = C.CurrentMemoryContext
        C.CurrentMemoryContext = C.CurTransactionContext
        out_ptr = C.JsonbValueToJsonb(out_ptr)
        C.CurrentMemoryContext = prev
        return ffi.cast('Datum', out_ptr), false
    end,

}
