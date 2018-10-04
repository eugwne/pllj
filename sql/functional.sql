do $$
local fn = find_function('quote_nullable(text)')
print(fn("qwerty"))
print(fn(nil))
$$ language pllj;

create or replace function pg_temp.get_json() returns jsonb as $$
select '{"a":5, "b":10}'::jsonb
$$ language sql;

do $$
    local get_json = save_function('pg_temp.get_json()')
    print(get_json())
$$ language pllj;

create or replace function pg_temp.get_json() returns jsonb as $$
select '{"a":50, "b":100}'::jsonb
$$ language sql;

do $$
local get_json = load_function('pg_temp.get_json()')
print(get_json())
$$ language pllj;

drop function pg_temp.get_json();

do $$
    local get_json = load_function('pg_temp.get_json()')
    local _, e = pcall(get_json)
    print(string.find(e, "cache lookup failed for function")~=nil)
$$ language pllj;