/* ----------------------------------------------------------------------
 * slony1_funcs.c
 *
 *	  The C functions and triggers portion of Slony-I.
 *
 *	Copyright (c) 2003-2006, PostgreSQL Global Development Group
 *	Author: Jan Wieck, Afilias USA INC.
 *
 *	
 * ----------------------------------------------------------------------
 */

#include "postgres.h"
#include "config.h"

#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "parser/keywords.h"
#include "parser/parse_type.h"
#include "executor/spi.h"
#include "commands/trigger.h"
#include "commands/async.h"
#include "catalog/pg_operator.h"
#include "access/xact.h"
#include "utils/builtins.h"
#include "utils/elog.h"
#ifdef HAVE_TYPCACHE
#include "utils/typcache.h"
#else
#include "parser/parse_oper.h"
#endif
#include "mb/pg_wchar.h"

#include <signal.h>
#include <errno.h>


PG_FUNCTION_INFO_V1(_Slony_I_createEvent);
PG_FUNCTION_INFO_V1(_Slony_I_getLocalNodeId);
PG_FUNCTION_INFO_V1(_Slony_I_getModuleVersion);

PG_FUNCTION_INFO_V1(_Slony_I_setSessionRole);
PG_FUNCTION_INFO_V1(_Slony_I_getSessionRole);
PG_FUNCTION_INFO_V1(_Slony_I_logTrigger);
PG_FUNCTION_INFO_V1(_Slony_I_denyAccess);
PG_FUNCTION_INFO_V1(_Slony_I_lockedSet);
PG_FUNCTION_INFO_V1(_Slony_I_killBackend);

PG_FUNCTION_INFO_V1(_slon_quote_ident);


Datum		_Slony_I_createEvent(PG_FUNCTION_ARGS);
Datum		_Slony_I_getLocalNodeId(PG_FUNCTION_ARGS);
Datum		_Slony_I_getModuleVersion(PG_FUNCTION_ARGS);

Datum		_Slony_I_setSessionRole(PG_FUNCTION_ARGS);
Datum		_Slony_I_getSessionRole(PG_FUNCTION_ARGS);
Datum		_Slony_I_logTrigger(PG_FUNCTION_ARGS);
Datum		_Slony_I_denyAccess(PG_FUNCTION_ARGS);
Datum		_Slony_I_lockedSet(PG_FUNCTION_ARGS);
Datum		_Slony_I_killBackend(PG_FUNCTION_ARGS);

Datum		_slon_quote_ident(PG_FUNCTION_ARGS);


#ifdef CYGWIN
extern DLLIMPORT Node *newNodeMacroHolder;
#endif

#define PLAN_NONE			0
#define PLAN_NOTIFY_EVENT	(1 << 0)
#define PLAN_INSERT_EVENT	(1 << 1)
#define PLAN_INSERT_LOG		(1 << 2)

#define SLON_ROLE_UNSET		0
#define SLON_ROLE_NORMAL	1
#define SLON_ROLE_SLON		2



/* ----
 * Slony_I_ClusterStatus -
 *
 *	The per-cluster data to hold for functions and triggers.
 * ----
 */
typedef struct slony_I_cluster_status
{
	NameData	clustername;
	char	   *clusterident;
	int32		localNodeId;
	TransactionId currentXid;
	int			session_role;
	void	   *plan_active_log;

	int			have_plan;
	void	   *plan_notify_event;
	void	   *plan_insert_event;
	void	   *plan_insert_log_1;
	void	   *plan_insert_log_2;
	void	   *plan_record_sequences;

	text	   *cmdtype_I;
	text	   *cmdtype_U;
	text	   *cmdtype_D;

	text	   *cmddata_buf;
	int			cmddata_size;

	struct slony_I_cluster_status *next;
}	Slony_I_ClusterStatus;


static Slony_I_ClusterStatus *clusterStatusList = NULL;
static Slony_I_ClusterStatus *
getClusterStatus(Name cluster_name,
				 int need_plan_mask);
const char * slon_quote_identifier(const char *ident);
static char *slon_quote_literal(char *str);


Datum
_Slony_I_createEvent(PG_FUNCTION_ARGS)
{
	TransactionId newXid = GetTopTransactionId();
	Slony_I_ClusterStatus *cs;
	text	   *ev_xip;
	char	   *ev_type_c;
	Datum		argv  [12];
	char		nulls  [13];
	char	   *buf;
	size_t		buf_size;
	int			rc;
	int			xcnt;
	char	   *cp;
	int			i;
	int64		retval;
	bool		isnull;

	if (SerializableSnapshot == NULL)
		elog(ERROR, "Slony-I: SerializableSnapshot is NULL in createEvent()");

	if ((rc = SPI_connect()) < 0)
		elog(ERROR, "Slony-I: SPI_connect() failed in createEvent()");

	/*
	 * Get or create the cluster status information and make sure it has the
	 * SPI plans that we need here.
	 */
	cs = getClusterStatus(PG_GETARG_NAME(0),
						  PLAN_NOTIFY_EVENT | PLAN_INSERT_EVENT);

	buf_size = 8192;
	buf = palloc(buf_size);

	/*
	 * Do the following only once per transaction.
	 */
	if (!TransactionIdEquals(cs->currentXid, newXid))
	{
		/*
		 * Once per transaction notify on the sl_event relation
		 */
		if ((rc = SPI_execp(cs->plan_notify_event, NULL, NULL, 0)) < 0)
			elog(ERROR, "Slony-I: SPI_execp() failed for \"NOTIFY event\"");

		cs->currentXid = newXid;
	}

	/*
	 * Build the comma separated list of transactions in progress as Text
	 * datum.
	 */
	*(cp = buf) = '\0';
	for (xcnt = 0; xcnt < SerializableSnapshot->xcnt; xcnt++)
	{
		if ((cp + 30) >= (buf + buf_size))
		{
			buf_size *= 2;
			buf = repalloc(buf, buf_size);
			cp = buf + strlen(buf);
		}
		sprintf(cp, "%s'%u'", (xcnt > 0) ? "," : "",
				SerializableSnapshot->xip[xcnt]);
		cp += strlen(cp);
	}
	ev_xip = DatumGetTextP(DirectFunctionCall1(textin, PointerGetDatum(buf)));

	/*
	 * Call the saved INSERT plan
	 */
	argv[0] = TransactionIdGetDatum(SerializableSnapshot->xmin);
	argv[1] = TransactionIdGetDatum(SerializableSnapshot->xmax);
	argv[2] = PointerGetDatum(ev_xip);
	nulls[0] = ' ';
	nulls[1] = ' ';
	nulls[2] = ' ';
	for (i = 1; i < 10; i++)
	{
		if (i >= PG_NARGS() || PG_ARGISNULL(i))
		{
			argv[i + 2] = (Datum)0;
			nulls[i + 2] = 'n';
		}
		else
		{
			argv[i + 2] = PG_GETARG_DATUM(i);
			nulls[i + 2] = ' ';
		}
	}
	nulls[12] = '\0';

	if ((rc = SPI_execp(cs->plan_insert_event, argv, nulls, 0)) < 0)
		elog(ERROR, "Slony-I: SPI_execp() failed for \"INSERT INTO sl_event ...\"");

	/*
	 * The INSERT plan also contains a SELECT currval('sl_event_seq'), use the
	 * new sequence number as return value.
	 */
	if (SPI_processed != 1)
		elog(ERROR, "Slony-I: INSERT plan did not return 1 result row");
	retval = DatumGetInt64(SPI_getbinval(SPI_tuptable->vals[0],
										 SPI_tuptable->tupdesc, 1, &isnull));

	/*
	 * For SYNC and ENABLE_SUBSCRIPTION events, we also remember all current
	 * sequence values.
	 */
	if (PG_NARGS() > 1 && !PG_ARGISNULL(1))
	{
		ev_type_c = DatumGetPointer(DirectFunctionCall1(
											   textout, PG_GETARG_DATUM(1)));
		if (strcmp(ev_type_c, "SYNC") == 0 ||
			strcmp(ev_type_c, "ENABLE_SUBSCRIPTION") == 0)
		{
			if ((rc = SPI_execp(cs->plan_record_sequences, NULL, NULL, 0)) < 0)
				elog(ERROR, "Slony-I: SPI_execp() failed for \"INSERT INTO sl_seqlog ...\"");
		}
	}

	SPI_finish();

	PG_RETURN_INT64(retval);
}


/*
 * _Slony_I_getLocalNodeId -
 *
 *	  SQL callable wrapper for calling getLocalNodeId() in order
 *	  to get the current setting of sequence sl_local_node_id with
 *	  configuration check.
 *
 */
Datum
_Slony_I_getLocalNodeId(PG_FUNCTION_ARGS)
{
	Slony_I_ClusterStatus *cs;
	int			rc;

	if ((rc = SPI_connect()) < 0)
		elog(ERROR, "Slony-I: SPI_connect() failed in getLocalNodeId()");

	cs = getClusterStatus(PG_GETARG_NAME(0), PLAN_NONE);

	SPI_finish();

	PG_RETURN_INT32(cs->localNodeId);
}


/*
 * _Slony_I_getModuleVersion -
 *
 *	  SQL callable function to determine the version number
 *	  of this shared object during the startup checks.
 *
 */
Datum
_Slony_I_getModuleVersion(PG_FUNCTION_ARGS)
{
	text	   *retval;
	int			len;

	len = strlen(SLONY_I_VERSION_STRING);
	retval = palloc(VARHDRSZ + len);
	VARATT_SIZEP(retval) = VARHDRSZ + len;
	memcpy(VARDATA(retval), SLONY_I_VERSION_STRING, len);

	PG_RETURN_TEXT_P(retval);
}


Datum
_Slony_I_setSessionRole(PG_FUNCTION_ARGS)
{
	Slony_I_ClusterStatus *cs;
	int			rc;
	text	   *new_role_t = PG_GETARG_TEXT_P(1);
	int			new_role = SLON_ROLE_UNSET;

	if ((rc = SPI_connect()) < 0)
		elog(ERROR, "Slony-I: SPI_connect() failed in setSessionRole()");

	cs = getClusterStatus(PG_GETARG_NAME(0), PLAN_NONE);

	SPI_finish();

	if (VARSIZE(new_role_t) == VARHDRSZ + 6 &&
		memcmp(VARDATA(new_role_t), "normal", 6) == 0)
	{
		new_role = SLON_ROLE_NORMAL;
	}
	else if (VARSIZE(new_role_t) == VARHDRSZ + 4 &&
			 memcmp(VARDATA(new_role_t), "slon", 4) == 0)
	{
		if (!superuser())
			elog(ERROR, "Slony-I: insufficient privilege for replication role");

		new_role = SLON_ROLE_SLON;
	}
	else
	{
		elog(ERROR, "Slony-I: invalid session role");
	}

	if (cs->session_role == SLON_ROLE_UNSET ||
		cs->session_role == new_role)
	{
		cs->session_role = new_role;
	}
	else
	{
		elog(ERROR, "Slony-I: cannot change session role once set");
	}

	PG_RETURN_TEXT_P(new_role_t);
}


Datum
_Slony_I_getSessionRole(PG_FUNCTION_ARGS)
{
	Slony_I_ClusterStatus *cs;
	int			rc;
	text	   *retval = NULL;

	if ((rc = SPI_connect()) < 0)
		elog(ERROR, "Slony-I: SPI_connect() failed in getSessionRole()");

	cs = getClusterStatus(PG_GETARG_NAME(0), PLAN_NONE);

	SPI_finish();

	switch (cs->session_role)
	{
		case SLON_ROLE_UNSET:
			cs->session_role = SLON_ROLE_NORMAL;
			retval = palloc(VARHDRSZ + 6);
			VARATT_SIZEP(retval) = VARHDRSZ + 6;
			memcpy(VARDATA(retval), "normal", 6);
			break;

		case SLON_ROLE_NORMAL:
			retval = palloc(VARHDRSZ + 6);
			VARATT_SIZEP(retval) = VARHDRSZ + 6;
			memcpy(VARDATA(retval), "normal", 6);
			break;

		case SLON_ROLE_SLON:
			retval = palloc(VARHDRSZ + 4);
			VARATT_SIZEP(retval) = VARHDRSZ + 4;
			memcpy(VARDATA(retval), "slon", 4);
			break;
	}

	PG_RETURN_TEXT_P(retval);
}


Datum
_Slony_I_logTrigger(PG_FUNCTION_ARGS)
{
	TransactionId newXid = GetTopTransactionId();
	Slony_I_ClusterStatus *cs;
	TriggerData *tg;
	Datum		argv  [4];
	text	   *cmdtype = NULL;
	int			rc;
	Name		cluster_name;
	int32		tab_id;
	char	   *attkind;
	int			attkind_idx;
	int			cmddata_need;

	/*
	 * Get the trigger call context
	 */
	if (!CALLED_AS_TRIGGER(fcinfo))
		elog(ERROR, "Slony-I: logTrigger() not called as trigger");
	tg = (TriggerData *) (fcinfo->context);

	/*
	 * Check all logTrigger() calling conventions
	 */
	if (!TRIGGER_FIRED_AFTER(tg->tg_event))
		elog(ERROR, "Slony-I: logTrigger() must be fired AFTER");
	if (!TRIGGER_FIRED_FOR_ROW(tg->tg_event))
		elog(ERROR, "Slony-I: logTrigger() must be fired FOR EACH ROW");
	if (tg->tg_trigger->tgnargs != 3)
		elog(ERROR, "Slony-I: logTrigger() must be defined with 3 args");

	/*
	 * Connect to the SPI manager
	 */
	if ((rc = SPI_connect()) < 0)
		elog(ERROR, "Slony-I: SPI_connect() failed in createEvent()");

	/*
	 * Get all the trigger arguments
	 */
	cluster_name = DatumGetName(DirectFunctionCall1(namein,
								CStringGetDatum(tg->tg_trigger->tgargs[0])));
	tab_id = strtol(tg->tg_trigger->tgargs[1], NULL, 10);
	attkind = tg->tg_trigger->tgargs[2];

	/*
	 * Get or create the cluster status information and make sure it has the
	 * SPI plans that we need here.
	 */
	cs = getClusterStatus(cluster_name, PLAN_INSERT_LOG);

	/*
	 * Check/set the session role
	 */
	switch (cs->session_role)
	{
		case SLON_ROLE_UNSET:	/* Nobody told us, force it to normal */
			cs->session_role = SLON_ROLE_NORMAL;
			break;

		case SLON_ROLE_NORMAL:	/* Normal, that's good */
			break;

		case SLON_ROLE_SLON:	/* non-client session ??? */
			elog(ERROR, "Slony-I: logTrigger() called in non-client session");
	}

	/*
	 * Do the following only once per transaction.
	 */
	if (!TransactionIdEquals(cs->currentXid, newXid))
	{
		/*
		 * Determine the currently active log table
		 */
		cs->plan_active_log = cs->plan_insert_log_1;

		cs->currentXid = newXid;
	}

	/*
	 * Determine cmdtype and cmddata depending on the command type
	 */
	if (TRIGGER_FIRED_BY_INSERT(tg->tg_event))
	{
		HeapTuple	new_row = tg->tg_trigtuple;
		TupleDesc	tupdesc = tg->tg_relation->rd_att;
		char	   *col_ident;
		char	  **col_value;
		int			len_ident;
		int			len_value;
		int			i;
		int			need_comma = false;
		char	   *cp = VARDATA(cs->cmddata_buf);

		/*
		 * INSERT
		 *
		 * cmdtype = 'I' cmddata = ("non-NULL-col" [, ...]) values ('value' [,
		 * ...])
		 */
		cmdtype = cs->cmdtype_I;

		/*
		 * Allocate an array of char pointers to hold the values. We need to
		 * go over the tuple descriptor 2 times, first to add the column names
		 * of non-null columns, second to add the values. But we can identify
		 * what's NULL only by getting the value via SPI_getvalue() in the
		 * first pass.
		 */
		col_value = (char **)palloc(sizeof(char *) *
									tg->tg_relation->rd_att->natts);

		/*
		 * Specify all the columns
		 */
		*cp++ = '(';
		for (i = 0; i < tg->tg_relation->rd_att->natts; i++)
		{
			/*
			 * Skip dropped columns and NULL values
			 */
			if (tupdesc->attrs[i]->attisdropped)
				continue;
			if ((col_value[i] = SPI_getvalue(new_row, tupdesc, i + 1)) == NULL)
				continue;

			col_ident = (char *)slon_quote_identifier(SPI_fname(tupdesc, i + 1));
			col_value[i] = slon_quote_literal(col_value[i]);

			cmddata_need = (cp - (char *)(cs->cmddata_buf)) + 16 +
				(len_ident = strlen(col_ident));
			if (cs->cmddata_size < cmddata_need)
			{
				int			have = (cp - (char *)(cs->cmddata_buf));

				while (cs->cmddata_size < cmddata_need)
					cs->cmddata_size *= 2;
				cs->cmddata_buf = realloc(cs->cmddata_buf, cs->cmddata_size);
				cp = (char *)(cs->cmddata_buf) + have;
			}

			if (need_comma)
				*cp++ = ',';
			else
				need_comma = true;

			memcpy(cp, col_ident, len_ident);
			cp += len_ident;
		}

		/*
		 * Append the string ") values ("
		 */
		*cp++ = ')';
		*cp++ = ' ';
		*cp++ = 'v';
		*cp++ = 'a';
		*cp++ = 'l';
		*cp++ = 'u';
		*cp++ = 'e';
		*cp++ = 's';
		*cp++ = ' ';
		*cp++ = '(';

		/*
		 * Append the values
		 */
		need_comma = false;
		for (i = 0; i < tg->tg_relation->rd_att->natts; i++)
		{
			/*
			 * Skip dropped columns and NULL values
			 */
			if (tupdesc->attrs[i]->attisdropped)
				continue;
			if (col_value[i] == NULL)
				continue;

			cmddata_need = (cp - (char *)(cs->cmddata_buf)) + 16 +
				(len_value = strlen(col_value[i]));
			if (cs->cmddata_size < cmddata_need)
			{
				int			have = (cp - (char *)(cs->cmddata_buf));

				while (cs->cmddata_size < cmddata_need)
					cs->cmddata_size *= 2;
				cs->cmddata_buf = realloc(cs->cmddata_buf, cs->cmddata_size);
				cp = (char *)(cs->cmddata_buf) + have;
			}

			if (need_comma)
				*cp++ = ',';
			else
				need_comma = true;

			memcpy(cp, col_value[i], len_value);
			cp += len_value;
		}

		/*
		 * Terminate and done
		 */
		*cp++ = ')';
		*cp = '\0';
		VARATT_SIZEP(cs->cmddata_buf) =
			VARHDRSZ + (cp - VARDATA(cs->cmddata_buf));
	}
	else if (TRIGGER_FIRED_BY_UPDATE(tg->tg_event))
	{
		HeapTuple	old_row = tg->tg_trigtuple;
		HeapTuple	new_row = tg->tg_newtuple;
		TupleDesc	tupdesc = tg->tg_relation->rd_att;
		Datum		old_value;
		Datum		new_value;
		bool		old_isnull;
		bool		new_isnull;

		char	   *col_ident;
		char	   *col_value;
		int			len_ident;
		int			len_value;
		int			i;
		int			need_comma = false;
		int			need_and = false;
		char	   *cp = VARDATA(cs->cmddata_buf);

		/*
		 * UPDATE
		 *
		 * cmdtype = 'U' cmddata = "col_ident"='value' [, ...] where "pk_ident" =
		 * 'value' [ and ...]
		 */
		cmdtype = cs->cmdtype_U;
		for (i = 0; i < tg->tg_relation->rd_att->natts; i++)
		{
			/*
			 * Ignore dropped columns
			 */
			if (tupdesc->attrs[i]->attisdropped)
				continue;

			old_value = SPI_getbinval(old_row, tupdesc, i + 1, &old_isnull);
			new_value = SPI_getbinval(new_row, tupdesc, i + 1, &new_isnull);

			/*
			 * If old and new value are NULL, the column is unchanged
			 */
			if (old_isnull && new_isnull)
				continue;

			/*
			 * If both are NOT NULL, we need to compare the values and skip
			 * setting the column if equal
			 */
			if (!old_isnull && !new_isnull)
			{
				Oid			opr_oid;
				FmgrInfo   *opr_finfo_p;

				/*
				 * Lookup the equal operators function call info using the
				 * typecache if available
				 */
#ifdef HAVE_TYPCACHE
				TypeCacheEntry *type_cache;

				type_cache = lookup_type_cache(
											   SPI_gettypeid(tupdesc, i + 1),
								  TYPECACHE_EQ_OPR | TYPECACHE_EQ_OPR_FINFO);
				opr_oid = type_cache->eq_opr;
				if (opr_oid == ARRAY_EQ_OP)
					opr_oid = InvalidOid;
				else
					opr_finfo_p = &(type_cache->eq_opr_finfo);
#else
				FmgrInfo	opr_finfo;

				opr_oid = compatible_oper_funcid(makeList1(makeString("=")),
											   SPI_gettypeid(tupdesc, i + 1),
										SPI_gettypeid(tupdesc, i + 1), true);
				if (OidIsValid(opr_oid))
				{
					fmgr_info(opr_oid, &opr_finfo);
					opr_finfo_p = &opr_finfo;
				}
#endif

				/*
				 * If we have an equal operator, use that to do binary
				 * comparision. Else get the string representation of both
				 * attributes and do string comparision.
				 */
				if (OidIsValid(opr_oid))
				{
					if (DatumGetBool(FunctionCall2(opr_finfo_p,
												   old_value, new_value)))
						continue;
				}
				else
				{
					char	   *old_strval = SPI_getvalue(old_row, tupdesc, i + 1);
					char	   *new_strval = SPI_getvalue(new_row, tupdesc, i + 1);

					if (strcmp(old_strval, new_strval) == 0)
						continue;
				}
			}

			if (need_comma)
				*cp++ = ',';
			else
				need_comma = true;

			col_ident = (char *)slon_quote_identifier(SPI_fname(tupdesc, i + 1));
			if (new_isnull)
				col_value = "NULL";
			else
				col_value = slon_quote_literal(SPI_getvalue(new_row, tupdesc, i + 1));

			cmddata_need = (cp - (char *)(cs->cmddata_buf)) + 16 +
				(len_ident = strlen(col_ident)) +
				(len_value = strlen(col_value));
			if (cs->cmddata_size < cmddata_need)
			{
				int			have = (cp - (char *)(cs->cmddata_buf));

				while (cs->cmddata_size < cmddata_need)
					cs->cmddata_size *= 2;
				cs->cmddata_buf = realloc(cs->cmddata_buf, cs->cmddata_size);
				cp = (char *)(cs->cmddata_buf) + have;
			}

			memcpy(cp, col_ident, len_ident);
			cp += len_ident;
			*cp++ = '=';
			memcpy(cp, col_value, len_value);
			cp += len_value;
		}

		/*
		 * It can happen that the only UPDATE an application does is to set a
		 * column to the same value again. In that case, we'd end up here with
		 * no columns in the SET clause yet. We add the first key column here
		 * with it's old value to simulate the same for the replication
		 * engine.
		 */
		if (!need_comma)
		{
			for (i = 0, attkind_idx = -1; i < tg->tg_relation->rd_att->natts; i++)
			{
				if (tupdesc->attrs[i]->attisdropped)
					continue;

				attkind_idx++;
				if (attkind[attkind_idx] == 'k')
					break;
			}
			col_ident = (char *)slon_quote_identifier(SPI_fname(tupdesc, i + 1));
			col_value = slon_quote_literal(SPI_getvalue(old_row, tupdesc, i + 1));

			cmddata_need = (cp - (char *)(cs->cmddata_buf)) + 16 +
				(len_ident = strlen(col_ident)) +
				(len_value = strlen(col_value));
			if (cs->cmddata_size < cmddata_need)
			{
				int			have = (cp - (char *)(cs->cmddata_buf));

				while (cs->cmddata_size < cmddata_need)
					cs->cmddata_size *= 2;
				cs->cmddata_buf = realloc(cs->cmddata_buf, cs->cmddata_size);
				cp = (char *)(cs->cmddata_buf) + have;
			}

			memcpy(cp, col_ident, len_ident);
			cp += len_ident;
			*cp++ = '=';
			memcpy(cp, col_value, len_value);
			cp += len_value;
		}

		*cp++ = ' ';
		*cp++ = 'w';
		*cp++ = 'h';
		*cp++ = 'e';
		*cp++ = 'r';
		*cp++ = 'e';
		*cp++ = ' ';

		for (i = 0, attkind_idx = -1; i < tg->tg_relation->rd_att->natts; i++)
		{
			/*
			 * Ignore dropped columns
			 */
			if (tupdesc->attrs[i]->attisdropped)
				continue;

			attkind_idx++;
			if (attkind[attkind_idx] != 'k')
				continue;
			col_ident = (char *)slon_quote_identifier(SPI_fname(tupdesc, i + 1));
			col_value = slon_quote_literal(SPI_getvalue(old_row, tupdesc, i + 1));
			if (col_value == NULL)
				elog(ERROR, "Slony-I: old key column %s.%s IS NULL on UPDATE", 
					NameStr(tg->tg_relation->rd_rel->relname), col_ident);

			cmddata_need = (cp - (char *)(cs->cmddata_buf)) + 16 +
				(len_ident = strlen(col_ident)) +
				(len_value = strlen(col_value));
			if (cs->cmddata_size < cmddata_need)
			{
				int			have = (cp - (char *)(cs->cmddata_buf));

				while (cs->cmddata_size < cmddata_need)
					cs->cmddata_size *= 2;
				cs->cmddata_buf = realloc(cs->cmddata_buf, cs->cmddata_size);
				cp = (char *)(cs->cmddata_buf) + have;
			}

			if (need_and)
			{
				*cp++ = ' ';
				*cp++ = 'a';
				*cp++ = 'n';
				*cp++ = 'd';
				*cp++ = ' ';
			}
			else
				need_and = true;

			memcpy(cp, col_ident, len_ident);
			cp += len_ident;
			*cp++ = '=';
			memcpy(cp, col_value, len_value);
			cp += len_value;
		}
		*cp = '\0';
		VARATT_SIZEP(cs->cmddata_buf) =
			VARHDRSZ + (cp - VARDATA(cs->cmddata_buf));
	}
	else if (TRIGGER_FIRED_BY_DELETE(tg->tg_event))
	{
		HeapTuple	old_row = tg->tg_trigtuple;
		TupleDesc	tupdesc = tg->tg_relation->rd_att;
		char	   *col_ident;
		char	   *col_value;
		int			len_ident;
		int			len_value;
		int			i;
		int			need_and = false;
		char	   *cp = VARDATA(cs->cmddata_buf);

		/*
		 * DELETE
		 *
		 * cmdtype = 'D' cmddata = "pk_ident"='value' [and ...]
		 */
		cmdtype = cs->cmdtype_D;

		for (i = 0, attkind_idx = -1; i < tg->tg_relation->rd_att->natts; i++)
		{
			if (tupdesc->attrs[i]->attisdropped)
				continue;

			attkind_idx++;
			if (attkind[attkind_idx] != 'k')
				continue;
			col_ident = (char *)slon_quote_identifier(SPI_fname(tupdesc, i + 1));
			col_value = slon_quote_literal(SPI_getvalue(old_row, tupdesc, i + 1));
			if (col_value == NULL)
				elog(ERROR, "Slony-I: old key column %s.%s IS NULL on DELETE", 
					NameStr(tg->tg_relation->rd_rel->relname), col_ident);

			cmddata_need = (cp - (char *)(cs->cmddata_buf)) + 16 +
				(len_ident = strlen(col_ident)) +
				(len_value = strlen(col_value));
			if (cs->cmddata_size < cmddata_need)
			{
				int			have = (cp - (char *)(cs->cmddata_buf));

				while (cs->cmddata_size < cmddata_need)
					cs->cmddata_size *= 2;
				cs->cmddata_buf = realloc(cs->cmddata_buf, cs->cmddata_size);
				cp = (char *)(cs->cmddata_buf) + have;
			}

			if (need_and)
			{
				*cp++ = ' ';
				*cp++ = 'a';
				*cp++ = 'n';
				*cp++ = 'd';
				*cp++ = ' ';
			}
			else
				need_and = true;

			memcpy(cp, col_ident, len_ident);
			cp += len_ident;
			*cp++ = '=';
			memcpy(cp, col_value, len_value);
			cp += len_value;
		}
		*cp = '\0';
		VARATT_SIZEP(cs->cmddata_buf) =
			VARHDRSZ + (cp - VARDATA(cs->cmddata_buf));
	}
	else
		elog(ERROR, "Slony-I: logTrigger() fired for unhandled event");

	/*
	 * Construct the parameter array and insert the log row.
	 */
	argv[0] = TransactionIdGetDatum(cs->currentXid);
	argv[1] = Int32GetDatum(tab_id);
	argv[2] = PointerGetDatum(cmdtype);
	argv[3] = PointerGetDatum(cs->cmddata_buf);
	SPI_execp(cs->plan_active_log, argv, NULL, 0);

	SPI_finish();
	return PointerGetDatum(NULL);
}


Datum
_Slony_I_denyAccess(PG_FUNCTION_ARGS)
{
	Slony_I_ClusterStatus *cs;
	TriggerData *tg;
	int			rc;
	Name		cluster_name;

	/*
	 * Get the trigger call context
	 */
	if (!CALLED_AS_TRIGGER(fcinfo))
		elog(ERROR, "Slony-I: denyAccess() not called as trigger");
	tg = (TriggerData *) (fcinfo->context);

	/*
	 * Check all logTrigger() calling conventions
	 */
	if (!TRIGGER_FIRED_BEFORE(tg->tg_event))
		elog(ERROR, "Slony-I: denyAccess() must be fired BEFORE");
	if (!TRIGGER_FIRED_FOR_ROW(tg->tg_event))
		elog(ERROR, "Slony-I: denyAccess() must be fired FOR EACH ROW");
	if (tg->tg_trigger->tgnargs != 1)
		elog(ERROR, "Slony-I: denyAccess() must be defined with 1 arg");

	/*
	 * Connect to the SPI manager
	 */
	if ((rc = SPI_connect()) < 0)
		elog(ERROR, "Slony-I: SPI_connect() failed in denyAccess()");

	/*
	 * Get all the trigger arguments
	 */
	cluster_name = DatumGetName(DirectFunctionCall1(namein,
								CStringGetDatum(tg->tg_trigger->tgargs[0])));

	/*
	 * Get or create the cluster status information and make sure it has the
	 * SPI plans that we need here.
	 */
	cs = getClusterStatus(cluster_name, PLAN_INSERT_LOG);

	/*
	 * Check/set the session role
	 */
	switch (cs->session_role)
	{
		case SLON_ROLE_UNSET:	/* Unknown or Normal is not allowed here */
		case SLON_ROLE_NORMAL:
			cs->session_role = SLON_ROLE_NORMAL;
			elog(ERROR,
				 "Slony-I: Table %s is replicated and cannot be "
				 "modified on a subscriber node",
				 NameStr(tg->tg_relation->rd_rel->relname));
			break;

		case SLON_ROLE_SLON:	/* Replication session, nothing to do here */
			break;
	}

	SPI_finish();
	if (TRIGGER_FIRED_BY_UPDATE(tg->tg_event))
		return PointerGetDatum(tg->tg_newtuple);
	else
		return PointerGetDatum(tg->tg_trigtuple);
}


Datum
_Slony_I_lockedSet(PG_FUNCTION_ARGS)
{
	TriggerData *tg;

	/*
	 * Get the trigger call context
	 */
	if (!CALLED_AS_TRIGGER(fcinfo))
		elog(ERROR, "Slony-I: lockedSet() not called as trigger");
	tg = (TriggerData *) (fcinfo->context);

	/*
	 * Check all logTrigger() calling conventions
	 */
	if (!TRIGGER_FIRED_BEFORE(tg->tg_event))
		elog(ERROR, "Slony-I: denyAccess() must be fired BEFORE");
	if (!TRIGGER_FIRED_FOR_ROW(tg->tg_event))
		elog(ERROR, "Slony-I: denyAccess() must be fired FOR EACH ROW");
	if (tg->tg_trigger->tgnargs != 1)
		elog(ERROR, "Slony-I: denyAccess() must be defined with 1 arg");

	elog(ERROR,
		 "Slony-I: Table %s is currently locked against updates "
		 "because of MOVE_SET operation in progress",
		 NameStr(tg->tg_relation->rd_rel->relname));

	return (Datum)0;
}


Datum
_Slony_I_killBackend(PG_FUNCTION_ARGS)
{
	int32		pid;
	int32		signo;
	text	   *signame;

	if (!superuser())
		elog(ERROR, "Slony-I: insufficient privilege for killBackend");

	pid		= PG_GETARG_INT32(0);
	signame	= PG_GETARG_TEXT_P(1);

	if (VARSIZE(signame) == VARHDRSZ + 4 &&
		memcmp(VARDATA(signame), "NULL", 0) == 0)
	{
		signo = 0;
	}
	else if (VARSIZE(signame) == VARHDRSZ + 4 &&
		memcmp(VARDATA(signame), "TERM", 0) == 0)
	{
		signo = SIGTERM;
	}
	else
	{
		elog(ERROR, "Slony-I: unsupported signal");
	}

	if (kill(pid, signo) < 0)
		PG_RETURN_INT32(-1);

	PG_RETURN_INT32(0);
}


static char *
slon_quote_literal(char *str)
{
	char	   *result;
	char	   *cp1;
	char	   *cp2;
	int			len;
	int			wl;

	if (str == NULL)
		return NULL;

	len = strlen(str);
	result = palloc(len * 2 + 3);
	cp1 = str;
	cp2 = result;

	*cp2++ = '\'';
	while (len > 0)
	{
		if ((wl = pg_mblen((unsigned char *)cp1)) != 1)
		{
			len -= wl;

			while (wl-- > 0)
				*cp2++ = *cp1++;
			continue;
		}

		if (*cp1 == '\'')
			*cp2++ = '\'';
		if (*cp1 == '\\')
			*cp2++ = '\\';
		*cp2++ = *cp1++;
		len--;
	}

	*cp2++ = '\'';
	*cp2++ = '\0';

	return result;
}


/*
 * slon_quote_identifier                     - Quote an identifier only if needed
 *
 * When quotes are needed, we palloc the required space; slightly
 * space-wasteful but well worth it for notational simplicity.
 *
 * Version: pgsql/src/backend/utils/adt/ruleutils.c,v 1.188 2005/01/13 17:19:10
 */
const char *
slon_quote_identifier(const char *ident)
{
        /*
         * Can avoid quoting if ident starts with a lowercase letter or
         * underscore and contains only lowercase letters, digits, and
         * underscores, *and* is not any SQL keyword.  Otherwise, supply
         * quotes.
         */
        int                     nquotes = 0;
        bool            safe;
        const char *ptr;
        char       *result;
        char       *optr;

        /*
         * would like to use <ctype.h> macros here, but they might yield
         * unwanted locale-specific results...
         */
        safe = ((ident[0] >= 'a' && ident[0] <= 'z') || ident[0] == '_');

        for (ptr = ident; *ptr; ptr++)
        {
                char            ch = *ptr;

                if ((ch >= 'a' && ch <= 'z') ||
                        (ch >= '0' && ch <= '9') ||
                        (ch == '_'))
                {
                        /* okay */
                }
                else
                {
                        safe = false;
                        if (ch == '"')
                                nquotes++;
                }
        }

        if (safe)
        {
                /*
                 * Check for keyword.  This test is overly strong, since many of
                 * the "keywords" known to the parser are usable as column names,
                 * but the parser doesn't provide any easy way to test for whether
                 * an identifier is safe or not... so be safe not sorry.
                 *
                 * Note: ScanKeywordLookup() does case-insensitive comparison, but
                 * that's fine, since we already know we have all-lower-case.
                 */
                if (ScanKeywordLookup(ident) != NULL)
                        safe = false;
        }

        if (safe)
                return ident;                   /* no change needed */

        result = (char *) palloc(strlen(ident) + nquotes + 2 + 1);

        optr = result;
        *optr++ = '"';
        for (ptr = ident; *ptr; ptr++)
        {
                char            ch = *ptr;

                if (ch == '"')
                        *optr++ = '"';
                *optr++ = ch;
        }
        *optr++ = '"';
        *optr = '\0';

        return result;
}



/*
 * _slon_quote_ident -
 *        returns a properly quoted identifier
 *
 * Version: pgsql/src/backend/utils/adt/quote.c,v 1.14.4.1 2005/03/21 16:29:31
 */
Datum
_slon_quote_ident(PG_FUNCTION_ARGS)
{
        text       *t = PG_GETARG_TEXT_P(0);
        text       *result;
        const char *qstr;
        char       *str;
        int                     len;

        /* We have to convert to a C string to use quote_identifier */
        len = VARSIZE(t) - VARHDRSZ;
        str = (char *) palloc(len + 1);
        memcpy(str, VARDATA(t), len);
        str[len] = '\0';

        qstr = slon_quote_identifier(str);

        len = strlen(qstr);
        result = (text *) palloc(len + VARHDRSZ);
        VARATT_SIZEP(result) = len + VARHDRSZ;
        memcpy(VARDATA(result), qstr, len);

        PG_RETURN_TEXT_P(result);
}



static Slony_I_ClusterStatus *
getClusterStatus(Name cluster_name, int need_plan_mask)
{
	Slony_I_ClusterStatus *cs;
	int			rc;
	char		query  [1024];
	bool		isnull;
	Oid			plan_types[12];
	Oid			xxid_typid;
	TypeName   *xxid_typename;

	/*
	 * Find an existing cs row for this cluster
	 */
	for (cs = clusterStatusList; cs; cs = cs->next)
	{
		if ((bool) DirectFunctionCall2(nameeq,
									   NameGetDatum(&(cs->clustername)),
									   NameGetDatum(cluster_name)) == true)
		{
			/*
			 * Return it if all the requested SPI plans are prepared already.
			 */
			if ((cs->have_plan & need_plan_mask) == need_plan_mask)
				return cs;

			/*
			 * Create more SPI plans below.
			 */
			break;
		}
	}

	if (cs == NULL)
	{
		/*
		 * No existing cs found ... create a new one
		 */
		cs = (Slony_I_ClusterStatus *) malloc(sizeof(Slony_I_ClusterStatus));
		memset(cs, 0, sizeof(Slony_I_ClusterStatus));

		/*
		 * We remember the plain cluster name for fast lookup
		 */
		strncpy(NameStr(cs->clustername), NameStr(*cluster_name), NAMEDATALEN);

		/*
		 * ... and the quoted identifier of it for building queries
		 */
		cs->clusterident = strdup(DatumGetCString(DirectFunctionCall1(textout,
											 DirectFunctionCall1(quote_ident,
																 DirectFunctionCall1(textin, CStringGetDatum(NameStr(*cluster_name)))))));

		/*
		 * Get our local node ID
		 */
		snprintf(query, 1024, "select last_value::int4 from %s.sl_local_node_id",
				 cs->clusterident);
		rc = SPI_exec(query, 0);
		if (rc < 0 || SPI_processed != 1)
			elog(ERROR, "Slony-I: failed to read sl_local_node_id");
		cs->localNodeId = DatumGetInt32(
										SPI_getbinval(SPI_tuptable->vals[0], SPI_tuptable->tupdesc, 1, &isnull));
		SPI_freetuptable(SPI_tuptable);
		if (cs->localNodeId < 0)
			elog(ERROR, "Slony-I: Node is uninitialized");

		/*
		 * Initialize the currentXid to invalid
		 */
		cs->currentXid = InvalidTransactionId;

		/*
		 * Insert the new control block into the list
		 */
		cs->next = clusterStatusList;
		clusterStatusList = cs;
	}

	/*
	 * Prepare and save the PLAN_NOTIFT_EVENT
	 */
	if ((need_plan_mask & PLAN_NOTIFY_EVENT) != 0 &&
		(cs->have_plan & PLAN_NOTIFY_EVENT) == 0)
	{
		sprintf(query, "NOTIFY \"%s_Event\";", NameStr(cs->clustername));
		cs->plan_notify_event = SPI_saveplan(SPI_prepare(query, 0, NULL));
		if (cs->plan_notify_event == NULL)
			elog(ERROR, "Slony-I: SPI_prepare() failed");

		cs->have_plan |= PLAN_NOTIFY_EVENT;
	}

	/*
	 * Prepare and save the PLAN_INSERT_EVENT
	 */
	if ((need_plan_mask & PLAN_INSERT_EVENT) != 0 &&
		(cs->have_plan & PLAN_INSERT_EVENT) == 0)
	{
		/*
		 * Lookup the oid of our special xxid type
		 */
		xxid_typename = makeNode(TypeName);
		xxid_typename->names =
			lappend(lappend(NIL, makeString(NameStr(cs->clustername))),
					makeString("xxid"));
		xxid_typid = typenameTypeId(xxid_typename);

		plan_types[0] = INT4OID;

		/*
		 * Create the saved plan. We lock the sl_event table in exclusive mode
		 * in order to ensure that all events are really assigned sequence
		 * numbers in the order they get committed.
		 */
		sprintf(query,
				"LOCK TABLE %s.sl_event IN EXCLUSIVE MODE; "
				"INSERT INTO %s.sl_event "
				"(ev_origin, ev_seqno, "
				"ev_timestamp, ev_minxid, ev_maxxid, ev_xip, "
				"ev_type, ev_data1, ev_data2, ev_data3, ev_data4, "
				"ev_data5, ev_data6, ev_data7, ev_data8) "
				"VALUES ('%d', nextval('%s.sl_event_seq'), "
				"now(), $1, $2, $3, "
				"$4, $5, $6, $7, $8, $9, $10, $11, $12); "
				"SELECT currval('%s.sl_event_seq');",
				cs->clusterident,
				cs->clusterident, cs->localNodeId, cs->clusterident,
				cs->clusterident);
		plan_types[0] = xxid_typid;
		plan_types[1] = xxid_typid;
		plan_types[2] = TEXTOID;
		plan_types[3] = TEXTOID;
		plan_types[4] = TEXTOID;
		plan_types[5] = TEXTOID;
		plan_types[6] = TEXTOID;
		plan_types[7] = TEXTOID;
		plan_types[8] = TEXTOID;
		plan_types[9] = TEXTOID;
		plan_types[10] = TEXTOID;
		plan_types[11] = TEXTOID;

		cs->plan_insert_event = SPI_saveplan(SPI_prepare(query, 12, plan_types));
		if (cs->plan_insert_event == NULL)
			elog(ERROR, "Slony-I: SPI_prepare() failed");

		/*
		 * Also prepare the plan to remember sequence numbers on certain
		 * events.
		 */
		sprintf(query,
				"insert into %s.sl_seqlog "
				"(seql_seqid, seql_origin, seql_ev_seqno, seql_last_value) "
		   "select seq_id, '%d', currval('%s.sl_event_seq'), seq_last_value "
				"from %s.sl_seqlastvalue "
				"where seq_origin = '%d'; "
				"insert into %s.sl_seqlog "
				"(seql_seqid, seql_origin, seql_ev_seqno, seql_last_value) "
				"select '0', '%d', currval('%s.sl_event_seq'), "
				" last_value from %s.sl_rowid_seq; ",
				cs->clusterident,
				cs->localNodeId, cs->clusterident,
				cs->clusterident, cs->localNodeId,
				cs->clusterident, cs->localNodeId,
				cs->clusterident, cs->clusterident);

		cs->plan_record_sequences = SPI_saveplan(SPI_prepare(query, 0, NULL));
		if (cs->plan_record_sequences == NULL)
			elog(ERROR, "Slony-I: SPI_prepare() failed");

		cs->have_plan |= PLAN_INSERT_EVENT;
	}

	/*
	 * Prepare and save the PLAN_INSERT_LOG
	 */
	if ((need_plan_mask & PLAN_INSERT_LOG) != 0 &&
		(cs->have_plan & PLAN_INSERT_LOG) == 0)
	{
		/*
		 * Lookup the oid of our special xxid type
		 */
		xxid_typename = makeNode(TypeName);
		xxid_typename->names =
			lappend(lappend(NIL, makeString(NameStr(cs->clustername))),
					makeString("xxid"));
		xxid_typid = typenameTypeId(xxid_typename);

		/*
		 * Create the saved plan's
		 */
		sprintf(query, "INSERT INTO %s.sl_log_1 "
				"(log_origin, log_xid, log_tableid, log_actionseq,"
				" log_cmdtype, log_cmddata) "
				"VALUES (%d, $1, $2, nextval('%s.sl_action_seq'),"
				" $3, $4);",
				cs->clusterident, cs->localNodeId, cs->clusterident);
		plan_types[0] = xxid_typid;
		plan_types[1] = INT4OID;
		plan_types[2] = TEXTOID;
		plan_types[3] = TEXTOID;

		cs->plan_insert_log_1 = SPI_saveplan(SPI_prepare(query, 4, plan_types));
		if (cs->plan_insert_log_1 == NULL)
			elog(ERROR, "Slony-I: SPI_prepare() failed");

		sprintf(query, "INSERT INTO %s.sl_log_2 "
				"(log_origin, log_xid, log_tableid, log_actionseq,"
				" log_cmdtype, log_cmddata) "
				"VALUES (%d, $1, $2, nextval('%s.sl_action_seq'),"
				" $3, $4);",
				cs->clusterident, cs->localNodeId, cs->clusterident);
		plan_types[0] = xxid_typid;
		plan_types[1] = INT4OID;
		plan_types[2] = TEXTOID;
		plan_types[3] = TEXTOID;

		cs->plan_insert_log_2 = SPI_saveplan(SPI_prepare(query, 4, plan_types));
		if (cs->plan_insert_log_2 == NULL)
			elog(ERROR, "Slony-I: SPI_prepare() failed");

		/*
		 * Also create the 3 rather static text values for the log_cmdtype
		 * parameter and initialize the cmddata_buf.
		 */
		cs->cmdtype_I = malloc(VARHDRSZ + 1);
		VARATT_SIZEP(cs->cmdtype_I) = VARHDRSZ + 1;
		*VARDATA(cs->cmdtype_I) = 'I';
		cs->cmdtype_U = malloc(VARHDRSZ + 1);
		VARATT_SIZEP(cs->cmdtype_U) = VARHDRSZ + 1;
		*VARDATA(cs->cmdtype_U) = 'U';
		cs->cmdtype_D = malloc(VARHDRSZ + 1);
		VARATT_SIZEP(cs->cmdtype_D) = VARHDRSZ + 1;
		*VARDATA(cs->cmdtype_D) = 'D';

		cs->cmddata_size = 8192;
		cs->cmddata_buf = (text *) malloc(8192);

		cs->have_plan |= PLAN_INSERT_LOG;
	}

	return cs;
}


/*
 * Local Variables:
 *	tab-width: 4
 *	c-indent-level: 4
 *	c-basic-offset: 4
 * End:
 */
