create function pg_temp.t1()
  returns setof integer
  language pllju
  as $$
    for i = 1,4 do
      local _, e = pcall(spi.execute , "select * from pg_temp.t1()")
      if __depth__ ~= 0 then
        error(e)
      else
        local found = (string.find(e, "SPI execute error: stack depth limit exceeded")~=nil)
        if found then 
            error("SPI execute error: stack depth limit exceeded")
        else
            error(e)
        end
      end
      coroutine.yield(i)
    end
$$;

select * from pg_temp.t1();
