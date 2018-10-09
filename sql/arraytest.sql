CREATE or replace FUNCTION echo_arr_int4(arg int4[]) RETURNS int4[] AS $$ 
if arg ~= nil then
    for k,v in pairs(arg) do
    print(tostring(k).. ' : '..tostring(v))
    end
end
if arg[-1] then
    return {[-2] = 5, [2] = 10}
end
return arg
$$ LANGUAGE pllj;

select quote_nullable(echo_arr_int4(NULL::int4[]));
SELECT echo_arr_int4('{}'::int4[]);
SELECT echo_arr_int4(array[1, 2, 3]::int4[]);
SELECT echo_arr_int4(array[NULL, NULL, 7]::int4[]);
select echo_arr_int4('[-1:0]={2,NULL}'::int4[]);

