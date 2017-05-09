CREATE or replace FUNCTION echo_new_arr(arg text[]) RETURNS text[] AS $$ 
return '{d,e}' 
$$ LANGUAGE pllj;

CREATE or replace FUNCTION echo_arr(arg text[]) RETURNS text[] AS $$ 
return arg
$$ LANGUAGE pllj;

SELECT echo_new_arr(array['a', 'b', 'c']);
SELECT echo_arr(array['a', 'b', 'c']);
