local spi = {}

local ffi = require('ffi')

local NULL = ffi.new("void*")

local spi_connected = false;

local pgdef = require('pllj.pgdefines')

local NAMEDATALEN = pgdef.pg_config_manual["NAMEDATALEN"]


ffi.cdef[[
typedef unsigned int Oid;
typedef uintptr_t Datum;
typedef int32_t int32;
typedef int16_t int16;

int	SPI_connect(void);
int	SPI_finish(void);
int	SPI_execute(const char *src, bool read_only, long tcount);
uint32_t SPI_processed;
]]

--[[#define NAMEDATALEN 64]]
ffi.cdef[[

typedef struct nameData
{
	char		data[64/*NAMEDATALEN*/];
} NameData;
typedef NameData *Name;

typedef struct Form_pg_attribute_data{
	Oid			attrelid;		/* OID of relation containing this attribute */
	NameData	attname;		/* name of attribute */

	Oid			atttypid;
	int32		attstattarget;
	int16		attlen;
	int16		attnum;
 
} Form_pg_attribute_data, *Form_pg_attribute;

typedef struct tupleDesc
{
	int			natts;			/* number of attributes in the tuple */
	Form_pg_attribute *attrs;
	/* attrs[N] is a pointer to the description of Attribute Number N+1 */
	/*TupleConstr*/ void *constr;		/* constraints, or NULL if none */
	Oid			tdtypeid;		/* composite type ID for tuple type */
	int32_t		tdtypmod;		/* typmod for tuple type */
	bool		tdhasoid;		/* tuple has oid attribute in its header */
	int			tdrefcount;		/* reference count, or -1 if not counting */
}	s_tupleDesc, *TupleDesc;


/*----------------------------*/

typedef struct BlockIdData
{
	uint16_t		bi_hi;
	uint16_t		bi_lo;
} BlockIdData;

typedef uint16_t OffsetNumber;

typedef struct ItemPointerData
{
	BlockIdData ip_blkid;
	OffsetNumber ip_posid;
} ItemPointerData;

typedef struct HeapTupleHeaderData HeapTupleHeaderData;

typedef HeapTupleHeaderData *HeapTupleHeader;

typedef struct HeapTupleData
{
	uint32_t		t_len;			/* length of *t_data */
	ItemPointerData t_self;	/* SelfItemPointer */
  Oid			t_tableOid;		  /* table the tuple came from */
  HeapTupleHeader t_data;	/* -> tuple header and data */
} HeapTupleData;

typedef HeapTupleData *HeapTuple;




typedef uint32_t SubTransactionId;
typedef struct MemoryContextData *MemoryContext;


typedef struct SPITupleTable
{
	MemoryContext tuptabcxt;	/* memory context of result table */
	uint32_t		alloced;		/* # of alloced vals */
	uint32_t		free;			/* # of free vals */
	TupleDesc	tupdesc;		/* tuple descriptor */
	HeapTuple  *vals;			/* tuples */
	void*	next;			/* link for internal bookkeeping */
	SubTransactionId subid;		/* subxact in which tuptable was created */
} SPITupleTable;

SPITupleTable *SPI_tuptable;

void SPI_freetuptable(SPITupleTable *tuptable);
]]



local function connect()
  if (spi_connected == false) then
    if (ffi.C.SPI_connect() ~= pgdef.spi["SPI_OK_CONNECT"]) then
      throw("SPI_connect error")
    end
    spi_connected = true
  end
  
end

ffi.cdef[[
typedef struct HeapTupleHeaderData HeapTupleHeaderData;
typedef HeapTupleHeaderData *HeapTupleHeader;
typedef int16_t AttrNumber;

Datum SPI_getbinval(HeapTuple row, TupleDesc rowdesc, int colnumber,
                    bool * isnull); /* del ? */
Datum pllj_heap_getattr(HeapTuple tuple, int16_t attnum, TupleDesc tupleDesc, bool *isnull);

]]

function spi.execute(query)
  connect()
  local result = -1
  --try
  result = ffi.C.SPI_execute(query, 0, 0)
  --catch
  if (result < 0) then
    return throw("SPI_execute_plan error:"..tostring(query))
  end
  if ((result == pgdef.spi["SPI_OK_SELECT"]) and (ffi.C.SPI_processed > 0)) then
    --[[TupleDesc]] tupleDesc = ffi.C.SPI_tuptable.tupdesc
    local rows = {}
    for i = 0, ffi.C.SPI_processed-1 do
      --[[HeapTuplelocal]] tuple = ffi.C.SPI_tuptable.vals[i]

      local natts = tupleDesc.natts
      local row = {}
      for k = 0, natts-1 do
        local attname = tupleDesc.attrs[k].attname;
        local columnName =  (ffi.string(attname, NAMEDATALEN))
        local attnum = tupleDesc.attrs[k].attnum;

        local isNull = ffi.new("bool[?]", 1)
        --local val = ffi.C.SPI_getbinval(tuple, tupleDesc, k, isNull)

        local val = ffi.C.pllj_heap_getattr(tuple, attnum, tupleDesc,  isNull)

        row[k+1] = isNull[0] == false and val or NULL

      end
      rows[i+1] = row

    end
    ffi.C.SPI_freetuptable(SPI_tuptable);
    return rows
    
  else
    return {}
  end
  
  
end

function spi.disconnect()
    if spi_connected then
      ffi.C.SPI_finish()
      spi_connected = false
    end
end


return spi