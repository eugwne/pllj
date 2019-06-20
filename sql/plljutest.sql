CREATE EXTENSION pllju;

do $$
assert(__untrusted__)
print("LuaJIT unrestricted")
$$ language pllju;

do $$
local f = require('pllj.func')
local fn = f.find_function('quote_nullable(text)')
print(fn("qwerty"))
print(fn(nil))
$$ language pllju;

create or replace function pg_temp.get_json() returns jsonb as $$
select '{"a":5, "b":10}'::jsonb
$$ language sql;

do $$
    local get_json = save_function('pg_temp.get_json()')
    print(get_json())
$$ language pllju;

create or replace function pg_temp.get_json() returns jsonb as $$
select '{"a":50, "b":100}'::jsonb
$$ language sql;

do $$
local get_json = load_function('pg_temp.get_json()')
print(get_json())
$$ language pllju;

create or replace function pg_temp.get_json() returns jsonb as $$
select '{"a":5, "b":10}'::jsonb
$$ language sql;

do $$
    g_json = find_function('pg_temp.get_json()')
    print(g_json())
    print(type(g_json()[1]))
$$ language pllju;

create or replace function pg_temp.get_json() returns jsonb as $$
select '{"a":50, "b":100}'::jsonb
$$ language sql;

CREATE or replace FUNCTION pg_temp.add(integer, integer) RETURNS integer
AS 'select $1 + $2;'
LANGUAGE SQL;

do $$
    spi.prepare("select * from pg_temp.add($1,$2);", "integer", "integer"):save_as('plan pg_temp.add')
$$ language pllju;

do $$
    local plan = spi.find_plan('plan pg_temp.add')
    local result = plan:exec(4, 7)
    for _, row in ipairs(result) do
      print(unpack(row))
    end
$$ language pllju;

do $$
    g_plan = spi.prepare("select * from pg_temp.add($1,$2);", "integer", "integer")
$$ language pllju;

do $$
    local plan = g_plan
    local result = plan:exec(4, 7)
    for _, row in ipairs(result) do
      print(unpack(row))
    end
$$ language pllju;