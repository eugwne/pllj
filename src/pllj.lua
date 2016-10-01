local pllj = {}

local function_cache = {}

local NULL = require('pllj.pg.c').NULL

local pgdef = require('pllj.pgdefines')

pllj._DESCRIPTION = "LuaJIT FFI postgres language extension"
pllj._VERSION     = "pllj 0.1"

local band = require("bit").band

local ffi = require('ffi')
ffi.cdef[[
extern bool errstart(int elevel, const char *filename, int lineno,
		 const char *funcname, const char *domain);
extern void errfinish(int dummy,...);
int	errmsg(const char *fmt,...);
]]
ffi.cdef[[
void set_pllj_call_result(Datum result);
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

--local function get_pg_typeinfo(oid)
--  local t = C.SearchSysCache(syscache.enum.TYPEOID, --[[ObjectIdGetDatum]](oid), 0, 0, 0);
--  local tstruct = ffi.cast('Form_pg_type', macro_GETSTRUCT(t));
--  print("-----tstruct------")
--  print(tstruct.typlen)
--  print(tstruct.typtype)
--  print(tstruct.typalign)
--  print(tstruct.typbyval)
--  print(tstruct.typelem)
--  print("------------------")
--  C.ReleaseSysCache(t)
--end

local function macro_PG_DETOAST_DATUM(datum)
  return C.pg_detoast_datum(ffi.cast('struct varlena*', ffi.cast('Pointer', datum)))
end

local function macro_SET_4_BYTES(X)
  --(((Datum) (value)) & 0xffffffff)
  return (band(ffi.cast('Datum', X), 0xffffffff))
end


local function macro_ObjectIdGetDatum(X)
  return ffi.cast('Datum', macro_SET_4_BYTES(X))
end

local function macro_DatumGetArrayTypeP(X)
  return ffi.cast('ArrayType *', macro_PG_DETOAST_DATUM(X))
end

local HEAP_XMIN_COMMITTED	=	0x0100	--/* t_xmin committed */
local HEAP_XMIN_INVALID	=	0x0200	--/* t_xmin invalid/aborted */
local HEAP_XMIN_FROZEN = band(HEAP_XMIN_COMMITTED,HEAP_XMIN_INVALID)

local function macro_HeapTupleHeaderGetRawXmin(tup)
  return tup.t_choice.t_heap.t_xmin
end

local function macro_HeapTupleHeaderXminFrozen(tup)
  --((tup)->t_infomask & (HEAP_XMIN_FROZEN)) == HEAP_XMIN_FROZEN 
  return (band(tup.t_infomask ,HEAP_XMIN_FROZEN) == HEAP_XMIN_FROZEN )
end

local TransactionId = ffi.typeof('TransactionId')
local FrozenTransactionId = ffi.cast(TransactionId, 2)
local function macro_HeapTupleHeaderGetXmin(tup)
  if macro_HeapTupleHeaderXminFrozen(tup) then
    return FrozenTransactionId
  end
  
  return macro_HeapTupleHeaderGetRawXmin(tup)
end

local pg_type = require('pllj.pg.pg_type')
require('pllj.pg.array')

ffi.cdef[[
Oid	GetUserId(void);
]]
local function get_func_from_oid(oid)
  local isNull = ffi.new("bool[?]", 1)
  local proc = C.SearchSysCache(syscache.enum.PROCOID, macro_ObjectIdGetDatum(oid), 0, 0, 0);

  local procst = ffi.cast('Form_pg_proc', macro_GETSTRUCT(proc));

  local nargs = procst.pronargs;
  local argtypes = procst.proargtypes.values;
  local rettype = procst.prorettype;
  local result_isset = procst.proretset;
--  print(procst)
--  print(argtypes)
--  print(nargs)
--  print('rettype  '..rettype)

--  for i = 0, nargs-1 do
--    print('argtype '..tostring(argtypes[i]))
--    get_pg_typeinfo(argtypes[i])
--  end
  local arguments = ''
  local targtypes = {}
  local proname = 'anonymous'
  if nargs > 0 then
    local vararg = false
    local nnames = ffi.new("int[?]", 1)
    local argnames = C.SysCacheGetAttr(syscache.enum.PROCOID, proc,
      pg_proc.defines.Anum_pg_proc_proargnames, isNull)
    if isNull[0] == false then
      local argname = ffi.new 'Datum *[1]'
      C.deconstruct_array(macro_DatumGetArrayTypeP(argnames), pg_type["TEXTOID"], -1, false,
        string.byte('i'), argname, nil, nnames)

      vararg = (nargs ~= nnames[0]) 
      local targ = {}
      local ttypes = {}
      if not vararg then
        for i = 0, nnames[0] - 1 do
          local arg = builtins.pg_text_tolua(argname[0][i])
          table.insert(targ, arg)
          table.insert(ttypes, tonumber(argtypes[i]))

          if #arg == 0 then
            vararg = true
            break
          end

        end
      end
      proname = ffi.string(procst.proname.data)

      arguments = '...'
      if not vararg then
        arguments = table.concat(targ, ', ')
        targtypes = ttypes
      end

    end
  end

  local prosrc = C.SysCacheGetAttr(syscache.enum.PROCOID, proc, pg_proc.defines.Anum_pg_proc_prosrc, isNull);
  prosrc = builtins.pg_text_tolua(prosrc)
  if (isNull[0] == true) then
    error( "null prosrc for function ".. oid);
  end

  local fntext = {'local ', proname,'\n', proname, ' = function (',arguments,')\n',
    prosrc, '\nend\nreturn ',proname}

  fntext = table.concat(fntext)


  local xmin = macro_HeapTupleHeaderGetXmin(proc.t_data)
  local tid = proc.t_self;
  local user_id = C.GetUserId()

  C.ReleaseSysCache(proc)

  local fn = assert(loadstring(fntext))

  return {
    func = fn(), 
    xmin = xmin, 
    tid,
    user_id,
    result_isset = result_isset, 
    result_type = rettype, 
    argtypes = targtypes 
  }
  
end

function pllj.validator (...)

end


local typeto = require('pllj.io').typeto
local datumfor = require('pllj.io').datumfor
local FunctionCallInfo = ffi.typeof('FunctionCallInfo')

function pllj.callhandler (fcinfo)
  spi.connect()
  fcinfo = ffi.cast(FunctionCallInfo,fcinfo)
  local fn_oid = fcinfo.flinfo.fn_oid
  local func_struct = function_cache[fn_oid]

  if not func_struct then
    func_struct = get_func_from_oid(fn_oid)
    function_cache[fn_oid] = func_struct
  end
  --[[istrigger = CALLED_AS_TRIGGER(fcinfo)]]
  local args = {}
  for i = 0, fcinfo.nargs-1 do
    if fcinfo.argnull[i] == true then
      table.insert(args, NULL)
    else 
      local typeoid = func_struct.argtypes[i+1]
      local iof = typeto[typeoid]

      if not iof then
        error('no conversion for type '..typeoid)
      end
      table.insert(args, iof(fcinfo.arg[i]))
    end

  end
  local result = func_struct.func(unpack(args))
  local iof = datumfor[func_struct.result_type]

  if not iof then
    error('no conversion for type '..tostring(func_struct.result_type))
  end
  if not result --[[or result == NULL]] then
    fcinfo.isnull = true
    return
  end

  C.set_pllj_call_result(iof(result))
  spi.disconnect()

end

function pllj.inlinehandler (...)
  spi.connect()
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
