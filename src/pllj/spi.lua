local spi = {}

local opt = {}

opt.readonly = false

local ffi = require('ffi')

local C = ffi.C;

local NULL = ffi.NULL

local call_pg_c_variadic = require('pllj.pg.func').call_pg_c_variadic

local pg_error = require('pllj.pg.pg_error')

local to_lua = require('pllj.io').to_lua
local to_pg = require('pllj.io').to_pg

local tuple_to_lua_1array = require('pllj.tuple_ops').tuple_to_lua_1array

local get_oid_from_name = require('pllj.pg.type_info').get_oid_from_name

local _private = setmetatable({}, {__mode = "k"}) 

local function process_ok()
    local tupleDesc = C.SPI_tuptable.tupdesc --[[TupleDesc]]

    local rows = {}
    local spi_processed = tonumber(C.SPI_processed)
    for i = 0, spi_processed-1 do
        local tuple = C.SPI_tuptable.vals[i] --[[HeapTuplelocal]]
        rows[i+1] = tuple_to_lua_1array(tupleDesc, tuple)

    end

    C.SPI_freetuptable(C.SPI_tuptable);
    return rows
end

local function noop()
end

local process_functions = {
    [C.SPI_OK_CONNECT] = noop,
    [C.SPI_OK_FINISH] = noop,
    [C.SPI_OK_FETCH] = noop,
    [C.SPI_OK_UTILITY] = noop,
    [C.SPI_OK_SELECT] = process_ok,
    [C.SPI_OK_SELINTO] = noop,
    [C.SPI_OK_INSERT] = noop,
    [C.SPI_OK_DELETE] = noop,
    [C.SPI_OK_UPDATE] = noop,
    [C.SPI_OK_CURSOR] = noop,
    [C.SPI_OK_INSERT_RETURNING] = process_ok,
    [C.SPI_OK_DELETE_RETURNING] = process_ok,
    [C.SPI_OK_UPDATE_RETURNING] = process_ok,
    [C.SPI_OK_REWRITTEN] = noop,
}

if C.PG_VERSION_NUM >= 100000 then
    process_functions[C.SPI_OK_REL_REGISTER] = noop
    process_functions[C.SPI_OK_REL_UNREGISTER] = noop
    process_functions[C.SPI_OK_TD_REGISTER] = noop
end

local function process_query_result(result)
    if (result < 0) then
        return error("SPI execute error: "..tostring(query))
    end

    if C.SPI_processed > 0 then
        return process_functions[result]()
    else
        return {}
    end
end

function spi.execute(query)
    --try
    local result = C.lj_SPI_execute(query, opt.readonly, 0)
    --catch
    pg_error.throw_last_error("SPI execute error: ")
    
    return process_query_result(result)
end

--TODO remake it
local _saved_plans = {}
local function save_as(self, name)
    _saved_plans[name] = self
end

function spi.find_plan(name)
    return _saved_plans[name]
end

local unwrap_plan
if __untrusted__ then
    unwrap_plan = function(plan_obj)
        return plan_obj
    end
else
    unwrap_plan = function(plan_obj)
        return _private[plan_obj]
    end
end

local function exec_plan(self, ...)
    local prepared_plan = unwrap_plan(self)
    local argc = prepared_plan.argc
    local oids = prepared_plan.oids
    local values = ffi.new("Datum [?]", argc)
    local nulls = ffi.new("char [?]", argc)
    local has_nulls = false
    local args = {...}
    for i = 0, argc-1 do
        local v = args[i+1]
        if v and v ~= ffi.NULL then
            nulls[i] = string.byte(' ')
            values[i] = to_pg(oids[i])(v)
        else
            nulls[i] = string.byte('n')
            has_nulls = true
        end
    end
    if not has_nulls then
        nulls = nil
    end
    local result = C.lj_SPI_execute_plan(prepared_plan.plan, values, nulls, opt.readonly, 0)
    pg_error.throw_last_error("SPI execute plan error: ")
    return process_query_result(result)
end

local plan_mt = {
    __index = {
        exec = exec_plan,
        save_as = save_as
    },
  }

local wrap_plan
if __untrusted__ then
    wrap_plan = function(plan_obj)
        setmetatable(plan_obj, plan_mt)
        return plan_obj
    end
else
    wrap_plan = function(plan_obj)
        local prepared_plan = {}
        _private[prepared_plan] = plan_obj
        setmetatable(prepared_plan, plan_mt)
        return prepared_plan
    end
end


function spi.prepare(query, ...)
    local argc = select('#', ...)
    local arg_types = {...}
    local oids = ffi.new("Oid [?]", argc)
    for i = 1, argc do
        local oid = get_oid_from_name(arg_types[i]) --call_pg_c_variadic(C.to_regtype, {text_to_pg(arg_types[i])})
        oids[i-1] = oid
    end
    local plan = C.lj_SPI_prepare_cursor(query, argc, oids, 0)
    pg_error.throw_last_error("SPI_prepare_cursor error:")

    assert(C.SPI_keepplan(plan)==0, "SPI keepplan failed")

    ffi.gc(plan, C.SPI_freeplan)

    return wrap_plan ({plan = plan, oids = oids, argc = argc})

end



return {
    spi = spi, 
    opt = opt,
}
