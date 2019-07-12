CREATE or replace FUNCTION pg_temp.inoutf(a integer, INOUT b text, INOUT c text)  AS
$$
begin
c = a||'c:'||c;
b = 'b:'||b;
end
$$
LANGUAGE plpgsql;

do $$
local a = spi.execute("SELECT pg_temp.inoutf(5, 'ABC', 'd') as val ");
local r = a[1][1]
print(r.b)
print(r.c)
$$ language pllj;

do $$
local f = find_function('pg_temp.inoutf(integer,text,text)',{only_internal=false});
local r = f(5, 'ABC', 'd')
print(r.b)
print(r.c)
$$ language pllj;

CREATE FUNCTION test_in_out_params(first in text, second out text) AS $$
return first .. '_in_to_out';
$$ LANGUAGE pllj;

SELECT * FROM test_in_out_params('test_in');

CREATE FUNCTION test_in_out_params_multi(first in text,
                                         second out text, third out text) AS $$
return {first .. '_record_in_to_out_1', first .. '_record_in_to_out_2'};
$$ LANGUAGE pllj;

SELECT * FROM test_in_out_params_multi('test_in');

CREATE FUNCTION test_inout_params(first inout text) AS $$
return first .. '_inout';
$$ LANGUAGE pllj;

SELECT * FROM test_inout_params('test_in');
