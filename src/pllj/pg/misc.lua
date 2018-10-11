local ffi = require('ffi')
local C = ffi.C
local get_pg_typeinfo = require('pllj.pg.type_info').get_pg_typeinfo

local function get_io_func(oid)
    local typeinfo = get_pg_typeinfo(oid)
    local free = typeinfo._free;
    typeinfo = typeinfo.data
    local inputf, outputf
    if typeinfo.typtype == C.TYPTYPE_BASE then

        local input = ffi.new("FmgrInfo[?]", 1)
        local output = ffi.new("FmgrInfo[?]", 1)
        C.fmgr_info_cxt(typeinfo.typinput, input, C.TopMemoryContext);
        C.fmgr_info_cxt(typeinfo.typoutput, output, C.TopMemoryContext);

        
        inputf = function(text)
            return C.InputFunctionCall(input, ffi.cast('char*', text), oid, -1)
        end

        outputf = function(datum)
            return ffi.string(C.OutputFunctionCall(output, datum))
        end

    end
    free()

    return inputf, outputf

end

return {get_io_func = get_io_func}