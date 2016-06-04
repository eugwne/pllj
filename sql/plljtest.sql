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
