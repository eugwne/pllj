local pllj = {}

local function_cache = {}

local ffi = require('ffi')
local all_types = require('pllj.pg.i').all_types
ffi.cdef(all_types)


local NULL = require('pllj.pg.c').NULL

local pgdef = require('pllj.pgdefines')

pllj._DESCRIPTION = "LuaJIT FFI postgres language extension"
pllj._VERSION = "pllj 0.1"



ffi.cdef [[
void set_pllj_call_result(Datum result);
bool lj_CALLED_AS_TRIGGER (void* fcinfo);
]]
local C = ffi.C;
local bit = require("bit")

print = function(text)
    C.errstart(pgdef.elog["INFO"], "", 0, nil, nil)
    C.errfinish(C.errmsg(tostring(text)))
end

local spi = require('pllj.spi')

local function throw_error(...)
    spi.disconnect()
    error(...)
end

local function error_xcall(err)
    if type(err) == "table" then
        if err.detail == nil then
            err.detail = debug.traceback()
        end
        return err
    else
        return { message = err, detail = debug.traceback() }
    end
end

local function exec(f)
    local status, err, ret = xpcall(f, error_xcall)

    if status ~= true then
        if type(err) == "table" then
            if err.detail == nil then
                err.detail = debug.traceback()
            end
            throw_error(err)
        else
            throw_error({ message = err, detail = debug.traceback() })
        end
    end
    return ret
end



local pllj_func = require('pllj.func')
local get_func_from_oid = pllj_func.get_func_from_oid
local need_update = pllj_func.need_update


local to_lua = require('pllj.io').to_lua
local datumfor = require('pllj.io').datumfor

local FunctionCallInfo = ffi.typeof('struct FunctionCallInfoData *')

local trigger_event = { 
    when ={
        [tonumber(C.TRIGGER_EVENT_BEFORE)] = "before",
        [tonumber(C.TRIGGER_EVENT_AFTER)] = "after",
        [tonumber(C.TRIGGER_EVENT_INSTEAD)] = "instead",
        },
    operation = {
        [tonumber(C.TRIGGER_EVENT_INSERT)] = "insert",
        [tonumber(C.TRIGGER_EVENT_DELETE)] = "delete",
        [tonumber(C.TRIGGER_EVENT_UPDATE)] = "update",
        [tonumber(C.TRIGGER_EVENT_TRUNCATE)] = "truncate",
    }   
}

local function print_named( t )
    print('_______')
    for k, v in pairs(t) do
        print(tostring(k))
        print (' = ' .. tostring(v))
    end
    print('------')
end
local tuple_to_lua_table = require('pllj.tuple_ops').tuple_to_lua_table
local function trigger_handler(func_struct, fcinfo)
    if func_struct.result_type ~= C.TRIGGEROID then
        return throw_error('wrong trigger function')
    end
    local tdata = ffi.cast('TriggerData*', fcinfo.context) 
    local trigger = {
        level = bit.band(tdata.tg_event, C.TRIGGER_EVENT_ROW) and "row" or "statement",
        operation = trigger_event.operation[bit.band(tdata.tg_event, C.TRIGGER_EVENT_OPMASK)],
        when = trigger_event.when[bit.band(tdata.tg_event, C.TRIGGER_EVENT_TIMINGMASK)]
    }
    --print(trigger.level) --"when"
    --print(trigger.operation) --"level"
    --print(trigger.when)
    local relname = ffi.string(tdata.tg_relation.rd_rel.relname.data)
    --print(relname)
    local namespace = ffi.string(C.get_namespace_name(tdata.tg_relation.rd_rel.relnamespace))

    local tupleDesc = tdata.tg_relation.rd_att
    local row = tuple_to_lua_table(tupleDesc, tdata.tg_trigtuple)
    local old_row 
    if trigger.level == "row" and trigger.when == "update" then
        old_row = row
        row = tuple_to_lua_table(tupleDesc, tdata.tg_newtuple)
    end

    local name = ffi.string(tdata.tg_trigger.tgname)
    --print(name)


    
    --print_named(row)
    --print(tupleDesc)
    --"operation"
    -- TODO pcall
    func_struct.func()
    --TODO: triggers
    --throw_error('NYI:triggers')
end


function pllj.validator(fn_oid)
    local f, err = get_func_from_oid(fn_oid)
    if not f then 
        error(err) 
    end
    function_cache[fn_oid] = f
end


function pllj.callhandler(fcinfo)
    spi.connect()
    fcinfo = ffi.cast(FunctionCallInfo, fcinfo)
    local fn_oid = fcinfo.flinfo.fn_oid
    local func_struct = function_cache[fn_oid]


    if not func_struct or need_update(func_struct) then
        local f, err = get_func_from_oid(fn_oid)
        if not f then 
            return throw_error(err) 
        end
        func_struct = f
        function_cache[fn_oid] = func_struct
    end

    local istrigger = C.lj_CALLED_AS_TRIGGER(fcinfo)
    if istrigger then
        trigger_handler(func_struct, fcinfo) --result_type
        return spi.disconnect()
    end
    local args = {}
    for i = 0, fcinfo.nargs - 1 do
        if fcinfo.argnull[i] == true then
            table.insert(args, NULL)
        else
            local typeoid = func_struct.argtypes[i + 1]
            local converter_to_lua = to_lua(typeoid)

            if not converter_to_lua then
                return throw_error('no conversion for type ' .. typeoid)
            end
            table.insert(args, converter_to_lua(fcinfo.arg[i]))
        end
    end
    -- TODO pcall
    local result = func_struct.func(unpack(args))
    local iof = datumfor[func_struct.result_type]

    if not iof then
        --get_pg_typeinfo(func_struct.result_type)
        return throw_error('no conversion for type ' .. tostring(func_struct.result_type))
    end
    if not result or result == NULL then
        fcinfo.isnull = true
        return spi.disconnect()
    end

    C.set_pllj_call_result(iof(result))
    return spi.disconnect()
end

function pllj.inlinehandler(...)
    spi.connect()
    local text = select(1, ...)
    local f, err = loadstring(text)
    if (f) then
        exec(f)
    else
        throw_error(err)
    end
    return spi.disconnect()
end

return pllj
