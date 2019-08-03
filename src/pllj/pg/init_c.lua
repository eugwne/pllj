local ffi = require('ffi')
local C = ffi.C

local table_new = require('table.new')

ffi.cdef[[
const char *
GetConfigOption(const char *name, bool missing_ok, bool restrict_privileged);
struct PortalData;
]]
local api_version = ffi.string(C.GetConfigOption('server_version_num', true, false))


local all_types = (require('pllj.pg.api_'..api_version) or require('pllj.pg.i')).all_types
ffi.cdef(all_types)

ffi.cdef[[
typedef  struct null_s{} null_s;

typedef struct LJFunctionData {
    void* fcinfo;
    Datum* result;
} LJFunctionData;

typedef struct{
    ExprContext econtext;
    ReturnSetInfo rsinfo;
} pgfunc_srf;

typedef struct {char* data;}* s_char_data_ptr;
]]

_G.imported = {}

do
    local exp = ffi.cast('void**',__exp__)[0]
    __exp__ = nil
    local ar = ffi.cast([[struct {
        const char *name;
        void *ptr;
        const char *tname;
      }* ]], exp)

    local function def(t, data)
        t[ffi.string(data.name)] = ffi.cast(ffi.string(data.tname), data.ptr)
    end
    local index = 0
    while ar[index].name ~= nil do
        def(imported, ar[index])
        index = index + 1
    end
end

local function __top_alloc(size)
    return C.MemoryContextAlloc(C.TopMemoryContext, size)
end


local null_t, NULL, nullptr
local null_mt = {
  __tostring = function() return 'NULL' end,
   __eq = function( left, right ) 
            local t = type(left)
            if not (t == 'nil' or t == 'cdata') then 
                return false 
            end

            if ffi.cast('void*', left) == nullptr then
                left = right
            end
            t = type(left)
            if not (t == 'nil' or t == 'cdata') then 
                return false 
            end
            local ptr = ffi.cast('void*', left)

            return ((ptr == nil) or (ptr == nullptr))
        end
}
null_t = ffi.metatype("null_s", null_mt)
NULL = null_t()
nullptr = ffi.cast('void*', NULL)

--NULL = ffi.new("void*")
ffi.NULL = NULL

local function __report(elevel, data)
    local elevel = math.min(elevel, C.WARNING)
    local message 
    local sqlerrcode
    local detail
    local hint
    local query
    local position
    local schema_name
    local table_name
    local column_name
    local datatype_name
    local constraint_name
    
    local t = type(data)
    if t == "table" then
        message = data.message and tostring(data.message) or ""
        sqlerrcode = tonumber(data.sqlerrcode)
        detail = data.detail
        hint = data.hint
        query = data.query
        position = tonumber(data.position)
        schema_name = data.schema_name
        table_name = data.table_name
        column_name = data.column_name
        datatype_name = data.datatype_name
        constraint_name = data.constraint_name
    elseif type(data) == "string" then
        message = data
    else
        message = data and tostring(data) or ""
    end 

    C.errstart(elevel, "", 0, nil, nil)
    C.errfinish(C.errcode(sqlerrcode and sqlerrcode or C.ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
        C.errmsg_internal(message),
        detail and C.errdetail_internal(tostring(detail)) or 0,
        --TODO context
        hint and  C.errhint(tostring(hint)) or 0,
        query and C.internalerrquery(tostring(query)) or 0,
        position and C.internalerrposition(position) or 0,
        schema_name and C.err_generic_string(string.byte('s'), tostring(schema_name)) or 0,--PG_DIAG_SCHEMA_NAME,
        table_name and C.err_generic_string(string.byte('t'), tostring(table_name)) or 0,--PG_DIAG_TABLE_NAME,
        column_name and C.err_generic_string(string.byte('c'), tostring(column_name)) or 0,--PG_DIAG_COLUMN_NAME,
        datatype_name and C.err_generic_string(string.byte('d'), tostring(datatype_name)) or 0,--PG_DIAG_DATATYPE_NAME,
        constraint_name and C.err_generic_string(string.byte('n'), tostring(constraint_name)) or 0--PG_DIAG_CONSTRAINT_NAME,
    )
end 

local function __log(data)
    __report(C.LOG, data)
end

local function __info(data)
    __report(C.INFO, data)
end

local function __notice(data)
    __report(C.NOTICE, data)
end

local function __warning(data)
    __report(C.WARNING, data)
end

local __pg_print
__pg_print = function(...)
    local args = {...}
    local argc = #args

    if argc < 2 then
        local text = args[1]
        C.errstart(C.INFO, "", 0, nil, nil)
        C.errfinish(C.errmsg_internal(tostring(text)))
        return __pg_print
    end
    local tmp = table_new(argc * 2, 0)
    table.insert(tmp, tostring(args[1]))
    for k = 2, argc  do
        table.insert(tmp, ' ')
        table.insert(tmp, tostring(args[k]))
    end
    local output = table.concat(tmp)
    C.errstart(C.INFO, "", 0, nil, nil)
    C.errfinish(C.errmsg_internal(tostring(output)))
    return __pg_print
end

top_alloc = __top_alloc
print = __pg_print
info = __info
log = __log
notice = __notice
warning = __warning
