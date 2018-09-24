local spi = {}

local ffi = require('ffi')

local C = ffi.C;

local NULL = ffi.NULL

local pgdef = require('pllj.pgdefines')



local function connect()
  
  if (C.SPI_connect() ~= pgdef.spi["SPI_OK_CONNECT"]) then
    error("SPI_connect error")
  end

end


local pg_error = require('pllj.pg.pg_error')

local to_lua = require('pllj.io').to_lua

local tuple_to_lua_1array = require('pllj.tuple_ops').tuple_to_lua_1array

function spi.execute(query)
  local result = -1
  --try
  result = C.lj_SPI_execute(query, 0, 0)
  --catch
  if (result < 0) then
    if (result == pg_error.THROW_NUMBER) then
      return error("SPI_execute_plan error:"..pg_error.get_exception_text())
    end
    return error("SPI_execute_plan error:"..tostring(query))
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

function spi.disconnect()
    C.SPI_finish()
end

local function throw_error(...)
    spi.disconnect()
    error(...)
end

spi.connect = connect
spi.throw_error = throw_error


return spi
