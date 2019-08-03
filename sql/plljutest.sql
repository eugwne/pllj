set pllju.on_init = $$ 
function print_result(result)
    print('__________')
    for _, row in ipairs(result) do
        print('|', unpack(row))
    end
    print('----------')
end 
$$;

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
    local get_json = load_function('pg_temp.get_json()')
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
    print(type(g_json()[-1]))
$$ language pllju;

create or replace function pg_temp.get_json() returns jsonb as $$
    select '{"a":50, "b":100}'::jsonb
$$ language sql;

CREATE or replace FUNCTION pg_temp.add(integer, integer) RETURNS integer
AS 'select $1 + $2;'
LANGUAGE SQL;

do $$
    local plan = spi.prepare("select * from pg_temp.add($1,$2);", {"integer", "integer"}):save_as('del')
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
    local plan = spi.prepare("select * from pg_temp.add($1,$2);", {"integer", "integer"}):save_as('plan pg_temp.add')
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
    local plan = spi.prepare("select * from pg_temp.add($1,$2);", {"integer", "integer"})
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
    g_plan = spi.prepare("select * from pg_temp.add($1,$2);", {"integer", "integer"})
$$ language pllju;

do $$
    local plan = g_plan
    local result = plan:exec(4, 7)
    for _, row in ipairs(result) do
      print(unpack(row))
    end
$$ language pllju;

do $$
local f = find_function('generate_series(int,int)')
local f1 = f(5,10)
print(f1())
f1 = nil
local f2 = f(2,2)
for r in f2 do
end
local f3 = f(1,10)
f3 = nil
collectgarbage('collect')
$$ language pllju;

CREATE TABLE sometable ( sid int4, sname text, sdata text);
INSERT INTO sometable VALUES (1, 'uno', 'data');
INSERT INTO sometable VALUES (2, 'dos', 'data');
INSERT INTO sometable VALUES (3, 'tres', 'data');
INSERT INTO sometable VALUES (4, 'quatro', 'data');
INSERT INTO sometable VALUES (5, 'cinco', 'data');

BEGIN;
do $$
    cursor = spi.cursor("select * from sometable")
$$ language pllju;
ROLLBACK;

do $$
    local _, e = pcall(cursor.close, cursor)
    print(string.find(e, "cursor deleted")~=nil)
$$ language pllju;



BEGIN;
do $$
    cursor = spi.cursor("select * from sometable")
$$ language pllju;

do $$
    cursor:close()
$$ language pllju;

ROLLBACK;

do $$
    cursor = spi.cursor("select * from sometable")
    cursor:close()
    local _, e = pcall(cursor.close, cursor)
    print(string.find(e, "cursor deleted")~=nil)
$$ language pllju;

do $$
    local cursor = spi.cursor("select * from sometable")
    print_result(cursor:fetch())
    print_result(cursor:fetch())
    print_result(cursor:fetch(-2))
    cursor = nil
    collectgarbage('collect')
    cursor = spi.cursor("select * from sometable")

    print_result(cursor:fetch(4))
    print_result(cursor:fetch(-2))
    print('move')
    cursor:move(1, 'a')
    print_result(cursor:fetch(1))
    cursor:move(1)
    print_result(cursor:fetch(1))
    cursor:move(10)
    print_result(cursor:fetch(1))
    cursor:move(2, 'b')
    print_result(cursor:fetch(1))
    cursor:move(-2)
    print_result(cursor:fetch(1))
    cursor:close()

$$ language pllju;

BEGIN;
do $$
    plan = spi.prepare("select * from sometable where sid > $1 ;", {"integer"})
    cursor = plan:cursor(1)
    cursor3 = plan:cursor(3)
    print_result(cursor:fetch(1))
    print_result(cursor3:fetch(1))
    print_result(cursor:fetch(1))
    print_result(cursor3:fetch(1))
$$ language pllju;

do $$
    print_result(cursor:fetch(1))
    print_result(cursor3:fetch(1))
$$ language pllju;
ROLLBACK;

do $$
    cursor = plan:cursor(1)
    cursor3 = plan:cursor(3)
    print_result(cursor:fetch(1))
    print_result(cursor3:fetch(1))
    print_result(cursor:fetch(1))
    print_result(cursor3:fetch(1))
$$ language pllju;

do $$
    local _, e = pcall(cursor.close, cursor)
    print(string.find(e, "cursor deleted")~=nil)
    _, e = pcall(cursor.close, cursor3)
    print(string.find(e, "cursor deleted")~=nil)
$$ language pllju;


do $$
    local m = 0
    for r in spi.rows('select generate_series(1,500000)') do
        assert(r[1] - m == 1)
        m = math.max(r[1], m)
    end
    print(m)
$$ language pllju;


do $$
    local plan = spi.prepare("select generate_series($1,$2)", {"int", "int"})
    local m = 0
    for i in plan:rows(1,3) do
        for k in plan:rows(4,6) do
            for l in plan:rows(7,9) do
                print(i[1], k[1], l[1])
            end
        end
    end

$$ language pllju;


do $$
    local cursor = plan:named_cursor("cursor_name", 1)
    local _, e = pcall(plan.named_cursor, plan, "cursor_name", 3)
    print(string.find(e, 'cursor "cursor_name" already exists')~=nil)
    cursor = nil
    collectgarbage("collect")
    collectgarbage("collect")
$$ language pllju;


BEGIN;
do $$
    plan = spi.prepare("select * from sometable where sid > $1 ;", {"integer"})
    plan:named_cursor("cursor 4", 4)
$$ language pllju;

do $$
    local c = spi.find_cursor("cursor 4")
    print(c)
    print_result(c:fetch(10))
$$ language pllju;
ROLLBACK;

do $$
    local _, e = spi.find_cursor("cursor 4")
    print(string.find(e, "cursor not found")~=nil)
$$ language pllju;

CREATE or replace FUNCTION pg_temp.get_temp_cursor() RETURNS text AS $$
    plan = spi.prepare("select * from sometable where sid > $1 ;", {"integer"})
    plan:named_cursor("get_temp_cursor", 2)
    return "get_temp_cursor"
$$ LANGUAGE pllju;

do $$
    local curname = spi.execute("select pg_temp.get_temp_cursor()")[1][1]
    local c = spi.find_cursor(curname)
    print(c)
    print_result(c:fetch(10))
$$ language pllju;

do $$
    local curname = spi.execute("select pg_temp.get_temp_cursor()")[1][1]
    collectgarbage('collect')
    local c = spi.find_cursor(curname)
    print(c)
    print_result(c:fetch(10))
$$ language pllju;

BEGIN;
do $$
    plan = spi.prepare("select * from sometable where sid > $1 ;", {"integer"})
    del = plan:named_cursor("del", 4)
$$ language pllju;
ROLLBACK;

do $$
    local _, e = pcall(del.fetch, del, 1)
    print(string.find(e, "cursor deleted")~=nil)
    _, e = pcall(del.move, del, 1)
    print(string.find(e, "cursor deleted")~=nil)
    _, e = pcall(del.close, del)
    print(string.find(e, "cursor deleted")~=nil)
    _, e = spi.find_cursor("del")
    print(string.find(e, "cursor not found")~=nil)
$$ language pllju;

