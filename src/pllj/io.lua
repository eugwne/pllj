local builtins = require('pllj.pg.builtins')
local pg_type = require('pllj.pg.pg_type')

local typeto = {
  [pg_type["INT4OID"]] = builtins.pg_int_tolua,
  [pg_type["TEXTOID"]] = builtins.pg_text_tolua 
}

local datumfor = {
  [pg_type["INT4OID"]] = builtins.lua_int4pg,
}

local function datum_to_value(datum, atttypid)

  local func = typeto[atttypid]
  if (func) then
    return func(datum)
  end
  return datum --TODO other types
  --print("SC = "..tonumber(syscache.enum.TYPEOID))
  --type = C.SearchSysCache(syscache.enum.TYPEOID, ObjectIdGetDatum(oid), 0, 0, 0);
end

return {
  typeto = typeto, 
  datumfor = datumfor, 
  datum_to_value = datum_to_value
}