do $$
local fn = find_function('quote_nullable(text)')
print(fn("qwerty"))
print(fn(nil))
$$ language pllj;

create or replace function pg_temp.get_json() returns json as $$
select '{"a":5, "b":10}'::json
$$ language sql;

do $$
    local get_json = load_function('pg_temp.get_json()')
    print(get_json())
$$ language pllj;

create or replace function pg_temp.get_json() returns json as $$
select '{"a":50, "b":100}'::json
$$ language sql;

do $$
local get_json = load_function('pg_temp.get_json()')
print(get_json())
print(type(get_json()[-1]))
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


CREATE or replace FUNCTION pg_temp.arg_count(a1 integer,a2 integer,a3 integer,a4 integer,a5 integer
,a6 integer,a7 integer,a8 integer,a9 integer,a10 integer
,a11 integer,a12 integer,a13 integer,a14 integer,a15 integer ) returns integer AS
$$
begin
return a1+a2+a3+a4+a5+a6+a7+a8+a9+a10+a11+a12+a13+a14+a15;
end
$$
LANGUAGE plpgsql;

do $$
  local f = find_function([[pg_temp.arg_count(integer, integer, integer, integer, integer,
  integer, integer, integer, integer, integer, 
  integer, integer, integer, integer, integer ) ]]);
  print(f(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15))
$$ language pllj;

CREATE TYPE pg_temp._pair AS (first text, second text);
CREATE OR REPLACE FUNCTION pg_temp.get_pair () RETURNS pg_temp._pair AS $$
select '("one","two")'::pg_temp._pair;
$$ LANGUAGE sql;

select pg_temp.get_pair ();

do $$
local f = find_function('pg_temp.get_pair ()')
local result = f()
print(result.first)
print(result.second)
$$ language pllj;

do $$
local f = find_function('generate_series(int,int)')
for rr in f(1,3) do

	for rr in f(41,43) do
		print(rr)
	end
	print(rr)
end
$$ language pllj;
