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
print(type(get_json()[1]))
$$ language pllj;

drop function pg_temp.get_json();

do $$
    local get_json = load_function('pg_temp.get_json()')
    local _, e = pcall(get_json)
    print(string.find(e, "cache lookup failed for function")~=nil)
$$ language pllj;

CREATE or replace FUNCTION pg_temp.concat_3(text, text, text) RETURNS text
AS 'select quote_nullable($1) || quote_nullable($2) || quote_nullable($3);'
LANGUAGE SQL;

do $$
local fn = find_function('pg_temp.concat_3(text, text, text)')
print(fn('1'))
print(fn('1',nil,'3'))
print(fn('1','2','3'))
print(fn(nil,'2','3'))
$$ language pllj;
