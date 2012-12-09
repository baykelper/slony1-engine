/*-------------------------------------------------------------------------
 *
 * 
 *
 * Copyright (c) 2012, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *		  
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"

#include "catalog/pg_class.h"
#include "catalog/pg_type.h"
#include "catalog/index.h"

#include "replication/output_plugin.h"
#include "replication/snapbuild.h"

#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/rel.h"
#include "utils/relcache.h"
#include "utils/syscache.h"
#include "utils/typcache.h"
#include "utils/array.h"


PG_MODULE_MAGIC;

void _PG_init(void);


extern void pg_decode_init(void **private);

extern bool pg_decode_begin_txn(void *private, StringInfo out, ReorderBufferTXN* txn);
extern bool pg_decode_commit_txn(void *private, StringInfo out, ReorderBufferTXN* txn, XLogRecPtr commit_lsn);
extern bool pg_decode_change(void *private, StringInfo out, ReorderBufferTXN* txn, Oid tableoid, ReorderBufferChange *change);

char * columnAsText(TupleDesc tupdesc, HeapTuple tuple,int idx);

void
_PG_init(void)
{
}

void
pg_decode_init(void **private)
{
	AssertVariableIsOfType(&pg_decode_init, LogicalDecodeInitCB);
	*private = AllocSetContextCreate(TopMemoryContext,
									 "text conversion context",
									 ALLOCSET_DEFAULT_MINSIZE,
									 ALLOCSET_DEFAULT_INITSIZE,
									 ALLOCSET_DEFAULT_MAXSIZE);
	elog(NOTICE,"inside of pg_decode_init");
}


bool
pg_decode_begin_txn(void *private, StringInfo out, ReorderBufferTXN* txn)
{
	AssertVariableIsOfType(&pg_decode_begin_txn, LogicalDecodeBeginCB);
	/**
	 * we can ignore the begin and commit. slony operates
	 * on SYNC boundaries.
	 */
	elog(NOTICE,"inside of begin");
appendStringInfo(out, "BEGIN %d", txn->xid);
	return true;
}

bool
pg_decode_commit_txn(void *private, StringInfo out, ReorderBufferTXN* txn, XLogRecPtr commit_lsn)
{
	AssertVariableIsOfType(&pg_decode_commit_txn, LogicalDecodeCommitCB);
	/**
	 * we can ignore the begin and commit. slony operates
	 * on SYNC boundaries.
	 */
	elog(NOTICE,"inside of commit");
	appendStringInfo(out, "COMMIT %d", txn->xid);
	return true;
}



bool
pg_decode_change(void *private, StringInfo out, ReorderBufferTXN* txn,
				 Oid tableoid, ReorderBufferChange *change)
{

	
	Relation relation = RelationIdGetRelation(tableoid);	
	TupleDesc	tupdesc = RelationGetDescr(relation);
	MemoryContext context = (MemoryContext)private;
	MemoryContext old = MemoryContextSwitchTo(context);
	int i;
	HeapTuple tuple;
	const char	   **cmdargs = NULL;
	const char	   **cmdargselem = NULL;
	bool	   *cmdnulls = NULL;
	bool	   *cmdnullselem = NULL;
	int		   cmddims[1];
	int        cmdlbs[1];
	ArrayType  *outvalues;
	const char * array_text;
	bool       first=true;

	elog(NOTICE,"inside og pg_decode_change");



	
	if(change->action == REORDER_BUFFER_CHANGE_INSERT)
	{		
		/**
		 * convert all columns to a pair of arrays (columns and values)
		 */
		tuple=&change->newtuple->tuple;
		
		cmdargs = cmdargselem = palloc( (relation->rd_att->natts * 2 +2) * sizeof(char*)  );
		cmdnulls = cmdnullselem = palloc( (relation->rd_att->natts *2 + 2) * sizeof(char*));
		
		

		for(i = 0; i < relation->rd_att->natts; i++)
		{
			const char * column;			
			const char * value;

			if(tupdesc->attrs[i]->attisdropped)
				continue;
			if(tupdesc->attrs[i]->attnum < 0)
				continue;
			column= NameStr(tupdesc->attrs[i]->attname);
			*cmdargselem++=column;
			cmdnullselem++;
			
			value = columnAsText(tupdesc,tuple,i);
			if (value == NULL) 
			{
				*cmdnullselem++=true;
				cmdargselem++;
			}
			else
			{
				*cmdnullselem++=false;
				*cmdargselem++=value;
			}			
			
		}   
		
		
	}
	else if (change->action == REORDER_BUFFER_CHANGE_UPDATE)
	{
		/**
		 * convert all columns into two pairs of arrays.
		 * one for key columns, one for non-key columns
		 */
		
	}
	else if (change->action == REORDER_BUFFER_CHANGE_DELETE)
	{
		/**
		 * convert the key columns to a pair of arrays.
		 */
	}
	else
	{
		/**
		 * what else?
		 */
	}   


	RelationClose(relation);
	while(cmdargs != cmdargselem)
	{
		appendStringInfo(out,first ? "%s," : ",%s,",*cmdargs++);
		first=false;
		if(*(++cmdnulls)==true)
		{
			appendStringInfo(out,"null");
		}
		else
		{
			appendStringInfo(out,"%s",*cmdargs);
		}
		cmdargs++;
		cmdnulls++;
	}
	MemoryContextSwitchTo(old);
	MemoryContextReset(context);

	elog(NOTICE,"leaving og pg_decode_change:");
	return true;
}


/**
 * converts the value stored in the attribute/column specified
 * to a text string.  If the value is NULL then a NULL is returned.
 */
char * columnAsText(TupleDesc tupdesc, HeapTuple tuple,int idx)
{
	Oid typid,typeoutput;
	bool		typisvarlena;
	Form_pg_type ftype;
	bool isnull;
	HeapTuple typeTuple;
	Datum origval,val;
	char * outputstr=NULL;

	typid = tupdesc->attrs[idx]->atttypid;

	typeTuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(typid));
	
	if(!HeapTupleIsValid(typeTuple)) 
		elog(ERROR, "cache lookup failed for type %u", typid);
	ftype = (Form_pg_type) GETSTRUCT(typeTuple);
	
	getTypeOutputInfo(typid,
					  &typeoutput, &typisvarlena);
	
	ReleaseSysCache(typeTuple);
	
	origval = fastgetattr(tuple, idx + 1, tupdesc, &isnull);
	if(typisvarlena && !isnull) 
		val = PointerGetDatum(PG_DETOAST_DATUM(origval));
	else
		val = origval;
	if (isnull)
		return NULL;
	outputstr = OidOutputFunctionCall(typeoutput, val);
	return outputstr;
}