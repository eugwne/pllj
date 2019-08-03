local spi = {}
local opt = {}

opt.readonly = false

local ffi = require('ffi')
local C = ffi.C;

local call_pg_c_variadic = require('pllj.pg.func').call_pg_c_variadic
local pg_error = require('pllj.pg.pg_error')

local to_lua = require('pllj.io').to_lua
local to_pg = require('pllj.io').to_pg

local tuple_to_lua_1array = require('pllj.tuple_ops').tuple_to_lua_1array

local get_oid_from_name = require('pllj.pg.type_info').get_oid_from_name
local table_new = require('table.new')

local _private = setmetatable({}, {__mode = "k"}) 

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

    typedef struct SharedPortal {
        intrusive_base base;
        Portal portal;
        const char *name;
        bool closed;
    } SharedPortal;
]]


local SharedPlan_ts = ffi.sizeof('SharedPlan')
local SharedPortal_ts = ffi.sizeof('SharedPortal')
local Oid_ts = ffi.sizeof('Oid')
local int_ptr_t = ffi.typeof('int*')
local void_ptr_t = ffi.typeof('void*')
local shared_plan_ptr_t = ffi.typeof('SharedPlan*')
local shared_portal_ptr_t = ffi.typeof('SharedPortal*')
local MemoryContextCallback_ts = ffi.sizeof('MemoryContextCallback')
local MemoryContextCallback_ptr_t = ffi.typeof('MemoryContextCallback*')


local function intrusive_ptr_create(type, size, _dtor)
    local raw = top_alloc(size)
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


local function intrusive_ptr_release_F(_dtor)
    return function(p)
        local iptr = ffi.cast(int_ptr_t, p)
        iptr[0] = iptr[0] - 1
        if iptr[0] == 0 then
            _dtor(p)
        end
    end
end


local plan_mt
local cursor_mt
local wrap
local unwrap
if __untrusted__ then
    wrap = function(obj, mt)
        setmetatable(obj, mt)
        return obj
    end

    unwrap = function(obj)
        return obj
    end
else
    wrap = function(obj, mt)
        local key = {}
        _private[key] = obj
        setmetatable(key, mt)
        return key
    end

    unwrap = function(obj)
        return _private[obj]
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


local function __cursor_iterator(cursor)
    local next_idx = 51
    local sz = 50
    local r
    return function()
        if next_idx > sz then
            r = cursor:fetch(sz)
            next_idx = 1
        end
        local v = r[next_idx]
        next_idx = next_idx + 1
        if v == nil then
            cursor:close()
        end
        return v
    end
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

local cursor_directions = {
    [0] = 0,
    [1] = 1,
    [2] = 2,
    [3] = 3,
    f = 0,
    b = 1,
    a = 2,
    r = 3,
    forward = 0,
    backward = 1,
    absolute = 2,
    relative = 3,
}

if C.PG_VERSION_NUM >= 100000 then
    process_functions[C.SPI_OK_REL_REGISTER] = noop
    process_functions[C.SPI_OK_REL_UNREGISTER] = noop
    process_functions[C.SPI_OK_TD_REGISTER] = noop
end

local portal_field_context
if C.PG_VERSION_NUM < 110000 then
    portal_field_context = "heap"
else
    portal_field_context = "portalContext"
end

local function _portal_destructor(p)
    if p.closed == false then
        p.closed = true
        imported.uthash_portal_remove(p.name)
        C.pfree(ffi.cast(void_ptr_t, p.name))
        C.SPI_cursor_close(p.portal)
    end
end

local portal_ptr_release = intrusive_ptr_release_F(_portal_destructor) 

local cb_cursor = function(arg)
    local p = ffi.cast(shared_portal_ptr_t, arg)
    if p.closed == false then
        imported.uthash_portal_remove(p.name)
        C.pfree(ffi.cast(void_ptr_t, p.name))
    end
    p.closed = true
    portal_ptr_release(p)
end
local cb_cursor_c = ffi.cast("void (*) (void *arg)", cb_cursor)


local function _shared_portal_new(portal)
    local gcp = intrusive_ptr_create(shared_portal_ptr_t, SharedPortal_ts, portal_ptr_release)
    gcp.portal = portal
    gcp.closed = false
    gcp.name = C.MemoryContextStrdup(C.TopMemoryContext, portal.name)
    local result = imported.uthash_portal_add(portal.name, gcp) 
    return gcp
end

local function _shared_portal_from(raw)
    local gcp = ffi.gc(ffi.cast(shared_portal_ptr_t, intrusive_ptr_add_ref(raw)), portal_ptr_release)
    return gcp
end

local function wrap_new_portal(portal)
    local p = _shared_portal_new(portal)
    local portal_memctx = portal[portal_field_context]
    local cbdata = ffi.cast(MemoryContextCallback_ptr_t, C.MemoryContextAlloc(portal_memctx, MemoryContextCallback_ts));
    cbdata.func = cb_cursor_c
    cbdata.arg = ffi.cast(void_ptr_t, intrusive_ptr_add_ref(p))
    C.MemoryContextRegisterResetCallback(portal_memctx, cbdata);
    return wrap ({p}, cursor_mt)
end

local function process_query_result(result)
    if C.SPI_processed > 0 then
        return process_functions[result]()
    else
        return {}
    end
end

local function _plan_destructor(p)
    C.SPI_freeplan(p.plan)
end

local plan_ptr_release = intrusive_ptr_release_F(_plan_destructor)

local function _shared_new(plan, argc)
    local gcp = intrusive_ptr_create(shared_plan_ptr_t, SharedPlan_ts + Oid_ts * argc, plan_ptr_release)
    gcp.plan = plan
    gcp.argc = argc
    return gcp
end

local function _shared_from(raw)
    local gcp = ffi.gc(ffi.cast(shared_plan_ptr_t, intrusive_ptr_add_ref(raw)), plan_ptr_release)
    return gcp
end


local function prepare_plan_args(prepared_plan, args)
    local argc = prepared_plan.argc
    local oids = prepared_plan.oids
    local values = ffi.new("Datum [?]", argc)
    local nulls = ffi.new("char [?]", argc)
    local has_nulls = false
    for i = 0, argc-1 do
        local v = args[i+1]
        if v ~= nil then
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
    return values, nulls
end

local function plan_exec(self, ...)
    local prepared_plan = unwrap(self)[1]
    local values, nulls = prepare_plan_args(prepared_plan, {...})
    local result = imported.SPI_execute_plan(prepared_plan.plan, values, nulls, opt.readonly, 0)
    pg_error.throw_last_error("SPI execute plan error: ")
    return process_query_result(result)
end

local function plan_save_as(self, name)

    local plan = unwrap(self)[1]

    local result = imported.uthash_add(tostring(name), plan) 
    if result == true then
        intrusive_ptr_add_ref(plan)
    else
        return error('plan ['..name..'] already exists')
    end
    return self

end

local function plan_named_cursor(self, name, ...)
    if name ~= nil then
        name = tostring(name)
    end
    local prepared_plan = unwrap(self)[1]
    local values, nulls = prepare_plan_args(prepared_plan, {...})
    local portal = imported.SPI_cursor_open(name, prepared_plan.plan, values, nulls, opt.readonly)
    pg_error.throw_last_error("SPI cursor error: ")
    return wrap_new_portal(portal)
end

local function plan_cursor(self, ...)
    return plan_named_cursor(self, nil, ...)
end

local function plan_rows(self, ...)
    local cursor = plan_cursor(self, ...)
    return __cursor_iterator(cursor)
end

plan_mt = {
    __index = {
        cursor = plan_cursor,
        named_cursor = plan_named_cursor,
        exec = plan_exec,
        rows = plan_rows,
        save_as = plan_save_as,
    },
  }

local function get_portal(self, noerror)
    noerror = noerror or false
    local obj = unwrap(self)
    local p = rawget(obj, 1)
    local portal = p.portal
    if not noerror then
        assert(p.closed == false, 'cursor deleted')
    end
    return portal, p
end

local function cursor_close(self, noerror)
    local portal, p = get_portal(self)
    -- local check = C.GetPortalByName(portal.name)
    -- assert(check~=nil)
    _portal_destructor(p)
end

local function cursor_fetch(self, count, direction)
    
    local portal = get_portal(self)
    count = count or 1
    direction_id = cursor_directions[direction] or 0
    --try
    imported.SPI_scroll_cursor_fetch(portal, direction_id, count)
    --catch
    pg_error.throw_last_error("SPI execute error: ")

    return process_query_result(C.SPI_OK_SELECT) --TODO select?
end

local function cursor_move(self, count, direction)
    
    local portal = get_portal(self)
    count = count or 1
    direction_id = cursor_directions[direction] or 0
    --try
    imported.SPI_scroll_cursor_move(portal, direction_id, count)
    --catch
    pg_error.throw_last_error("SPI execute error: ")
end

local function cursor_tostring(self)
    local portal = get_portal(self)
    assert(portal ~= nil)
    return ffi.string(portal.name)
end

cursor_mt = {
    __index = {
        fetch = cursor_fetch,
        move = cursor_move,
        close = cursor_close,
    },
    __tostring = cursor_tostring
}


function spi.find_plan(name)
    local result = imported.uthash_find(tostring(name))
    if result ~= nil then
        local p = _shared_from(result)
        return wrap ({p}, plan_mt)
    end
    return nil, "plan not found"
end


function spi.execute(query)
    --try
    local result = imported.SPI_execute(query, opt.readonly, 0)
    --catch
    pg_error.throw_last_error("SPI execute error: ")
    
    return process_query_result(result)
end


function spi.prepare(query, arg_types)
    arg_types = arg_types or {}
    local argc = #arg_types
    local p = _shared_new(nil, argc)
    for i = 1, argc do
        local oid = get_oid_from_name(arg_types[i]) --call_pg_c_variadic(C.to_regtype, {text_to_pg(arg_types[i])})
        p.oids[i-1] = oid
    end
    local plan = imported.SPI_prepare_cursor(query, p.argc, p.oids, 0)
    pg_error.throw_last_error("SPI_prepare_cursor error:")
    p.plan = plan

    assert(C.SPI_keepplan(plan)==0, "SPI keepplan failed")

    return wrap ({p}, plan_mt)

end


function spi.find_cursor(name)
    local result = imported.uthash_portal_find(name)

    if result ~= nil then
        local p = _shared_portal_from(result)
        return wrap ({p}, cursor_mt)
    end
    return nil, 'cursor not found'
end


function spi.named_cursor(name, query, arg_types, args)
    if name ~= nil then
        name = tostring(name)
    end
    arg_types = arg_types or {}
    args = args or {}
    local argc = #args
    assert(argc == #arg_types)

    local oids = ffi.new("Oid [?]", argc)
    for i = 1, argc do
        local oid = get_oid_from_name(arg_types[i]) 
        oids[i-1] = oid
    end

    local values = ffi.new("Datum [?]", argc)
    local nulls = ffi.new("char [?]", argc)

    for i = 0, argc-1 do
        local v = args[i+1]
        if v ~= nil then
            nulls[i] = string.byte(' ')
            values[i] = to_pg(oids[i])(v)
        else
            nulls[i] = string.byte('n')
        end
    end
    --TODO cursor options 
    --[[
            #define CURSOR_OPT_BINARY		0x0001	/* BINARY */
            #define CURSOR_OPT_SCROLL		0x0002	/* SCROLL explicitly given */
            #define CURSOR_OPT_NO_SCROLL	0x0004	/* NO SCROLL explicitly given */
            #define CURSOR_OPT_INSENSITIVE	0x0008	/* INSENSITIVE */
            #define CURSOR_OPT_HOLD			0x0010	/* WITH HOLD */
            /* these planner-control flags do not correspond to any SQL grammar: */
            #define CURSOR_OPT_FAST_PLAN	0x0020	/* prefer fast-start plan */
            #define CURSOR_OPT_GENERIC_PLAN 0x0040	/* force use of generic plan */
            #define CURSOR_OPT_CUSTOM_PLAN	0x0080	/* force use of custom plan */
            #define CURSOR_OPT_PARALLEL_OK	0x0100	/* parallel mode OK */
    ]]

    local portal = imported.SPI_cursor_open_with_args(name,
                                                    query,
                                                    argc, oids,
                                                    values, nulls,
                                                    opt.readonly, 0 --[[cursor options]]);
    pg_error.throw_last_error("SPI_cursor_open_with_args error:")
    return wrap_new_portal(portal)
end

function spi.cursor(query, arg_types, args)
    return spi.named_cursor(nil, query, arg_types, args)
end


local cb_data = { names = {}}
local cb_key = function(key)
    table.insert(cb_data.names, ffi.string(key))
end
local cb_key_c = ffi.cast("void (*) (const char *)", cb_key)

function spi.get_saved_plan_names()
    local size = tonumber(imported.uthash_count())
    cb_data.names = table_new(size, 0)
    imported.uthash_iter(cb_key_c)
    return cb_data.names
end


function spi.free_plan(name)
    local sname = tostring(name)
    local result = imported.uthash_remove(sname)

    if result ~= nil then
        plan_ptr_release(result)
    else
        return error('free_plan [' .. sname .. '] not found')
    end
end


function spi.rows(query)
    local cursor = spi.cursor(query)
    return __cursor_iterator(cursor)
end

return {
    spi = spi, 
    opt = opt,
}
