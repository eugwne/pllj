local gcc = require("gcc")
local cdecl = require("gcc.cdecl")
local fficdecl = require("ffi-cdecl")

-- send assembler output to /dev/null
gcc.set_asm_file_name(gcc.HOST_BIT_BUCKET)

-- Captured C declarations.
local decls = {}
-- Type declaration identifiers.
local types = {}

-- Parse C declaration from capture macro.
gcc.register_callback(gcc.PLUGIN_PRE_GENERICIZE, function(node)
  local decl, id = fficdecl.parse(node)

  local op = node:name():value():match("^cdecl_(.-)__(.+)")
  if decl then
    
    if decl:class() == "type" or decl:code() == "type_decl" then
      types[decl] = id
      if (id == 'bool') then
        return
      end
    end

    table.insert(decls, {decl = decl, id = id})
  end
end)

local function format_helper(node)
    if node == decl then return id end
    return types[node]
end
  
local function format(decl, id)
  
  if decl:class() == "constant" then
    return "static const int " .. id .. " = " .. decl:value()
  end
  if decl:class() == "type" and decl:code() == "enumeral_type" then
    return string.format([[struct enum_%s {
  %s;
}]], id, cdecl.declare(decl, format_helper))
  end
  return cdecl.declare(decl, format_helper)
end

local decl_names = {}
-- invoke Lua function after translation unit has been parsed
gcc.register_callback(gcc.PLUGIN_FINISH_UNIT, function()
  -- get global variables in reverse order of declaration
  
  local vars = gcc.get_variables()
  for i = #vars, 1, -1 do
    -- initial value is a string constant
    --print(vars[i]:initial():value())
  end

  local result = {}
  for i, decl in ipairs(decls) do
    local res = format(decl.decl, decl.id) .. ";"
    decl_names[decl.id] = (decl_names[decl.id] or '\n')..res..'\n'
    result[i] = res.."\n\n"
  end
  print[=[local all_types=[[]=]
  print(table.concat(result))
  print[=[]]]=]
  print('return {all_types = all_types}')
--  print('local pg_import = {}')
--  for k, v in pairs(decl_names) do
--    print(string.format("pg_import['%s'] = [[%s]]",k,v))
--  end
--  print[=[
--  local ffi = require('ffi')
--  pg_import.import = function(t)
--    local tnamed = {}
--    for i = 1, #t do
--      table.insert(tnamed, pg_import[t[i]])
--    end
--    return(table.concat(tnamed))
--  end
--
--  pg_import.all_types = all_types
--  ]=]
--  print('return pg_import')
--  print([[--total ]]..#result)
end)
