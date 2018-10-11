local ffi = require('ffi')
local C = ffi.C

local typeto = {}


typeto[C.VOIDOID] = function ()
end


return {typeto = typeto}
