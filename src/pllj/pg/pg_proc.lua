local ffi = require('ffi')
ffi.cdef[[
typedef struct FormData_pg_proc{
	NameData	proname;		/* procedure name */
	Oid			pronamespace;	/* OID of namespace containing this proc */
	Oid			proowner;		/* procedure owner */
	Oid			prolang;		/* OID of pg_language entry */
	float4		procost;		/* estimated execution cost */
	float4		prorows;		/* estimated # of rows out (if proretset) */
	Oid			provariadic;	/* element type of variadic array, or 0 */
	regproc		protransform;	/* transforms calls to it during planning */
	bool		proisagg;		/* is it an aggregate? */
	bool		proiswindow;	/* is it a window function? */
	bool		prosecdef;		/* security definer */
	bool		proleakproof;	/* is it a leak-proof function? */
	bool		proisstrict;	/* strict with respect to NULLs? */
	bool		proretset;		/* returns a set? */
	char		provolatile;	/* see PROVOLATILE_ categories below */
	int16		pronargs;		/* number of arguments */
	int16		pronargdefaults;	/* number of arguments with defaults */
	Oid			prorettype;		/* OID of result type */

	/*
	 * variable-length fields start here, but we allow direct access to
	 * proargtypes
	 */
	oidvector	proargtypes;	/* parameter types (excludes OUT params) */

} FormData_pg_proc;
typedef FormData_pg_proc *Form_pg_proc;
struct pg_proc_def {
	    static const int Anum_pg_proc_prosrc = 25;
	};
]]
local defines = ffi.new("struct pg_proc_def")
return {defines = defines}