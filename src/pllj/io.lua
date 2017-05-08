local typeto = require('pllj.pg.to_lua').typeto

local datumfor = require('pllj.pg.to_pg').datumfor

local syscache = require('pllj.pg.syscache')
local macro = require('pllj.pg.macro')

local ffi = require('ffi')
local C = ffi.C
local function get_pg_typeinfo(oid)
    local t = C.SearchSysCache(syscache.enum.TYPEOID, --[[ObjectIdGetDatum]] oid, 0, 0, 0);
    local tstruct = ffi.cast('Form_pg_type', macro.GETSTRUCT(t));
--    print("-----tstruct------")
--    print(tstruct.typlen)
--    print(tstruct.typtype)
--    print(tstruct.typalign)
--    print(tstruct.typbyval)
--    print(tstruct.typelem)
--    print("------------------")
--    local result = {
--        typlen = tstruct.typlen,
--        typtype = tstruct.typtype,
--        typalign = tstruct.typalign,
--        typbyval = tstruct.typbyval,
--        typelem = tstruct.typelem,
--        typinput = tstruct.typinput,
--        typoutput = tstruct.typoutput
--    }
    local result = {
        data = tstruct,
        _free = function() C.ReleaseSysCache(t) end
    }

    return result;
end

local raw_datum = {
    __tostring = function(self)
        local charPtr = C.OutputFunctionCall(self.output, self.datum)
        return ffi.string(charPtr)
    end
}

local function create_converter_tolua(oid)
    local typeinfo = get_pg_typeinfo(oid)
    local free = typeinfo._free;
    typeinfo = typeinfo.data
    local result
    if typeinfo.typtype == C.TYPTYPE_BASE then

        local input = ffi.new("FmgrInfo[?]", 1)
        local output = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(typeinfo.typinput, input, C.TopMemoryContext);
        C.fmgr_info_cxt(typeinfo.typoutput, output, C.TopMemoryContext);

        result = function (datum)
            local value = {
                datum = datum,
                oid = oid,
                typeinfo = typeinfo,
                input = input,
                output = output
            }
            setmetatable(value, raw_datum)

            return value
        end
    end
    free()
    return result

end

local function to_lua(typeoid)
    local to_lua = typeto[typeoid]
    if not to_lua then
        to_lua = create_converter_tolua(typeoid) or function(datum) return datum end
        typeto[typeoid] = to_lua
    end
    return to_lua
end

--local function datum_to_value(datum, atttypid)
--
--    local func = typeto[atttypid]
--    if (func) then
--        return func(datum)
--    end
--    return datum --TODO other types
--    --print("SC = "..tonumber(syscache.enum.TYPEOID))
--    --type = C.SearchSysCache(syscache.enum.TYPEOID, ObjectIdGetDatum(oid), 0, 0, 0);
--end

return {
    to_lua = to_lua,
    datumfor = datumfor,
}