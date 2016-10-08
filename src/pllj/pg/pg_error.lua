local THROW_NUMBER = -1000

local ffi = require('ffi')

local C = ffi.C

ffi.cdef[[ErrorData  *last_edata;]]


local function get_exception_text()
  local message = ffi.string(C.last_edata.message)
  local detail = ffi.string(C.last_edata.detail)
  return message.."|"..detail
end



return {
  THROW_NUMBER = THROW_NUMBER,
  get_exception_text = get_exception_text
  }