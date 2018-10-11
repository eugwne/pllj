local ffi = require('ffi')
local C = ffi.C

local datumfor = {}


datumfor[C.VOIDOID] = function ()
    return ffi.cast('Datum', 0)
end

return {datumfor=datumfor}

