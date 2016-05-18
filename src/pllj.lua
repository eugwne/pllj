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

local throw = function(text)
  ffi.C.errstart(pgdef.elog["ERROR"], "", 0, nil, nil)
  ffi.C.errfinish(ffi.C.errmsg(tostring(text)))
end

function pllj.validator (...)

end

function pllj.callhandler (...)

end

function pllj.inlinehandler (...)
  local text = select(1, ...)
  f = loadstring(text)
  if (f) then 
    f() 
  else 
    throw('can not execute') 
  end
end

return pllj
