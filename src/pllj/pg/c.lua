local ffi = require('ffi')

ffi.cdef[[
typedef float float4;
typedef double float8;

typedef char *Pointer;
typedef unsigned int Oid;
typedef uintptr_t Datum;
typedef int32_t int32;
typedef uint32_t uint32;
typedef int16_t int16;
typedef uint16_t uint16;
typedef int8_t int8;
typedef uint8_t uint8;

typedef uint8 bits8;			/* >= 8 bits */
typedef uint16 bits16;			/* >= 16 bits */
typedef uint32 bits32;			/* >= 32 bits */


typedef struct nameData
{
	char		data[64/*NAMEDATALEN*/];
} NameData;
typedef NameData *Name;

typedef Oid regproc;
typedef regproc RegProcedure;

typedef uint32 TransactionId;

typedef uint32 LocalTransactionId;

typedef uint32 SubTransactionId;

typedef TransactionId MultiXactId;

typedef uint32 MultiXactOffset;

typedef uint32 CommandId;

typedef struct
{
	int32		vl_len_;		/* these fields must match ArrayType! */
	int			ndim;			/* always 1 for oidvector */
	int32		dataoffset;		/* always 0 for oidvector */
	Oid			elemtype;
	int			dim1;
	int			lbound1;
	Oid			values[/*FLEXIBLE_ARRAY_MEMBER*/];
} oidvector;
]]
local NULL = ffi.new("void*")

return {NULL = NULL}