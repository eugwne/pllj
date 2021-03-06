#define cdecl_type(id)                  void cdecl_type__ ## id(id *unused) {}
#define cdecl_memb(id)                  void cdecl_memb__ ## id(id *unused) {}
#define cdecl_struct(tag)               void cdecl_struct__ ## tag(struct tag *unused) {}
#define cdecl_union(tag)                void cdecl_union__ ## tag(union tag *unused) {}
#define cdecl_enum(tag)                 void cdecl_enum__ ## tag(enum tag *unused) {}
#define cdecl_func(id)                  void cdecl_func__ ## id(__typeof__(id)); void cdecl_expr__ ## id() { cdecl_func__ ## id(id); }
#define cdecl_var                       cdecl_func
#define cdecl_const                     cdecl_func

#include <postgres.h>
#include <c.h>
#include <access/htup_details.h> 
#include <utils/array.h> 


#include <utils/builtins.h> 
#include <catalog/pg_proc.h> 
#include <catalog/pg_type.h> 
#include <executor/spi.h> 
#include <catalog/pg_attribute.h> 
#include <catalog/pg_language.h> 
#include <access/tupdesc.h>
#include <utils/syscache.h>
#include <utils/lsyscache.h>
#include <utils/memutils.h>
#include <utils/rel.h>
#include <utils/reltrigger.h>
#include <miscadmin.h> 
#include <commands/trigger.h>

#include <parser/parse_type.h>
#include <funcapi.h>
#include <utils/typcache.h>
#include <utils/portal.h>
#include <nodes/parsenodes.h>
#include <utils/jsonb.h>
#include <utils/numeric.h>

#if PG_VERSION_NUM >= 130000
#include <tcop/cmdtag.h>
#endif

#define cdecl_nstruct(tag)               void cdecl_struct__ ## tag(tag *unused) {}

cdecl_struct(varlena)
cdecl_type(int32)
cdecl_type(Oid)
cdecl_type(bool)
cdecl_type(Datum)
cdecl_type(Pointer)

cdecl_type(float4)
cdecl_type(float8)
cdecl_type(uint32)
cdecl_type(int16)
cdecl_type(uint16)
cdecl_type(int8)
cdecl_type(uint8)
cdecl_type(bits8)
cdecl_type(bits16)
cdecl_type(bits32)

cdecl_type(OffsetNumber)

cdecl_struct(BlockIdData)
cdecl_type(BlockIdData)

cdecl_func(errstart)
cdecl_func(errfinish)
cdecl_func(errmsg_internal)


#if PG_VERSION_NUM >= 120000
cdecl_struct(NullableDatum)
cdecl_type(NullableDatum)
#endif

cdecl_type(FunctionCallInfo)
//array
cdecl_nstruct(ArrayType)
cdecl_type(ArrayType)
cdecl_func(deconstruct_array)

cdecl_nstruct(NameData)
cdecl_type(NameData)
cdecl_type(Name)


cdecl_type(regproc)
cdecl_type(RegProcedure)
cdecl_type(TransactionId)
cdecl_type(LocalTransactionId)
cdecl_type(SubTransactionId)
cdecl_type(MultiXactId)
cdecl_type(MultiXactOffset)
cdecl_type(CommandId)

cdecl_nstruct(oidvector)
cdecl_type(oidvector)

cdecl_type(MemoryContext)

cdecl_func(pg_detoast_datum)
cdecl_type(fmNodePtr)


cdecl_type(PGFunction)
cdecl_func(DirectFunctionCall1Coll)

cdecl_struct(FmgrInfo)
cdecl_type(FmgrInfo)

cdecl_struct(ErrorData)
cdecl_type(ErrorData)

cdecl_func(FreeErrorData)

cdecl_struct(FormData_pg_proc)
cdecl_type(FormData_pg_proc)
cdecl_type(Form_pg_proc)

cdecl_struct(FormData_pg_type)
cdecl_type(FormData_pg_type)
cdecl_type(Form_pg_type)
cdecl_func(GetUserId)
cdecl_func(textout)

#if PG_VERSION_NUM >= 120000
cdecl_struct(FunctionCallInfoBaseData)
cdecl_type(FunctionCallInfoBaseData)
#define LOCAL_FCINFO_TYPE(name, nargs) \
	typedef union \
	{ \
		FunctionCallInfoBaseData fcinfo; \
		char fcinfo_data[SizeForFunctionCallInfo(nargs)]; \
	} name; 

LOCAL_FCINFO_TYPE(FCInfoMax, FUNC_MAX_ARGS)
cdecl_type(FCInfoMax)

#else
cdecl_struct(FunctionCallInfoData)
cdecl_type(FunctionCallInfoData)
#endif


cdecl_struct(ItemPointerData)
cdecl_type(ItemPointerData)

cdecl_func(SPI_connect)
cdecl_func(SPI_finish)
#ifndef SPI_push
cdecl_func(SPI_push)
#endif
#ifndef SPI_pop
cdecl_func(SPI_pop)
#endif
cdecl_var(SPI_processed)


cdecl_nstruct(FormData_pg_attribute)
cdecl_type(FormData_pg_attribute)
cdecl_type(Form_pg_attribute)
//cdecl_type(Form_pg_attribute)
#if PG_VERSION_NUM >= 120000
    cdecl_struct(TupleDescData)
#else
    cdecl_struct(tupleDesc)
#endif
cdecl_type(TupleDesc)

cdecl_struct(HeapTupleFields)
cdecl_type(HeapTupleFields)

cdecl_struct(DatumTupleFields)
cdecl_type(DatumTupleFields)

cdecl_struct(slist_node)

cdecl_struct(HeapTupleHeaderData)
cdecl_type(HeapTupleHeaderData)
cdecl_type(HeapTupleHeader)

cdecl_struct(HeapTupleData)
cdecl_type(HeapTupleData)
cdecl_type(HeapTuple)

cdecl_struct(SPITupleTable)
cdecl_type(SPITupleTable)
cdecl_var(SPI_tuptable)


cdecl_func(SPI_freetuptable)




cdecl_type(AttrNumber)
cdecl_func(SPI_getbinval)

cdecl_const(Anum_pg_proc_proargnames)
cdecl_const(Anum_pg_proc_prosrc)

cdecl_enum(SysCacheIdentifier)
cdecl_func(SearchSysCache)
cdecl_func(ReleaseSysCache)
cdecl_func(SysCacheGetAttr)

cdecl_func(SPI_palloc)
cdecl_const(VARHDRSZ) 

#ifdef WORDS_BIGENDIAN
#define D_WORDS_BIGENDIAN (1)
#else
#define D_WORDS_BIGENDIAN (0)
#endif

cdecl_const(D_WORDS_BIGENDIAN)

cdecl_type(varattrib_4b)

cdecl_const(TYPTYPE_BASE)
cdecl_const(TYPTYPE_COMPOSITE)
cdecl_const(TYPTYPE_DOMAIN)
cdecl_const(TYPTYPE_ENUM)
cdecl_const(TYPTYPE_PSEUDO)
cdecl_const(TYPTYPE_RANGE)

cdecl_func(fmgr_info_cxt)
cdecl_var(CurrentMemoryContext)
cdecl_var(TopMemoryContext)
cdecl_var(CurTransactionContext)
cdecl_func(OutputFunctionCall)
//inlined cdecl_func(MemoryContextSwitchTo)

cdecl_const(TRIGGEROID)

cdecl_enum(NodeTag)

cdecl_struct(FormData_pg_class)
cdecl_struct(LockRelId)
cdecl_struct(LockInfoData)
cdecl_struct(RelFileNode)
cdecl_struct(RelationData)

cdecl_struct(Trigger)
cdecl_struct(TriggerData)
cdecl_type(TriggerData)


cdecl_const(TRIGGER_EVENT_INSERT)
cdecl_const(TRIGGER_EVENT_DELETE)
cdecl_const(TRIGGER_EVENT_UPDATE)
cdecl_const(TRIGGER_EVENT_TRUNCATE)
cdecl_const(TRIGGER_EVENT_OPMASK)

cdecl_const(TRIGGER_EVENT_ROW)

cdecl_const(TRIGGER_EVENT_BEFORE)
cdecl_const(TRIGGER_EVENT_AFTER)
cdecl_const(TRIGGER_EVENT_INSTEAD)
cdecl_const(TRIGGER_EVENT_TIMINGMASK)

cdecl_const(NAMEDATALEN)

cdecl_func(get_namespace_name)

cdecl_func(heap_form_tuple)

#ifndef SIZEOF_DATUM
    #define SIZEOF_DATUM ((int32) sizeof(Datum))
#endif

cdecl_const(SIZEOF_DATUM)

#ifndef SIZEOF_BOOL
    #define SIZEOF_BOOL ((int32) sizeof(bool))
#endif

cdecl_const(SIZEOF_BOOL)

cdecl_func(palloc)
cdecl_func(MemoryContextAlloc)
cdecl_func(pfree)

cdecl_func(heap_copy_tuple_as_datum)
cdecl_func(heap_freetuple)

cdecl_const(HEAPTUPLESIZE)
//cdecl_func(DatumGetHeapTupleHeader)
cdecl_func(SPI_returntuple)
cdecl_func(SPI_copytuple)

cdecl_const(FLOAT4OID)
cdecl_const(FLOAT8OID)
cdecl_const(INT2OID)
cdecl_const(INT4OID)
cdecl_const(INT8OID)
cdecl_const(TEXTOID)
cdecl_const(VOIDOID)
cdecl_const(RECORDOID)

cdecl_const(FLOAT4ARRAYOID)
#ifndef FLOAT8ARRAYOID
    #define FLOAT8ARRAYOID 1022
#endif
cdecl_const(FLOAT8ARRAYOID)
cdecl_const(INT2ARRAYOID)
cdecl_const(INT4ARRAYOID)
cdecl_const(TEXTARRAYOID)
cdecl_const(BOOLOID)
cdecl_const(JSONBOID)


//cdecl_func(stringToQualifiedNameList)
cdecl_func(parseTypeString)
cdecl_func(InputFunctionCall)
//cdecl_func(regprocedurein)
cdecl_func(to_regprocedure)
cdecl_func(to_regtype)

cdecl_const(InvalidOid)
cdecl_const(INTERNALlanguageId)
cdecl_func(get_func_arg_info)

cdecl_const(HEAP_XMIN_FROZEN)
cdecl_type(SPIPlanPtr)
cdecl_func(SPI_prepare_cursor)
cdecl_func(SPI_keepplan)
cdecl_func(SPI_freeplan)

cdecl_const(LOG)
cdecl_const(INFO)
cdecl_const(NOTICE)
cdecl_const(WARNING)
cdecl_const(ERROR)
cdecl_const(FATAL)
cdecl_const(PANIC)

cdecl_const(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION)
cdecl_func(errcode)
cdecl_func(errdetail_internal)
cdecl_func(errhint)
cdecl_func(internalerrquery)
cdecl_func(internalerrposition)
cdecl_func(err_generic_string)



#define SHIFT_ARR_DIMS ARR_DIMS(0)
cdecl_const(SHIFT_ARR_DIMS)

cdecl_func(get_typlenbyvalalign)
cdecl_func(construct_md_array)
cdecl_func(construct_array)
cdecl_func(SPI_datumTransfer)
cdecl_func(MemoryContextStats)

cdecl_const(PROVOLATILE_VOLATILE)

cdecl_const(SPI_OK_CONNECT)
cdecl_const(SPI_OK_FINISH)
cdecl_const(SPI_OK_FETCH)
cdecl_const(SPI_OK_UTILITY)
cdecl_const(SPI_OK_SELECT)
cdecl_const(SPI_OK_SELINTO)
cdecl_const(SPI_OK_INSERT)
cdecl_const(SPI_OK_DELETE)
cdecl_const(SPI_OK_UPDATE)
cdecl_const(SPI_OK_CURSOR)
cdecl_const(SPI_OK_INSERT_RETURNING)
cdecl_const(SPI_OK_DELETE_RETURNING)
cdecl_const(SPI_OK_UPDATE_RETURNING)
cdecl_const(SPI_OK_REWRITTEN)

#if PG_VERSION_NUM >= 100000
cdecl_const(SPI_OK_REL_REGISTER)
cdecl_const(SPI_OK_REL_UNREGISTER)
cdecl_const(SPI_OK_TD_REGISTER)
#endif
cdecl_func(get_language_name)

cdecl_func(lookup_rowtype_tupdesc_noerror)
cdecl_func(CreateTupleDescCopyConstr)
cdecl_func(BlessTupleDesc)
cdecl_func(DecrTupleDescRefCount)
cdecl_func(GetAttributeByNum)
cdecl_func(HeapTupleHeaderGetDatum)

cdecl_struct(ExprContext_CB)
cdecl_type(ExprContext_CB)
cdecl_struct(ExprContext)
cdecl_type(ExprContext)
cdecl_struct(FuncCallContext)
cdecl_type(FuncCallContext)
cdecl_struct(ReturnSetInfo)
cdecl_type(ReturnSetInfo)
cdecl_func(RegisterExprContextCallback)
cdecl_func(UnregisterExprContextCallback)
cdecl_enum(TypeFuncClass)
cdecl_func(get_call_result_type)

cdecl_enum(CommandTag)
cdecl_struct(QueryCompletion)

cdecl_type(Portal)
cdecl_enum(PortalStrategy)
cdecl_enum(PortalStatus)
cdecl_struct(PortalData)


cdecl_func(GetPortalByName)
//cdecl_func(SPI_cursor_open)
cdecl_func(SPI_cursor_close)


cdecl_struct(MemoryContextCallback)
cdecl_type(MemoryContextCallback)
cdecl_func(MemoryContextRegisterResetCallback)
cdecl_enum(FetchDirection)

cdecl_func(MemoryContextStrdup)

cdecl_func(numeric_out)
cdecl_func(numeric_in)
cdecl_type(Numeric)

cdecl_type(JsonbIteratorToken)
cdecl_type(JsonbIterState)

cdecl_struct(JsonbContainer)
cdecl_type(JsonbContainer)

cdecl_struct(JsonbIterator)
cdecl_type(JsonbIterator)

cdecl_nstruct(Jsonb)
cdecl_type(Jsonb)

cdecl_func(JsonbIteratorInit)

cdecl_type(JsonbValue)
cdecl_func(JsonbIteratorNext)

cdecl_enum(jbvType)
cdecl_struct(JsonbValue)
cdecl_func(JsonbValueToJsonb)

cdecl_struct(JsonbParseState)
cdecl_type(JsonbParseState)

cdecl_func(pushJsonbValue)



cdecl_const(PG_VERSION_NUM)
