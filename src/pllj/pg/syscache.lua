local ffi = require('ffi')
ffi.cdef[[
  struct syscache {
    enum //SysCacheIdentifier
    {
      AGGFNOID = 0,
      AMNAME,
      AMOID,
      AMOPOPID,
      AMOPSTRATEGY,
      AMPROCNUM,
      ATTNAME,
      ATTNUM,
      AUTHMEMMEMROLE,
      AUTHMEMROLEMEM,
      AUTHNAME,
      AUTHOID,
      CASTSOURCETARGET,
      CLAAMNAMENSP,
      CLAOID,
      COLLNAMEENCNSP,
      COLLOID,
      CONDEFAULT,
      CONNAMENSP,
      CONSTROID,
      CONVOID,
      DATABASEOID,
      DEFACLROLENSPOBJ,
      ENUMOID,
      ENUMTYPOIDNAME,
      EVENTTRIGGERNAME,
      EVENTTRIGGEROID,
      FOREIGNDATAWRAPPERNAME,
      FOREIGNDATAWRAPPEROID,
      FOREIGNSERVERNAME,
      FOREIGNSERVEROID,
      FOREIGNTABLEREL,
      INDEXRELID,
      LANGNAME,
      LANGOID,
      NAMESPACENAME,
      NAMESPACEOID,
      OPERNAMENSP,
      OPEROID,
      OPFAMILYAMNAMENSP,
      OPFAMILYOID,
      PROCNAMEARGSNSP,
      PROCOID,
      RANGETYPE,
      RELNAMENSP,
      RELOID,
      REPLORIGIDENT,
      REPLORIGNAME,
      RULERELNAME,
      STATRELATTINH,
      TABLESPACEOID,
      TRFOID,
      TRFTYPELANG,
      TSCONFIGMAP,
      TSCONFIGNAMENSP,
      TSCONFIGOID,
      TSDICTNAMENSP,
      TSDICTOID,
      TSPARSERNAMENSP,
      TSPARSEROID,
      TSTEMPLATENAMENSP,
      TSTEMPLATEOID,
      TYPENAMENSP,
      TYPEOID,
      USERMAPPINGOID,
      USERMAPPINGUSERSERVER
    };
  };
HeapTuple SearchSysCache(int cacheId,
			   Datum key1, Datum key2, Datum key3, Datum key4);
void ReleaseSysCache(HeapTuple tuple);

typedef int16 AttrNumber;
Datum SysCacheGetAttr(int cacheId, HeapTuple tup,
				AttrNumber attributeNumber, bool *isNull);
]]

local enum = ffi.new("struct syscache")
  
return {enum = enum}