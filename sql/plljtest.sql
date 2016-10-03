\set ECHO none
CREATE EXTENSION pllj;
\set ECHO all

do $$
print("Hello LuaJIT FFI")
$$ language pllj;

create table pg_temp.test(txt text);

do $$
local spi = require("pllj.spi")
spi.execute("insert into pg_temp.test(txt) values('qwerty')")
$$ language pllj;

select * from pg_temp.test;

do $$
local spi = require("pllj.spi")
local result = spi.execute("select null union all select generate_series(7,9)")
for _, row in ipairs(result) do
	for _, col in ipairs(row) do
		print (tonumber(col))
	end
end
result = spi.execute("select 'test'::text ")
print(result[1][1])
$$ language pllj;
CREATE OR REPLACE FUNCTION pg_temp.echo(val integer)
  RETURNS integer AS
$$
if val < 3 then
	return nil
end
return val * 2
$$  LANGUAGE pllj;
select g, quote_nullable(pg_temp.echo(g)) from generate_series(1,5) as g;

CREATE OR REPLACE FUNCTION public.sum_values(a integer, b integer, c integer)
  RETURNS integer AS
$$ return a+b+c $$ language pllj;

do $$
local spi = require("pllj.spi")
for i = 5,10 do
local result = spi.execute(string.format ("select sum_values(%s,%s,%s)", i, i*2, i*3))
print(result[1][1])
end
$$ language pllj;

CREATE OR REPLACE FUNCTION public.rec_spi(n integer)
  RETURNS integer AS
$BODY$
local function call_spi(value)
	local spi = require("pllj.spi")
	local result = spi.execute(string.format ("select rec_spi(%s)", value))
	return(result[1][1])
end
  if n < 2 then
    return n
  else
    return call_spi(n - 1)+n
  end
$BODY$ LANGUAGE pllj;

select rec_spi(50);

CREATE FUNCTION get_max(a integer, b integer) RETURNS integer AS $$
  if a == nil then return b end
  if b == nil then return a end
  return a > b and a or b
$$ LANGUAGE pllj;
SELECT quote_nullable(get_max(1,2)), 
quote_nullable(get_max(2,1)), 
quote_nullable(get_max(2,null)), 
quote_nullable(get_max(null, 2)), 
quote_nullable(get_max(null, null));

CREATE or replace FUNCTION pg_temp.get_temp_val() RETURNS integer AS $$
  return 5
$$ LANGUAGE pllj;
SELECT pg_temp.get_temp_val();

CREATE or replace FUNCTION pg_temp.get_temp_val() RETURNS integer AS $$
  return 9
$$ LANGUAGE pllj;
SELECT pg_temp.get_temp_val();
