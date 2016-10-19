local _ = require('pllj.pg.builtins')
local pg_type = require('pllj.pg.pg_type')

local typeto = {}

local datumfor = {}

for k, v in pairs(pg_type) do
  typeto[v.oid] = v.tolua 
  datumfor[v.oid] = v.topg
end




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