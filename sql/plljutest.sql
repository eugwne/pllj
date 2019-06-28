CREATE EXTENSION pllju;

do $$
assert(__untrusted__)
print("LuaJIT unrestricted")
$$ language pllju;

do $$
    ffi = require('ffi')
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
    local plan = spi.prepare("select * from pg_temp.add($1,$2);", "integer", "integer"):save_as('del')
    intptr_counter = ffi.cast("int*", plan[1])
    collectgarbage('collect')
    print('ref_count ' .. intptr_counter[0])
    plan = spi.find_plan('del')
    print('ref_count ' .. intptr_counter[0])
    collectgarbage('collect')
    print('ref_count ' .. intptr_counter[0])
$$ language pllju;

do $$
    collectgarbage('stop')
    local plan = spi.prepare("select * from pg_temp.add($1,$2);", "integer", "integer"):save_as('plan pg_temp.add')
    intptr_counter = ffi.cast("int*", plan[1])
$$ language pllju;

do $$
    print('ref_count ' .. intptr_counter[0])
$$ language pllju;

do $$
    local plan = spi.find_plan('plan pg_temp.add')
    local result = plan:exec(4, 7)
    for _, row in ipairs(result) do
      print(unpack(row))
    end
$$ language pllju;

do $$
    for i = 1, 100000 do
        spi.get_saved_plan_names()
    end
    local plan_names = spi.get_saved_plan_names()
    for _, v in ipairs(plan_names) do
        print(v)
    end
$$ language pllju;

do $$
    local _, e = pcall(spi.free_plan, 'delete')
    print(string.find(e, "free_plan")~=nil and string.find(e, "not found")~=nil)
    local p = spi.prepare("select 1;")
    _, e = pcall(p.save_as, p, 'del')
    print(string.find(e, "plan")~=nil and string.find(e, "already exists")~=nil)
$$ language pllju;

do $$
    print('ref_count ' .. intptr_counter[0])
$$ language pllju;

do $$
    local plan = spi.find_plan('plan pg_temp.add')
    print(plan[1].base.ref_count)
    print('++++++++++++')
    collectgarbage('restart')
    collectgarbage('collect')
    print('-----------')
    spi.free_plan('plan pg_temp.add')
    local result = plan:exec(4, 7)
    print('1 == ' .. plan[1].base.ref_count)
    for _, row in ipairs(result) do
      print(unpack(row))
    end
$$ language pllju;

do $$
    local plan = spi.prepare("select * from pg_temp.add($1,$2);", "integer", "integer")
    intptr_counter = ffi.cast("int*", plan[1])
    print('ref_count ' .. intptr_counter[0])
    local p2 = plan:save_as('del2')
    print('ref_count ' .. intptr_counter[0])
    spi.free_plan('del2')
    print('ref_count ' .. intptr_counter[0])
    p2 = nil
    collectgarbage('collect')
    print('ref_count ' .. intptr_counter[0])
    plan:exec(4, 7)
    plan = nil
    collectgarbage('collect')
    print('dirty read freed memory, ref_count ' .. intptr_counter[0])

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