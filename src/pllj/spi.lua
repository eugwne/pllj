local spi = {}

require('pllj.pg.palloc')

local ffi = require('ffi')

local C = ffi.C;

local NULL = require('pllj.pg.c').NULL

local pgdef = require('pllj.pgdefines')

--local NAMEDATALEN = pgdef.pg_config_manual["NAMEDATALEN"]


ffi.cdef[[
int	SPI_connect(void);
int	SPI_finish(void);
int	lj_SPI_execute(const char *src, bool read_only, long tcount);
void SPI_push(void);
void SPI_pop(void);
uint32_t SPI_processed;
int call_depth;
]]

--[[#define NAMEDATALEN 64]]
require('pllj.pg.itemptr')
ffi.cdef[[


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
  
  if (C.SPI_connect() ~= pgdef.spi["SPI_OK_CONNECT"]) then
    error("SPI_connect error")
  end

end

ffi.cdef[[
typedef struct HeapTupleFields
{
	TransactionId t_xmin;		/* inserting xact ID */
	TransactionId t_xmax;		/* deleting or locking xact ID */

	union
	{
		CommandId	t_cid;		/* inserting or deleting command ID, or both */
		TransactionId t_xvac;	/* old-style VACUUM FULL xact ID */
	}			t_field3;
} HeapTupleFields;

typedef struct DatumTupleFields
{
	int32		datum_len_;		/* varlena header (do not touch directly!) */

	int32		datum_typmod;	/* -1, or identifier of a record type */

	Oid			datum_typeid;	/* composite type OID, or RECORDOID */

	/*
	 * Note: field ordering is chosen with thought that Oid might someday
	 * widen to 64 bits.
	 */
} DatumTupleFields;

typedef struct HeapTupleHeaderData
{
	union
	{
		HeapTupleFields t_heap;
		DatumTupleFields t_datum;
	}			t_choice;
  
  ItemPointerData t_ctid;		/* current TID of this or newer tuple (or a
								 * speculative insertion token) */

	/* Fields below here must match MinimalTupleData! */

	uint16		t_infomask2;	/* number of attributes + various flags */

	uint16		t_infomask;		/* various flag bits, see below */

	uint8		t_hoff;			/* sizeof header incl. bitmap, padding */

	/* ^ - 23 bytes - ^ */

	bits8		t_bits[/*FLEXIBLE_ARRAY_MEMBER*/];	/* bitmap of NULLs */
  
} HeapTupleHeaderData;

//typedef struct HeapTupleHeaderData HeapTupleHeaderData;
typedef HeapTupleHeaderData *HeapTupleHeader;
typedef int16_t AttrNumber;

Datum SPI_getbinval(HeapTuple row, TupleDesc rowdesc, int colnumber,
                    bool * isnull); /* del ? */
Datum pllj_heap_getattr(HeapTuple tuple, int16_t attnum, TupleDesc tupleDesc, bool *isnull);

]]

local pg_error = require('pllj.pg.pg_error')

local datum_to_value = require('pllj.io').datum_to_value

function spi.execute(query)
  local result = -1
  --try
  result = C.lj_SPI_execute(query, 0, 0)
  --catch
  if (result < 0) then
    if (result == pg_error.THROW_NUMBER) then
      return error("SPI_execute_plan error:"..pg_error.get_exception_text())
    end
    return error("SPI_execute_plan error:"..tostring(query))
  end
  if ((result == pgdef.spi["SPI_OK_SELECT"]) and (C.SPI_processed > 0)) then
    --[[TupleDesc]]local tupleDesc = C.SPI_tuptable.tupdesc
    local rows = {}
    for i = 0, C.SPI_processed-1 do
      --[[HeapTuplelocal]]local tuple = C.SPI_tuptable.vals[i]

      local natts = tupleDesc.natts
      local row = {}
      for k = 0, natts-1 do
        --local attname = tupleDesc.attrs[k].attname;
        --local columnName =  (ffi.string(attname, NAMEDATALEN))
        local attnum = tupleDesc.attrs[k].attnum;
        local atttypid = tupleDesc.attrs[k].atttypid;

        local isNull = ffi.new("bool[?]", 1)
        --local val = C.SPI_getbinval(tuple, tupleDesc, k, isNull)

        local val = C.pllj_heap_getattr(tuple, attnum, tupleDesc,  isNull)
        val = datum_to_value(val, atttypid) 

        row[k+1] = isNull[0] == false and val or NULL

      end
      rows[i+1] = row

    end

    C.SPI_freetuptable(C.SPI_tuptable);
    return rows

  else
    return {}
  end


end

function spi.disconnect()
    C.SPI_finish()
end

spi.connect = connect


return spi