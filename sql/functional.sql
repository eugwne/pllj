do $$
local f = require('pllj.func')
local fn = f.find_function('quote_nullable(text)')
print(fn("qwerty"))
print(fn(nil))
$$ language pllj
