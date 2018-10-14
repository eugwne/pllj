CREATE or replace FUNCTION echo_new_arr(arg text[]) RETURNS text[] AS $$ 
return '{d,e}' 
$$ LANGUAGE pllj;

CREATE or replace FUNCTION echo_arr(arg text[]) RETURNS text[] AS $$ 
return arg
$$ LANGUAGE pllj;

SELECT echo_new_arr(array['a', 'b', 'c']);
SELECT echo_arr(array['a', 'b', 'c']);


CREATE or replace FUNCTION echo_arr_err() RETURNS text[] AS $$ 
return '{d,' 
$$ LANGUAGE pllj;

do $$
    local _, e = pcall(spi.execute, "SELECT echo_arr_err();")
    print(string.find(e, "malformed array literal")~=nil)
$$ language pllj;