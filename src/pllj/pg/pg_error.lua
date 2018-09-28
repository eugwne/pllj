local THROW_NUMBER = -1000

local ffi = require('ffi')

local C = ffi.C

ffi.cdef[[ErrorData  *last_edata;]]


local function get_exception_text()
  local message = C.last_edata.message == nil and "" or ffi.string(C.last_edata.message)
  local detail = C.last_edata.detail == nil and "" or ffi.string(C.last_edata.detail)
  --TODO: C.FreeErrorData(C.last_edata) ?
  
  return message.."|"..detail
end



return {
  THROW_NUMBER = THROW_NUMBER,
  get_exception_text = get_exception_text
  }