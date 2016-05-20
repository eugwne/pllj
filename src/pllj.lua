local pllj = {}

local pgdef = require('pllj.pgdefines')

pllj._DESCRIPTION = "LuaJIT FFI postgres language extension"
pllj._VERSION     = "pllj 0.1"

local ffi = require('ffi')
ffi.cdef[[
extern bool errstart(int elevel, const char *filename, int lineno,
		 const char *funcname, const char *domain);
extern void errfinish(int dummy,...);
int	errmsg(const char *fmt,...);
]]

print = function(text)
  ffi.C.errstart(pgdef.elog["INFO"], "", 0, nil, nil)
  ffi.C.errfinish(ffi.C.errmsg(tostring(text)))
end

throw = function(text)
  ffi.C.errstart(pgdef.elog["ERROR"], "", 0, nil, nil)
  ffi.C.errfinish(ffi.C.errmsg(tostring(text)))
end

local spi = require('pllj.spi')

function pllj.validator (...)

end

function pllj.callhandler (...)
  spi.disconnect()
end

function pllj.inlinehandler (...)
  local text = select(1, ...)
  local f, error = loadstring(text)
  if (f) then 
    f() 
    spi.disconnect()
  else 
    spi.disconnect()
    throw(error) 
  end
end

return pllj
