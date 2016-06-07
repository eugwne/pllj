local pllj = {}

local function_cache = {}

require('pllj.pg.c')

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
local C = ffi.C;

print = function(text)
  C.errstart(pgdef.elog["INFO"], "", 0, nil, nil)
  C.errfinish(C.errmsg(tostring(text)))
end

local spi = require('pllj.spi')
local syscache = require('pllj.pg.syscache')

require('pllj.pg.pg_proc')

local function macro_GETSTRUCT(TUP)
  local addr = ffi.cast("intptr_t", (TUP).t_data)
  return ffi.cast('char*',addr+(TUP.t_data.t_hoff))
end

local builtins = require('pllj.pg.builtins')
local pg_proc = require('pllj.pg.pg_proc')

local function get_pg_typeinfo(oid)
  local t = C.SearchSysCache(syscache.enum.TYPEOID, --[[ObjectIdGetDatum]](oid), 0, 0, 0);
  local tstruct = ffi.cast('Form_pg_type', macro_GETSTRUCT(t));
  print("-----tstruct------")
  print(tstruct.typlen)
  print(tstruct.typtype)
  print(tstruct.typalign)
  print(tstruct.typbyval)
  print(tstruct.typelem)
  print("------------------")
  C.ReleaseSysCache(t)
end

local function macro_PG_DETOAST_DATUM(datum)
  return C.pg_detoast_datum(ffi.cast('struct varlena*', ffi.cast('Pointer', datum)))
end


local function macro_DatumGetArrayTypeP(X)
  return ffi.cast('ArrayType *',macro_PG_DETOAST_DATUM(X))
end


local pg_type = require('pllj.pg.pg_type')
require('pllj.pg.array')
local function get_func_from_oid(oid)
  local isNull = ffi.new("bool[?]", 1)
  local proc = C.SearchSysCache(syscache.enum.PROCOID, --[[ObjectIdGetDatum]](oid), 0, 0, 0);

  print(proc)
  local procst = ffi.cast('Form_pg_proc', macro_GETSTRUCT(proc));

  local nargs = procst.pronargs;
  local argtypes = procst.proargtypes.values;
  local rettype = procst.prorettype;
  local isset = procst.proretset;
--  print(procst)
--  print(argtypes)
--  print(nargs)
--  print('rettype  '..rettype)

--  for i = 0, nargs-1 do
--    print('argtype '..tostring(argtypes[i]))
--    get_pg_typeinfo(argtypes[i])
--  end
  if nargs > 0 then
    local nnames = ffi.new("int[?]", 1)
    local argnames = C.SysCacheGetAttr(syscache.enum.PROCOID, proc,
        pg_proc.defines.Anum_pg_proc_proargnames, isNull)
    if isNull[0] == false then
      local argname = ffi.new 'Datum *[1]'
      C.deconstruct_array(macro_DatumGetArrayTypeP(argnames), pg_type["TEXTOID"], -1, false,
          string.byte('i'), argname, nil, nnames)
      print(argname)
      print(nnames[0])
      for i = 0, nnames[0] - 1 do
        print(builtins.pg_text_tolua(argname[0][i]))
      end
      
    end
    
  end
  
  

  
  local prosrc = C.SysCacheGetAttr(syscache.enum.PROCOID, proc, pg_proc.defines.Anum_pg_proc_prosrc, isNull);
  prosrc = builtins.pg_text_tolua(prosrc)
  if (isNull[0] == true) then
		error( "null prosrc for function ".. oid);
  end
  
  print(prosrc)
  
  C.ReleaseSysCache(proc)
  return nil
end

function pllj.validator (...)

end


function pllj.callhandler (fcinfo)
  fcinfo = ffi.cast('FunctionCallInfo',fcinfo)
  local fn_oid = fcinfo.flinfo.fn_oid
  local func = function_cache[fn_oid]
  if not func then
    func = get_func_from_oid(fn_oid)
    function_cache[fn_oid] = func
  end
  
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
