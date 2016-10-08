local ffi = require('ffi')
local p = require('pllj.pg.i')
local def = 
[[
struct pg_proc_def { ]]..
  p['Anum_pg_proc_proargnames']..
  p['Anum_pg_proc_prosrc']..
[[	};
]]
ffi.cdef(def)
local defines = ffi.new("struct pg_proc_def")
return {defines = defines}