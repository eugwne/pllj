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
cdecl_func(errmsg)

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

//cdecl_type(FunctionCallInfo)


cdecl_struct(FunctionCallInfoData)
cdecl_type(FunctionCallInfoData)

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
cdecl_struct(tupleDesc)
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
cdecl_func(pfree)

cdecl_func(heap_copy_tuple_as_datum)
cdecl_func(heap_freetuple)

cdecl_const(HEAPTUPLESIZE)
//cdecl_func(DatumGetHeapTupleHeader)
cdecl_func(SPI_returntuple)
cdecl_func(SPI_copytuple)

cdecl_const(INT2OID)
cdecl_const(INT4OID)
cdecl_const(INT8OID)
cdecl_const(TEXTOID)
cdecl_const(VOIDOID)

cdecl_const(INT2ARRAYOID)
cdecl_const(INT4ARRAYOID)
cdecl_const(TEXTARRAYOID)

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

#define SHIFT_ARR_DIMS ARR_DIMS(0)
cdecl_const(SHIFT_ARR_DIMS)

cdecl_func(get_typlenbyvalalign)
cdecl_func(construct_md_array)
cdecl_func(construct_array)
cdecl_func(SPI_datumTransfer)
cdecl_func(MemoryContextStats)
