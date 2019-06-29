CREATE TYPE text_pair AS (first text, second text);
CREATE OR REPLACE FUNCTION pg_temp.cmpz (g text_pair, f text) RETURNS text_pair AS $$
  print(g)
  print (string.format(f, g.first, g.second))
  return g
$$ LANGUAGE pllju;

SELECT pg_temp.cmpz(('one', 'two'), '%s, %s!');


create type type1 as (a text, b int, c boolean);
create type type2 as (a type1, b boolean);
create type type3 as (a type2, b int);

CREATE OR REPLACE FUNCTION pg_temp.cmpz2 (v type3) RETURNS type3 AS $$
  print(v)
  print ('v.b =', v.b)
  print('v.a.b =', v.a.b)
  print('v.a.a.c =', v.a.a.c)
  print('v.a.a.b =', v.a.a.b)
  print('v.a.a.a =', v.a.a.a)
  v.a.a.a = 'updated value'
  print('v.a.a.a =', v.a.a.a)
  print(v)
  return v
$$ LANGUAGE pllju;

SELECT pg_temp.cmpz2(((('testvalue',20,true), false), 10));
SELECT pg_temp.cmpz2(((('testvalue',null,true), null), 10));

CREATE OR REPLACE FUNCTION pg_temp.cmpz3 (v type3) RETURNS type3 AS $$
  print(v)
  print('v.b =', v.b)
  print('v.a.b =', v.a.b)
  print('v.a.a =', v.a.a)
  print(v)
  v.a.a = "('string value',40,false)"
  assert(tostring(v) ~= '("(,f)",10)') 
  print(v)
  return v
$$ LANGUAGE pllju;
SELECT pg_temp.cmpz3(((null, false), 10));

CREATE OR REPLACE FUNCTION pg_temp.cmpz (g text_pair) RETURNS text_pair AS $$
  print(g)
  print (g.first)
  print (g.second)
  local f = g.first
  g.first = g.second
  g.second = f
  return g
$$ LANGUAGE pllju;



SELECT pg_temp.cmpz(('one', null));