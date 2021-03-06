
CREATE EXTENSION hstore;

CREATE or replace FUNCTION echo_hst(arg hstore) RETURNS hstore AS $$ 
if arg ~= nil then
    for k,v in pairs(arg) do
    print(tostring(k).. ' : '..tostring(v))
    end
    arg.test = "value"
    arg.nulltest = NULL
end

return arg
$$ LANGUAGE pllj;

select echo_hst(hstore('avalue', 'bteststr'));
