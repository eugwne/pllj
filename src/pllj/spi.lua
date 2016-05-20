local spi = {}

local spi_connected = false;

local ffi = require('ffi')
ffi.cdef[[
int	SPI_connect(void);
int	SPI_finish(void);
int	SPI_execute(const char *src, bool read_only, long tcount);
uint32_t SPI_processed;
]]
local pgdef = require('pllj.pgdefines')

local function connect()
  if (spi_connected == false) then
    if (ffi.C.SPI_connect() ~= pgdef.spi["SPI_OK_CONNECT"]) then
      throw("SPI_connect error")
    end
    spi_connected = true
  end
  
end


function spi.execute(query)
  connect()
  local result = -1
  --try
  result = ffi.C.SPI_execute(query, 0, 0)
  --catch
  if (result < 0) then
    return throw("SPI_execute_plan error:"..tostring(query))
  end
  if ((result == pgdef.spi["SPI_OK_SELECT"]) and (ffi.C.SPI_processed > 0)) then
    print("processed:"..tostring(ffi.C.SPI_processed).." rows")
  end
  
end

function spi.disconnect()
    if spi_connected then
      ffi.C.SPI_finish()
      spi_connected = false
    end
end


return spi