CREATE FUNCTION pg_temp.jtest1(val jsonb) RETURNS int
LANGUAGE pllj
AS $$
print(val.a)
print(val.c)
return 0
$$;
SELECT pg_temp.jtest1('{"a": 1, "c": "NULL"}'::jsonb);

CREATE FUNCTION pg_temp.jtest2(val jsonb) RETURNS jsonb
LANGUAGE pllj
AS $$
if type(val) == "string" then
    print(val)
end

print(val[1])
print(val[2])
print(val[3])

return val
$$;
SELECT pg_temp.jtest2('["a", "b", "c"]'::jsonb);

SELECT pg_temp.jtest2(to_json('just text'::text)::jsonb);

CREATE FUNCTION pg_temp.jtestNULL() RETURNS jsonb
LANGUAGE pllj
AS $$
return NULL
$$;

CREATE FUNCTION pg_temp.jtestNil() RETURNS jsonb
LANGUAGE pllj
AS $$
return nil
$$;

SELECT quote_nullable(pg_temp.jtestNULL()) lj_null, 
       quote_nullable(pg_temp.jtestNil())  lj_nil, 
       quote_nullable('null'::jsonb)       js_null;


CREATE FUNCTION pg_temp.jtestStr() RETURNS jsonb
LANGUAGE pllj
AS $$
return "test string"
$$;

SELECT pg_temp.jtestStr();

CREATE FUNCTION pg_temp.jtestBool() RETURNS jsonb
LANGUAGE pllj
AS $$
return 1==1
$$;

SELECT pg_temp.jtestBool();

CREATE FUNCTION pg_temp.jtestN() RETURNS jsonb
LANGUAGE pllj
AS $$
return 5.5
$$;

SELECT pg_temp.jtestN();


CREATE FUNCTION pg_temp.jtestOb() RETURNS jsonb
LANGUAGE pllj
AS $$
return {a = 5}
$$;

SELECT pg_temp.jtestOb();

CREATE FUNCTION pg_temp.jtestOb2() RETURNS jsonb
LANGUAGE pllj
AS $$
return {a = 5, b = { c = { d = 10}}}
$$;

SELECT pg_temp.jtestOb2();

CREATE FUNCTION pg_temp.jtestOb3() RETURNS jsonb
LANGUAGE pllj
AS $$
local v =  {a = 5}
v.b = v
return v
$$;

SELECT pg_temp.jtestOb3();

CREATE FUNCTION pg_temp.jtestObz() RETURNS jsonb
LANGUAGE pllj
AS $$
return {}
$$;

SELECT pg_temp.jtestObz();

CREATE FUNCTION pg_temp.jtestOb4() RETURNS jsonb
LANGUAGE pllj
AS $$
return {1,2,nil,4}
$$;

SELECT pg_temp.jtestOb4();

CREATE FUNCTION pg_temp.jtestOb4n() RETURNS jsonb
LANGUAGE pllj
AS $$
return {nil,4}
$$;

SELECT pg_temp.jtestOb4n();

CREATE FUNCTION pg_temp.jtestOb4z() RETURNS jsonb
LANGUAGE pllj
AS $$
return {[0] = 4}
$$;

SELECT pg_temp.jtestOb4z();

CREATE FUNCTION pg_temp.jtestOb41() RETURNS jsonb
LANGUAGE pllj
AS $$
return {1, 2, NULL, 4}
$$;

SELECT pg_temp.jtestOb41();

CREATE FUNCTION pg_temp.jtestOb5() RETURNS jsonb
LANGUAGE pllj
AS $$
return {[0]=1, 2, NULL, 4}
$$;

SELECT pg_temp.jtestOb5();

CREATE FUNCTION pg_temp.jtestOb6() RETURNS jsonb
LANGUAGE pllj
AS $$
return {1, ["q"]=5, nil, 6}
$$;

SELECT pg_temp.jtestOb6();

