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

CREATE OR REPLACE FUNCTION validation_error()
  RETURNS integer AS
$BODY$
ret value
$BODY$ LANGUAGE pllj;

CREATE FUNCTION echo_int2(arg int2) RETURNS int2 AS $$ return arg $$ LANGUAGE pllj;
SELECT echo_int2('12345');
CREATE FUNCTION echo_int4(arg int4) RETURNS int4 AS $$ return arg $$ LANGUAGE pllj;
SELECT echo_int4('1234567890');
CREATE FUNCTION echo_int8(arg int8) RETURNS int8 AS $$ return arg $$ LANGUAGE pllj;
SELECT echo_int8('1234567890123456789');
CREATE FUNCTION int64_minus_one(value bigint)
RETURNS bigint AS $$
  return value - 1;
$$ LANGUAGE pllj;
select int64_minus_one(9223372036854775807);
CREATE FUNCTION echo_text(arg text) RETURNS text AS $$ return arg $$ LANGUAGE pllj;
SELECT echo_text('qwe''qwe');


CREATE TABLE table_1
(
   id serial,
   column_1 int8
) ;

CREATE FUNCTION pllj_t1() RETURNS trigger AS $$
  print('trigger call column_1 = '..  tostring(trigger.row.column_1))
  local value = trigger.row.column_1
  if value > 10 then
    trigger.row.column_1 = value * 2
  end
$$ LANGUAGE pllj;

CREATE TRIGGER bi_table_1 BEFORE INSERT OR UPDATE OR DELETE ON table_1
  FOR EACH ROW EXECUTE PROCEDURE pllj_t1();
insert into table_1 (column_1) values(5);
insert into table_1 (column_1) values(15);
select column_1 from table_1 order by 1;

do $$
    local spi = require("pllj.spi")
    local plan = spi.prepare("select * from generate_series($1,$2);", {"bigint", "bigint"})
    local result = plan:exec(4, 7)

    for _, row in ipairs(result) do
      print(unpack(row))
    end
$$ language pllj;

CREATE or replace FUNCTION pg_temp.add(integer, integer) RETURNS integer
AS 'select $1 + $2;'
LANGUAGE SQL;

do $$
    local spi = require("pllj.spi")
    _G.plan = spi.prepare("select * from pg_temp.add($1,$2);", {"integer", "integer"})
$$ language pllj;

do $$
    local result = plan:exec(4, 7)
    for _, row in ipairs(result) do
      print(unpack(row))
    end
$$ language pllj;

drop function pg_temp.add(integer, integer);

do $$
    local _, e = pcall(plan.exec, plan, 4, 7)
    print(string.find(e, "function pg_temp.add")~=nil and string.find(e, "does not exist")~=nil)
$$ language pllj;

do $$
    local spi = require("pllj.spi")
    local _, e = pcall(spi.execute, "select * from pg_temp.add(1,2);")
    print(string.find(e, "function pg_temp.add")~=nil and string.find(e, "does not exist")~=nil)
$$ language pllj;