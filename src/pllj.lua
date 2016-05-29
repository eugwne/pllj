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

local spi = require('pllj.spi')

function pllj.validator (...)

end


function pllj.callhandler (...)
  spi.disconnect()
end

function pllj.inlinehandler (...)
  local text = select(1, ...)
  local f, err = loadstring(text)
  if (f) then 
    local status, err = xpcall(f, function(err) 
        if type(err) == "table" then
        if err.detail == nil then
          err.detail = debug.traceback()
        end
        return err
      else
        return {message = err, detail = debug.traceback()} 
      end
      
    end) 
    spi.disconnect()
    if status ~= true then
      if type(err) == "table" then
        if err.detail == nil then
          err.detail = debug.traceback()
        end
        error(err)
      else
        error({message = err, detail = debug.traceback()} ) 
      end
    end
    
    
  else 
    spi.disconnect()
    error(err) 
  end
end

return pllj
