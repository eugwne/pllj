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

local plan_mt
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

local unwrap_plan

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


ffi.cdef[[
    typedef struct intrusive_base {
        int ref_count;
    } intrusive_base;

    typedef struct SharedPlan {
        intrusive_base base;
        int argc;
        SPIPlanPtr plan;
        Oid oids[];
    } SharedPlan;
]]

local hash_key = ffi.new('intptr_t[?]', 1)
local found = ffi.new('bool[?]',1)
local SharedPlan_ts = ffi.sizeof('SharedPlan')
local Oid_ts = ffi.sizeof('Oid')
local shared_ht = ffi.cast('HTAB***', __shareddata__)[0][0]

local function _mc_alloc(size)
    return C.MemoryContextAlloc(C.TopMemoryContext, size)
end

local function _shared_destructor(p)
    C.SPI_freeplan(p.plan)
end

local int_ptr_t = ffi.typeof('int*')
local shared_plan_ptr_t = ffi.typeof('SharedPlan*')

local function intrusive_ptr_create(type, size, _dtor)
    local raw = _mc_alloc(size)
    local iptr = ffi.cast(int_ptr_t, raw)
    iptr[0] = 1
    local gct = ffi.gc(ffi.cast(type, iptr), _dtor)
    return gct
end

local function intrusive_ptr_add_ref(p)
    local iptr = ffi.cast(int_ptr_t, p)
    iptr[0] = iptr[0] + 1
    return iptr
end

local function intrusive_ptr_release(p)
    local iptr = ffi.cast(int_ptr_t, p)
    iptr[0] = iptr[0] - 1
    if iptr[0] == 0 then
        _shared_destructor(p)
    end
end

local function _shared_new(plan, argc)
    local gcp = intrusive_ptr_create(shared_plan_ptr_t, SharedPlan_ts + Oid_ts * argc, intrusive_ptr_release)
    gcp.plan = plan
    gcp.argc = argc
    return gcp
end

local function _shared_from(raw)
    local gcp = ffi.gc(ffi.cast(shared_plan_ptr_t, intrusive_ptr_add_ref(raw)), intrusive_ptr_release)
    return gcp
end

function spi.find_plan(name)
    assert(type(name)=='string' and #name < 8)

    ffi.fill(hash_key, 8)
    ffi.copy(hash_key, name, math.min(7,#name))

    found[0] = false

    local result = ffi.cast('void**',C.hash_search(shared_ht, hash_key
        , 0--HASH_FIND
        , found))

    if found[0] == true then
        local p = _shared_from(result[0])
        return wrap_plan ({p})
    end
    return nil
end

function spi.free_plan(name)
    assert(type(name)=='string' and #name < 8)

    ffi.fill(hash_key, 8)
    ffi.copy(hash_key, name, math.min(7,#name))

    found[0] = false

    local result = ffi.cast('void**',C.hash_search(shared_ht, hash_key
    , 2--HASH_REMOVE
    , found))

    if found[0] == true then
        intrusive_ptr_release(result[0])
    else
        return error('free_plan not found: '..name)
    end
end

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
    local prepared_plan = unwrap_plan(self)[1]
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

local function save_as(self, name)
    assert(type(name)=='string' and #name < 8)

    local plan = unwrap_plan(self)[1]

    hash_key[0] = 0

    ffi.copy(hash_key, name, math.min(8, #name))

    found[0] = false

    local result = ffi.cast('void**', C.hash_search(shared_ht, ffi.cast('intptr_t*',hash_key), 3--[[HASH_ENTER_NULL]], found))
    if result == nil then
        return error('could not create entry for data structure')
    end
    if found[0] == true then
        return error('plan ['..name..'] already exists')
    else
        result[0] = intrusive_ptr_add_ref(plan)
    end
    return self

end

plan_mt = {
    __index = {
        exec = exec_plan,
        save_as = save_as
    },
  }

function spi.prepare(query, ...)
    local argc = select('#', ...)
    local arg_types = {...}
    local p = _shared_new(nil, argc)
    for i = 1, argc do
        local oid = get_oid_from_name(arg_types[i]) --call_pg_c_variadic(C.to_regtype, {text_to_pg(arg_types[i])})
        p.oids[i-1] = oid
    end
    local plan = C.lj_SPI_prepare_cursor(query, p.argc, p.oids, 0)
    pg_error.throw_last_error("SPI_prepare_cursor error:")
    p.plan = plan

    assert(C.SPI_keepplan(plan)==0, "SPI keepplan failed")

    return wrap_plan ({p})

end



return {
    spi = spi, 
    opt = opt,
}
