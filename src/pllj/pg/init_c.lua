local ffi = require('ffi')
local all_types = require('pllj.pg.i').all_types
ffi.cdef(all_types)
