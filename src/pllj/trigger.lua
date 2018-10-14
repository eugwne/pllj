local ffi = require('ffi')
local spi = require('pllj.spi').spi
local bit = require("bit")

local C = ffi.C;

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

local tuple_to_lua_table = require('pllj.tuple_ops').tuple_to_lua_table
local lua_table_to_tuple = require('pllj.tuple_ops').lua_table_to_tuple
local G_mt = {__index = _G }

local private_key = {}
local private_key_changes = {}
local proxy_mt = {
    __index = function(self, key)
        return self[private_key][key]
    end,
    __newindex = function(self, key, value)
        self[private_key][private_key_changes] = true
        self[private_key][key] = value
    end,
}
local function track(t)
    local proxy = {}
    proxy[private_key] = t
    setmetatable(proxy, proxy_mt)
    return proxy
end

local function trigger_handler(func_struct, fcinfo)
    if func_struct.result_type ~= C.TRIGGEROID then
        return error('wrong trigger function')
    end
    local tdata = ffi.cast('TriggerData*', fcinfo.context)
    local trigger_level = bit.band(tdata.tg_event, C.TRIGGER_EVENT_ROW) and "row" or "statement"
    local trigger_operation = trigger_event.operation[bit.band(tdata.tg_event, C.TRIGGER_EVENT_OPMASK)]
    local trigger_when = trigger_event.when[bit.band(tdata.tg_event, C.TRIGGER_EVENT_TIMINGMASK)]

    local relname = ffi.string(tdata.tg_relation.rd_rel.relname.data)
    local namespace = ffi.string(C.get_namespace_name(tdata.tg_relation.rd_rel.relnamespace))
    local relation_oid = tonumber(tdata.tg_relation.rd_id)

    local tupleDesc = tdata.tg_relation.rd_att
    local row = tuple_to_lua_table(tupleDesc, tdata.tg_trigtuple)
    local old_row
    if trigger_level == "row" and trigger_operation == "update" then
        old_row = row
        row = tuple_to_lua_table(tupleDesc, tdata.tg_newtuple)
    end

    local trigger_name = ffi.string(tdata.tg_trigger.tgname)

    local trigger = {
        level = trigger_level,
        operation = trigger_operation,
        when = trigger_when,
        name = trigger_name,
        old = old_row,
        row = track(row),
        relation = {
            namespace = namespace,
            name = relname,
            oid = relation_oid
        }
    }

    local newgt = {trigger = trigger}
    setmetatable(newgt, G_mt)
    setfenv(func_struct.func, newgt)
    func_struct.func()

    if trigger_level == "row" and trigger_when == "before" then

        if row[private_key_changes] then
            return true, C.SPI_copytuple(lua_table_to_tuple(tupleDesc, row))
        end

        return true, tdata.tg_trigtuple
    end

end

return {
    trigger_handler = trigger_handler
}
