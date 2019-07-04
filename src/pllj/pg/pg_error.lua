local ffi = require('ffi')

local C = ffi.C

ffi.cdef[[ErrorData  *last_edata;]]


local function get_exception_text()
  local message = C.last_edata.message == nil and "" or ffi.string(C.last_edata.message)
  local detail = C.last_edata.detail == nil and "" or ffi.string(C.last_edata.detail)
  --TODO: C.FreeErrorData(C.last_edata) ?
  
  return message.."\n\t"..detail
end


local function throw_last_error(text)
    if C.last_edata == nil then return end 
    text = (text or "") .. get_exception_text()
    C.FreeErrorData(C.last_edata)
    C.last_edata = nil
    return error(text)
end


return {
    get_exception_text = get_exception_text,
    throw_last_error = throw_last_error,
}
