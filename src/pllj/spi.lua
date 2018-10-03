local spi = {}

local ffi = require('ffi')

local C = ffi.C;

local NULL = ffi.NULL

local pgdef = require('pllj.pgdefines')

local call_pg_variadic = require('pllj.pg.func').call_pg_variadic
local text_to_pg = require('pllj.pg.to_pg').datumfor[C.TEXTOID]

local function throw_error(...)
    spi.disconnect()
    error(...)
end

local function connect()
  
  if (C.SPI_connect() ~= pgdef.spi["SPI_OK_CONNECT"]) then
    error("SPI_connect error")
  end

end


local pg_error = require('pllj.pg.pg_error')

local to_lua = require('pllj.io').to_lua
local to_pg = require('pllj.io').to_pg

local tuple_to_lua_1array = require('pllj.tuple_ops').tuple_to_lua_1array


local function process_query_result(result)
    if (result < 0) then
        if (result == pg_error.THROW_NUMBER) then
          return error("SPI execute error: "..pg_error.get_exception_text())
        end
        return error("SPI execute error: "..tostring(query))
      end
      if ((result == pgdef.spi["SPI_OK_SELECT"]) and (C.SPI_processed > 0)) then
        local tupleDesc = C.SPI_tuptable.tupdesc --[[TupleDesc]]
        
    
        local rows = {}
        local spi_processed = tonumber(C.SPI_processed)
        for i = 0, spi_processed-1 do
          local tuple = C.SPI_tuptable.vals[i] --[[HeapTuplelocal]]
          rows[i+1] = tuple_to_lua_1array(tupleDesc, tuple)
    
        end
    
        C.SPI_freetuptable(C.SPI_tuptable);
        return rows
    
      else
        return {}
      end
end

function spi.execute(query)
    local result = -1
    --try
    result = C.lj_SPI_execute(query, 0, 0)
    --catch
    return process_query_result(result)
end

local function exec_plan(prepared_plan, ...)
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
    local result = C.lj_SPI_execute_plan(prepared_plan.plan, values, nulls, 0, 0)
    return process_query_result(result)
end

local plan_mt = {
    __index = {
        exec = exec_plan,
    },
  }

function spi.prepare(query, ...)
    local argc = select('#', ...)
    local arg_types = {...}
    local oids = ffi.new("Oid [?]", argc)
    for i = 1, argc do
        local oid = call_pg_variadic(C.to_regtype, {text_to_pg(arg_types[i])})
        oids[i-1] = oid
    end
    local plan = C.lj_SPI_prepare_cursor(query, argc, oids, 0)
    if plan == nil then
        return error("SPI_prepare_cursor error:"..pg_error.get_exception_text())
    end
    assert(C.SPI_keepplan(plan)==0)

    ffi.gc(plan, C.SPI_freeplan)
    local prepared_plan = {plan = plan, oids = oids, argc = argc}
    setmetatable(prepared_plan, plan_mt)

    return prepared_plan
    

end



function spi.disconnect()
    return C.SPI_finish()
end



spi.connect = connect
spi.throw_error = throw_error


return spi
