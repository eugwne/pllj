local fmgr = {}
local ffi = require('ffi')
require('pllj.pg.palloc')
--#define FUNC_MAX_ARGS		100
ffi.cdef[[
typedef struct Node *fmNodePtr;

typedef struct FunctionCallInfoData *FunctionCallInfo;
typedef Datum (*PGFunction) (FunctionCallInfo fcinfo);

typedef struct FmgrInfo
{
	PGFunction	fn_addr;		/* pointer to function or handler to be called */
	Oid			fn_oid;			/* OID of function (NOT of handler, if any) */
	short		fn_nargs;		/* number of input args (0..FUNC_MAX_ARGS) */
	bool		fn_strict;		/* function is "strict" (NULL in => NULL out) */
	bool		fn_retset;		/* function returns a set */
	unsigned char fn_stats;		/* collect stats if track_functions > this */
	void	   *fn_extra;		/* extra space for use by handler */
	MemoryContext fn_mcxt;		/* memory context to store fn_extra in */
	fmNodePtr	fn_expr;		/* expression parse tree for call, or NULL */
} FmgrInfo;

typedef struct FunctionCallInfoData
{
	FmgrInfo   *flinfo;			/* ptr to lookup info used for this call */
	fmNodePtr	context;		/* pass info about context of call */
	fmNodePtr	resultinfo;		/* pass or return extra info about result */
	Oid			fncollation;	/* collation for function to use */
	bool		isnull;			/* function must set true if result is NULL */
	short		nargs;			/* # arguments actually passed */
	Datum		arg[100/*FUNC_MAX_ARGS*/];		/* Arguments passed to function */
	bool		argnull[100/*FUNC_MAX_ARGS*/]; /* T if arg[i] is actually NULL */
} FunctionCallInfoData;


Datum DirectFunctionCall1Coll(PGFunction func, Oid collation,
						Datum arg1);
]]

return fmgr
