CREATE or replace FUNCTION echo_arr_int(arg int4[]) RETURNS int4[] AS $$ 
if arg ~= nil then
    for k,v in pairs(arg) do
    print(tostring(k).. ' : '..tostring(v))
    end
    if arg[-1] then
        return {[-2] = 5, [2] = 10}
    end
end

return arg
$$ LANGUAGE pllj;

CREATE or replace FUNCTION echo_arr_int(arg int2[]) RETURNS int2[] AS $$ 
if arg ~= nil then
    for k,v in pairs(arg) do
    print(tostring(k).. ' : '..tostring(v))
    end
    if arg[-1] then
        --TODO wraparound or error
        return {[-2] = 5, [2] = 256*256 + 10}
    end
end
return arg
$$ LANGUAGE pllj;

CREATE or replace FUNCTION echo_arr_int(arg int8[]) RETURNS int8[] AS $$ 
if arg ~= nil then
    for k,v in pairs(arg) do
    print(tostring(k).. ' : '..tostring(v))
    end
    if arg[-1] then
        return {[-2] = 5, [2] = 256*256 + 10}
    end
end
return arg
$$ LANGUAGE pllj;

CREATE or replace FUNCTION echo_text_arr(arg text[]) RETURNS text[] AS $$ 
if arg ~= nil then
    arg[2]= "q"
end
return arg
$$ LANGUAGE pllj;

CREATE or replace FUNCTION echo_arr_float(arg float4[]) RETURNS float4[] AS $$ 
 if arg ~= nil then
    for k,v in pairs(arg) do
    print(tostring(k).. ' : '..tostring(v))
    end
    if arg[-1] then
        return {[-2] = 5.2, [2] = 10.7}
    end
end
$$ LANGUAGE pllj;

CREATE or replace FUNCTION echo_arr_float(arg float8[]) RETURNS float8[] AS $$ 
 if arg ~= nil then
    for k,v in pairs(arg) do
    print(tostring(k).. ' : '..tostring(v))
    end
    if arg[-1] then
        return {[-2] = 5.2, [2] = 10.7}
    end
end
$$ LANGUAGE pllj;

select quote_nullable(echo_arr_int(NULL::int4[]));
SELECT echo_arr_int('{}'::int4[]);
SELECT echo_arr_int(array[1, 2, 3]::int4[]);
SELECT echo_arr_int(array[NULL, NULL, 7]::int4[]);
select echo_arr_int('[-1:0]={2,NULL}'::int4[]);

select quote_nullable(echo_arr_int(NULL::int2[]));
SELECT echo_arr_int('{}'::int2[]);
SELECT echo_arr_int(array[1, 2, 3]::int2[]);
SELECT echo_arr_int(array[NULL, NULL, 7]::int2[]);
select echo_arr_int('[-1:0]={2,NULL}'::int2[]);

select quote_nullable(echo_arr_int(NULL::int8[]));
SELECT echo_arr_int('{}'::int8[]);
SELECT echo_arr_int(array[1, 2, 3]::int8[]);
SELECT echo_arr_int(array[NULL, NULL, 7]::int8[]);
select echo_arr_int('[-1:0]={2,NULL}'::int8[]);


select quote_nullable(echo_text_arr(NULL::text[]));
SELECT echo_text_arr('{}'::text[]);
SELECT echo_text_arr(array[NULL, NULL, 'a']::text[]);


select quote_nullable(echo_arr_float(NULL::float4[]));
SELECT echo_arr_float('{}'::float4[]);
SELECT echo_arr_float(array[1.3, 2.5, 3.7]::float4[]);
SELECT echo_arr_float(array[NULL, NULL, 7.2]::float4[]);
select echo_arr_float('[-1:0]={2.1,NULL}'::float4[]);


select quote_nullable(echo_arr_float(NULL::float8[]));
SELECT echo_arr_float('{}'::float8[]);
SELECT echo_arr_float(array[1.3, 2.5, 3.7]::float8[]);
SELECT echo_arr_float(array[NULL, NULL, 7.2]::float8[]);
select echo_arr_float('[-1:0]={2.1,NULL}'::float8[]);
