local ffi = require('ffi')

local C = ffi.C

local ref_error = imported.last_e

local function get_exception_text()
  local message = ref_error.data.message == nil and "" or ffi.string(ref_error.data.message)
  local detail = ref_error.data.detail == nil and "" or ffi.string(ref_error.data.detail)
  --TODO: C.FreeErrorData(C.last_edata) ?
  
  return message.."\n\t"..detail
end


local function throw_last_error(text)
    if ref_error.data == nil then return end 
    text = (text or "") .. get_exception_text()
    C.FreeErrorData(ref_error.data)
    ref_error.data = nil
    return error(text)
end


return {
    get_exception_text = get_exception_text,
    throw_last_error = throw_last_error,
}
