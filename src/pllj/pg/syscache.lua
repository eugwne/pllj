local ffi = require('ffi')

local enum = ffi.new("struct enum_SysCacheIdentifier")
  
return {enum = enum}