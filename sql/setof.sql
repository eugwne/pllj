CREATE OR REPLACE FUNCTION pg_temp.srf()
RETURNS SETOF integer AS $$
  coroutine.yield(1)
  coroutine.yield(nil)
  coroutine.yield(2)
  coroutine.yield()
  coroutine.yield(3)
  coroutine.yield(NULL)
  coroutine.yield(4)
$$ LANGUAGE pllj;

select quote_nullable(pg_temp.srf());

create function pg_temp.tf2()
  returns setof integer
  language pllj
  as $f$
    for i = 1,4 do coroutine.yield(i) end
$f$;

select * from generate_series(1,3) i, lateral (select pg_temp.tf2() limit i) s;

create function pg_temp.t1()
  returns setof integer
  language pllj
  as $$
      assert(__depth__ == nil)
$$;

select * from pg_temp.t1();

create function pg_temp.t2()
  returns setof integer
  language pllj
  as $$
    for i = 1,4 do coroutine.yield(i) end
$$;

select pg_temp.t2(), pg_temp.t2();

create function pg_temp.t3() returns setof type3 as $$
    coroutine.yield({{{'testvalue', 20, true}, false}, 10}) 
    coroutine.yield({a = { a = { a = 'testvalue', b = 20, c = true}, b = false}, b = 10}) 

$$  language pllj;

select pg_temp.t3();
