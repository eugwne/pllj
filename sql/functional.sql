do $$
local f = require('pllj.func')
local fn = f.find_function('quote_nullable(text)')
print(fn("qwerty"))
print(fn(nil))
$$ language pllj;

create or replace function pg_temp.get_json() returns jsonb as $$
select '{"a":5, "b":10}'::jsonb
$$ language sql;

do $$
    local fn = require('pllj.func').find_function('pg_temp.get_json()')
    _G.get_json = fn
    print(get_json())
$$ language pllj;

create or replace function pg_temp.get_json() returns jsonb as $$
select '{"a":50, "b":100}'::jsonb
$$ language sql;

do $$
print(get_json())
$$ language pllj;

drop function pg_temp.get_json();

do $$
    local _, e = pcall(get_json)
    print(string.find(e, "cache lookup failed for function")~=nil)
$$ language pllj;