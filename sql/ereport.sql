CREATE FUNCTION elog_test() RETURNS void
AS $$
info('----')
log({message = "log txt", detail="detail text"})
info('----')
info({detail="detail text"})
info('----')
info()
info('----')
info({message = "number", detail=12345})
info('----')
info({
    message = "message text",
    detail = "detail text",
    hint = "hint text",
    sqlstate = "XX000",
    schema_name = "schema_name text",
    table_name = "table_name text",
    column_name = "column_name text",
    datatype_name = "datatype_name text",
    constraint_name = "constraint_name text"
})
info('----')
notice({message = "notice", detail="detail text"})
info('----')
warning({message="warning", detail="detail text"})
info('----')
error({message = "error text", detail="detail text", hint="hint text", context = "context text"})
$$ LANGUAGE pllj;

SELECT elog_test();

CREATE FUNCTION elog_test2() RETURNS void
AS $$
info('----')
error("error text 2")
$$ LANGUAGE pllj;

SELECT elog_test2();
