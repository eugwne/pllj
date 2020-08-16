local ffi = require('ffi')
local C = ffi.C
local macro = require('pllj.pg.macro')

local get_oid_from_name = require('pllj.pg.type_info').get_oid_from_name
local hstore_oid = get_oid_from_name('hstore')

if hstore_oid == 0 then
    return false
end

local table_new = require('table.new')
local nkeys_loaded, nkeys = pcall(require, "table.nkeys")
if not nkeys_loaded then
    nkeys = function (T)
        local count = 0
        for _ in pairs(T) do count = count + 1 end
        return count
    end
end

ffi.cdef[[

typedef struct HEntry
{
    uint32      entry;
} HEntry;

typedef struct HStore
{
    int32       vl_len_;    /* varlena header (do not touch directly!) */
    uint32      size_;      /* flags and number of items in hstore */
/* array of HEntry follows */
} HStore;

typedef struct Pairs
{
    char        *key;
    char        *val;
    size_t      keylen;
    size_t      vallen;
    bool        isnull;     /* value is null? */
    bool        needfree;   /* need to pfree the value? */
} Pairs;

HStore* hstoreUpgrade(Datum orig);
int	hstoreUniquePairs(Pairs *a, int32 l, int32 *buflen);
HStore *hstorePairs(Pairs *pairs, int32 pcount, int32 buflen);
]]

local HStore_ptr_t = ffi.typeof('HStore*')
local HEntry_ptr_t = ffi.typeof('HEntry*')

local Pairs_ts = ffi.sizeof('Pairs')


local band = require("bit").band
local function HS_COUNT(hsp_) 
    return tonumber(band(hsp_.size_ , 0x0FFFFFFF))
end

local function ARRPTR(x)
    return ffi.cast(HEntry_ptr_t, ( ffi.cast(HStore_ptr_t, x) + 1 ) )
end

local function STRPTR(x)
    return ffi.cast('char*', ARRPTR(x) + 2 * HS_COUNT(x) ) 
end

local function HSE_ISFIRST(he_) 
    return band(he_.entry, 0x80000000) ~= 0  --#define HENTRY_ISFIRST 0x80000000
end
    
local function HSE_ISNULL(he_) 
    return band(he_.entry, 0x40000000) ~= 0  --#define HENTRY_ISNULL  0x40000000
end
        
local function HSE_ENDPOS(he_) 
    return band(he_.entry,  0x3FFFFFFF)  --#define HENTRY_POSMASK 0x3FFFFFFF
end

local function HSE_OFF(he_) 
    if HSE_ISFIRST(he_) then
        return 0
    end
    return HSE_ENDPOS(ffi.cast(HEntry_ptr_t, he_)-1)
end

local function HSTORE_KEY(arr_, str_, i_)
    return ((str_) + HSE_OFF((arr_)[2 * i_]))
end

local function HSTORE_VAL(arr_, str_, i_)
    return ((str_) + HSE_OFF((arr_)[2 * i_ + 1]))
end

local function HSE_LEN(he_) 
    if HSE_ISFIRST(he_) then
        return HSE_ENDPOS(he_)
    end
    return HSE_ENDPOS(he_) - HSE_ENDPOS(ffi.cast(HEntry_ptr_t, he_)-1)
end

local function HSTORE_KEYLEN(arr_, i_)
    return HSE_LEN((arr_)[2*(i_)])
end

local function HSTORE_VALLEN(arr_,i_)
    return HSE_LEN((arr_)[2*(i_) + 1])
end

local function HSTORE_VALISNULL(arr_, i_)
    return HSE_ISNULL((arr_)[2*(i_)+1])
end


local function hstoreCheckKeyLen(len)
    assert (len <= 0x3FFFFFFF, "string too long for hstore key") --#define HSTORE_MAX_KEY_LEN 0x3FFFFFFF
    return len;
end

local function hstoreCheckValLen(len)
    assert (len <= 0x3FFFFFFF, "string too long for hstore value") --#define HSTORE_MAX_VALUE_LEN 0x3FFFFFFF
    return len;
end

local buflen = ffi.new('int32_t[?]', 1)

return { 

    oid = hstore_oid,

    to_lua = function(datum)
        local _in = C.hstoreUpgrade(datum)
        local count = HS_COUNT(_in)

        local base = STRPTR(_in);
        local entries = ARRPTR(_in);

        local out = table_new(0, count)
        for i = 0, count-1 do
            local key = ffi.string(HSTORE_KEY(entries, base, i), HSTORE_KEYLEN(entries, i))
            if HSTORE_VALISNULL(entries, i) then
                out[key] = NULL
            else
                out[key] = ffi.string(HSTORE_VAL(entries, base, i), HSTORE_VALLEN(entries, i))
            end
        end

        return out
    end,

    to_datum = function(lv)
        if (lv == NULL) then
            return ffi.cast('Datum', 0), true
        end
        assert(type(lv)=='table')

        local sz = nkeys(lv)
        local _pairs = ffi.cast('Pairs*', C.palloc(sz * Pairs_ts))
        local idx = 0
        for k, v in pairs(lv) do
            assert(type(k) == "string")

            _pairs[idx].key = ffi.cast('char*', k)
            _pairs[idx].keylen = hstoreCheckKeyLen(#k)
            _pairs[idx].needfree = false
            if v ~= nil then
                assert(type(v) == "string")
                _pairs[idx].val = ffi.cast('char*', v)
                _pairs[idx].vallen = hstoreCheckValLen(#v)
                _pairs[idx].needfree = false
                _pairs[idx].isnull = false;
            else
                _pairs[idx].isnull = true;
            end
            idx = idx + 1
        end
        sz = C.hstoreUniquePairs(_pairs, sz, buflen);
        local out = C.hstorePairs(_pairs, sz, buflen[0]);

        if out == nil then
            return ffi.cast('Datum', 0), true
        end
        return C.SPI_datumTransfer(ffi.cast('Datum', out), false, -1) , false
    end,

}
