local pgdefines = {}
local C = require('ffi').C


pgdefines.pg_config_manual = {
  ["NAMEDATALEN"] = C.NAMEDATALEN
}

pgdefines.spi = {
  ["SPI_OK_CONNECT"] = 1,
  ["SPI_OK_SELECT"] = 5
}

return pgdefines
