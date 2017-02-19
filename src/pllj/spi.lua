local spi = {}

local ffi = require('ffi')

local C = ffi.C;

local NULL = require('pllj.pg.c').NULL

local pgdef = require('pllj.pgdefines')

ffi.cdef[[
int	lj_SPI_execute(const char *src, bool read_only, long tcount);
int call_depth;
Datum pllj_heap_getattr(HeapTuple tuple, int16_t attnum, TupleDesc tupleDesc, bool *isnull);
]]

local function connect()
  
  if (C.SPI_connect() ~= pgdef.spi["SPI_OK_CONNECT"]) then
    error("SPI_connect error")
  end

end


local pg_error = require('pllj.pg.pg_error')

local to_lua = require('pllj.io').to_lua

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
    --[[TupleDesc]]local tupleDesc = C.SPI_tuptable.tupdesc
    local rows = {}
    local spi_processed = tonumber(C.SPI_processed)
    for i = 0, spi_processed-1 do
      --[[HeapTuplelocal]]local tuple = C.SPI_tuptable.vals[i]

      local natts = tupleDesc.natts
      local row = {}
      for k = 0, natts-1 do
        --local attname = tupleDesc.attrs[k].attname;
        --local columnName =  (ffi.string(attname, NAMEDATALEN))
        local attnum = tupleDesc.attrs[k].attnum;
        local atttypid = tupleDesc.attrs[k].atttypid;

        local isNull = ffi.new("bool[?]", 1)
        --local val = C.SPI_getbinval(tuple, tupleDesc, k, isNull)

        local val = C.pllj_heap_getattr(tuple, attnum, tupleDesc,  isNull)
        val = to_lua(atttypid)(val)

        row[k+1] = isNull[0] == false and val or NULL

      end
      rows[i+1] = row

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

spi.connect = connect


return spi
