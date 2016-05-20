local pgdefines = {}

pgdefines.elog = { 
	["LOG"] = 15,
	["INFO"] = 17,
	["NOTICE"] = 18,
	["WARNING"] = 19,
	["ERROR"] = 20,
	["FATAL"] = 21,
	["PANIC"] = 22
}

pgdefines.spi = {
  ["SPI_OK_CONNECT"] = 1,
  ["SPI_OK_SELECT"] = 5
}

return pgdefines
