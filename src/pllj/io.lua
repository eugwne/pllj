local builtins = require('pllj.pg.builtins')
local pg_type = require('pllj.pg.pg_type')

local typeto = {
  [pg_type["INT4OID"]] = builtins.pg_int_tolua,
  [pg_type["TEXTOID"]] = builtins.pg_text_tolua 
}

return {typeto = typeto}