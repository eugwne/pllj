local ffi = require('ffi')

require('pllj.pg.c')

ffi.cdef[[
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
]]

return {}