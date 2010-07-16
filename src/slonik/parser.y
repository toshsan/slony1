%{
/*-------------------------------------------------------------------------
 * parser.y
 *
 *	The slonik command language grammar
 *
 *	Copyright (c) 2003-2006, PostgreSQL Global Development Group
 *	Author: Jan Wieck, Afilias USA INC.
 *
 *	
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "libpq-fe.h"
#include "slonik.h"


/*
 * Common option types
 */
typedef enum {
	O_ADD_ID,
	O_BACKUP_NODE,
	O_CLIENT,
	O_COMMENT,
	O_CONNINFO,
	O_CONNRETRY,
	O_EVENT_NODE,
	O_EXECUTE_ONLY_ON,
	O_FILENAME,
	O_FORWARD,
	O_FQNAME,
	O_ID,
	O_NEW_ORIGIN,
	O_NEW_SET,
	O_NODE_ID,
	O_OLD_ORIGIN,
	O_ORIGIN,
	O_PROVIDER,
	O_RECEIVER,
	O_SECONDS,
	O_SERVER,
	O_SER_KEY,
	O_SET_ID,
	O_SPOOLNODE,
	O_TAB_ID,
	O_TIMEOUT,
	O_TRIG_NAME,
	O_USE_KEY,
	O_WAIT_CONFIRMED,
	O_WAIT_ON,

	END_OF_OPTIONS = -1
} option_code;


/*
 * Common given option list
 */
typedef struct option_list {
	option_code	opt_code;
	int			lineno;
	int32		ival;
	char	   *str;

	struct option_list *next;
} option_list;


/*
 * Common per statement possible option strcture
 */
typedef struct statement_option {
	option_code	opt_code;
	int			lineno;
	int			ival;
	char	   *str;
} statement_option;
#define	STMT_OPTION_INT(_code,_dfl)		{_code, -1, _dfl, NULL}
#define	STMT_OPTION_STR(_code,_dfl)		{_code, -1, -1, _dfl}
#define	STMT_OPTION_YN(_code,_dfl)		{_code, -1, _dfl, NULL}
#define STMT_OPTION_END					{END_OF_OPTIONS, -1, -1, NULL}


/*
 * Global data
 */
char   *current_file = "<stdin>";
extern int yyleng;
#ifdef DEBUG
int yydebug=1;
#endif
/*
 * Local functions
 */
static int	assign_options(statement_option *so, option_list *ol);



%}

/*
 * Parser lval and types
 */
%union {
	int32		ival;
	char		*str;
	option_list	*opt_list;
	SlonikAdmInfo	*adm_info;
	SlonikStmt	*statement;
}

%type <ival>		id
%type <ival>		lno
%type <ival>		exit_code
%type <str>		literal
%type <str>		ident
%type <str>		hdr_clustername
%type <adm_info>	hdr_admconninfos
%type <adm_info>	hdr_admconninfo
%type <statement>	stmts
%type <statement>	stmt
%type <statement>	stmt_try
%type <statement>	try_stmts
%type <statement>	try_stmt
%type <statement>	try_on_error
%type <statement>	try_on_success
%type <statement>	stmt_echo
%type <statement>	stmt_exit
%type <statement>	stmt_restart_node
%type <statement>	stmt_error
%type <statement>	stmt_init_cluster
%type <statement>	stmt_store_node
%type <statement>	stmt_drop_node
%type <statement>	stmt_failed_node
%type <statement>	stmt_uninstall_node
%type <statement>	stmt_store_path
%type <statement>	stmt_drop_path
%type <statement>	stmt_store_listen
%type <statement>	stmt_drop_listen
%type <statement>	stmt_create_set
%type <statement>	stmt_drop_set
%type <statement>	stmt_merge_set
%type <statement>	stmt_set_add_table
%type <statement>	stmt_set_add_sequence
%type <statement>	stmt_set_drop_table
%type <statement>	stmt_set_drop_sequence
%type <statement>	stmt_set_move_table
%type <statement>	stmt_set_move_sequence
%type <statement>	stmt_table_add_key
%type <statement>	stmt_store_trigger
%type <statement>	stmt_drop_trigger
%type <statement>	stmt_subscribe_set
%type <statement>	stmt_unsubscribe_set
%type <statement>	stmt_lock_set
%type <statement>	stmt_unlock_set
%type <statement>	stmt_move_set
%type <statement>	stmt_ddl_script
%type <statement>	stmt_update_functions
%type <statement>	stmt_repair_config
%type <statement>	stmt_wait_event
%type <statement>	stmt_sync
%type <statement>	stmt_sleep
%type <opt_list>	option_list
%type <opt_list>	option_list_item
%type <opt_list>	option_list_items
%type <opt_list>	option_item_id
%type <opt_list>	option_item_literal
%type <opt_list>	option_item_yn


/*
 * Keyword tokens
 */
%token	K_ADD
%token	K_ADMIN
%token	K_ALL
%token	K_BACKUP
%token	K_CLIENT
%token	K_CLUSTER
%token	K_CLUSTERNAME
%token	K_COMMENT
%token	K_CONFIG
%token	K_CONFIRMED
%token	K_CONNINFO
%token	K_CONNRETRY
%token	K_CREATE
%token	K_DROP
%token	K_ECHO
%token	K_ERROR
%token	K_EVENT
%token	K_EXECUTE
%token	K_EXIT
%token	K_FAILOVER
%token	K_FALSE
%token	K_FILENAME
%token	K_FOR
%token	K_FORWARD
%token	K_FULL
%token	K_FUNCTIONS
%token	K_ID
%token	K_INIT
%token	K_KEY
%token	K_LISTEN
%token	K_LOCK
%token	K_MERGE
%token	K_MOVE
%token	K_NAME
%token	K_NEW
%token	K_NO
%token	K_NODE
%token	K_OFF
%token	K_OLD
%token	K_ON
%token	K_ONLY
%token	K_ORIGIN
%token	K_PATH
%token	K_PROVIDER
%token	K_QUALIFIED
%token	K_RECEIVER
%token	K_RESTART
%token	K_SCRIPT
%token	K_SEQUENCE
%token	K_SERIAL
%token	K_SERVER
%token	K_SET
%token	K_SLEEP
%token	K_SPOOLNODE
%token	K_STORE
%token	K_SUBSCRIBE
%token	K_SUCCESS
%token	K_SYNC
%token	K_TABLE
%token	K_TIMEOUT
%token	K_TRIGGER
%token	K_TRUE
%token	K_TRY
%token	K_UNINSTALL
%token	K_UNLOCK
%token	K_UNSUBSCRIBE
%token	K_UPDATE
%token	K_WAIT
%token	K_YES
%token  K_REPAIR
%token  K_SECONDS

/*
 * Other scanner tokens
 */
%token	T_IDENT
%token	T_LITERAL
%token	T_NUMBER


%%

/*
 * A script consists of header information and statements
 */
script				: hdr_clustername
                      hdr_admconninfos
					  stmts
                    {
						parser_script = (SlonikScript *)
								malloc(sizeof(SlonikScript));
						memset(parser_script, 0, sizeof(SlonikScript));

						parser_script->clustername		= $1;
						parser_script->filename			= current_file;
						parser_script->adminfo_list		= $2;
						parser_script->script_stmts		= $3;
					}
					;

hdr_clustername		: lno K_CLUSTER K_NAME '=' ident ';'
					{
						$$ = $5;
					}
					;

hdr_admconninfos	: hdr_admconninfo
					{ $$ = $1; }
					| hdr_admconninfo hdr_admconninfos
					{ $1->next = $2; $$ = $1; }
					;

hdr_admconninfo		: lno K_NODE id K_ADMIN K_CONNINFO '=' literal ';'
					{
						SlonikAdmInfo	   *new;

						new = (SlonikAdmInfo *)
								malloc(sizeof(SlonikAdmInfo));
						memset(new, 0, sizeof(SlonikAdmInfo));

						new->no_id			= $3;
						new->stmt_filename	= current_file;
						new->stmt_lno		= $1;
						new->conninfo		= $7;
						new->last_event		= -1;

						$$ = new;
					}
					;

stmts				: stmt
						{ $$ = $1; }
					| stmt stmts
						{ $1->next = $2; $$ = $1; }
					;

stmt				: stmt_try
						{ $$ = $1; }
					| try_stmt
						{ $$ = $1; }
					;

stmt_try			: lno K_TRY '{' try_stmts '}'
					  try_on_error
					{
						SlonikStmt_try *new;

						new = (SlonikStmt_try *)
								malloc(sizeof(SlonikStmt_try));
						memset(new, 0, sizeof(SlonikStmt_try));
						new->hdr.stmt_type		= STMT_TRY;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						new->try_block = $4;
						new->error_block = $6;

						$$ = (SlonikStmt *)new;
					}
					| lno K_TRY '{' try_stmts '}'
					  try_on_success try_on_error
					{
						SlonikStmt_try *new;

						new = (SlonikStmt_try *)
								malloc(sizeof(SlonikStmt_try));
						memset(new, 0, sizeof(SlonikStmt_try));
						new->hdr.stmt_type		= STMT_TRY;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						new->try_block = $4;
						new->success_block = $6;
						new->error_block = $7;

						$$ = (SlonikStmt *)new;
					}
					| lno K_TRY '{' try_stmts '}'
					  try_on_error try_on_success 
					{
						SlonikStmt_try *new;

						new = (SlonikStmt_try *)
								malloc(sizeof(SlonikStmt_try));
						memset(new, 0, sizeof(SlonikStmt_try));
						new->hdr.stmt_type		= STMT_TRY;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						new->try_block = $4;
						new->success_block = $7;
						new->error_block = $6;

						$$ = (SlonikStmt *)new;
					}
					| lno K_TRY '{' try_stmts '}'
					  try_on_success
					{
						SlonikStmt_try *new;

						new = (SlonikStmt_try *)
								malloc(sizeof(SlonikStmt_try));
						memset(new, 0, sizeof(SlonikStmt_try));
						new->hdr.stmt_type		= STMT_TRY;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						new->try_block = $4;
						new->success_block = $6;

						$$ = (SlonikStmt *)new;
					}
					| lno K_TRY '{' try_stmts '}'
					{
						SlonikStmt_try *new;

						new = (SlonikStmt_try *)
								malloc(sizeof(SlonikStmt_try));
						memset(new, 0, sizeof(SlonikStmt_try));
						new->hdr.stmt_type		= STMT_TRY;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						new->try_block = $4;

						$$ = (SlonikStmt *)new;
					}
					;

try_on_error		: K_ON K_ERROR '{' stmts '}'
						{ $$ = $4; }
					;
try_on_success		: K_ON K_SUCCESS '{' stmts '}'
						{ $$ = $4; }
					;

try_stmts			: try_stmt
						{ $$ = $1; }
					| try_stmt try_stmts
						{ $1->next = $2; $$ = $1; }
					;

try_stmt			: stmt_echo
						{ $$ = $1; }
					| stmt_exit
						{ $$ = $1; }
					| stmt_restart_node
						{ $$ = $1; }
					| stmt_init_cluster
						{ $$ = $1; }
					| stmt_store_node
						{ $$ = $1; }
					| stmt_drop_node
						{ $$ = $1; }
					| stmt_failed_node
						{ $$ = $1; }
					| stmt_uninstall_node
						{ $$ = $1; }
					| stmt_store_path
						{ $$ = $1; }
					| stmt_drop_path
						{ $$ = $1; }
					| stmt_store_listen
						{ $$ = $1; }
					| stmt_drop_listen
						{ $$ = $1; }
					| stmt_create_set
						{ $$ = $1; }
					| stmt_drop_set
						{ $$ = $1; }
					| stmt_merge_set
						{ $$ = $1; }
					| stmt_table_add_key
						{ $$ = $1; }
					| stmt_set_add_table
						{ $$ = $1; }
					| stmt_set_add_sequence
						{ $$ = $1; }
					| stmt_set_drop_table
						{ $$ = $1; }
					| stmt_set_drop_sequence
						{ $$ = $1; }
					| stmt_set_move_table
						{ $$ = $1; }
					| stmt_set_move_sequence
						{ $$ = $1; }
					| stmt_store_trigger
						{ $$ = $1; }
					| stmt_drop_trigger
						{ $$ = $1; }
					| stmt_subscribe_set
						{ $$ = $1; }
					| stmt_unsubscribe_set
						{ $$ = $1; }
					| stmt_lock_set
						{ $$ = $1; }
					| stmt_unlock_set
						{ $$ = $1; }
					| stmt_move_set
						{ $$ = $1; }
					| stmt_ddl_script
						{ $$ = $1; }
					| stmt_update_functions
						{ $$ = $1; }
					| stmt_repair_config
						{ $$ = $1; }
					| stmt_wait_event
						{ $$ = $1; }
					| stmt_error ';' 
						{ yyerrok;
						  $$ = $1; }
					| stmt_sync
						{ $$ = $1; }
					| stmt_sleep
						{ $$ = $1; }
					;

stmt_echo			: lno K_ECHO literal ';'
					{
						SlonikStmt_echo *new;

						new = (SlonikStmt_echo *)
								malloc(sizeof(SlonikStmt_echo));
						memset(new, 0, sizeof(SlonikStmt_echo));
						new->hdr.stmt_type		= STMT_ECHO;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						new->str = $3;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_exit			: lno K_EXIT exit_code ';'
					{
						SlonikStmt_exit *new;

						new = (SlonikStmt_exit *)
								malloc(sizeof(SlonikStmt_exit));
						memset(new, 0, sizeof(SlonikStmt_exit));
						new->hdr.stmt_type		= STMT_EXIT;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						new->exitcode = $3;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_restart_node	: lno K_RESTART K_NODE id ';'
					{
						SlonikStmt_restart_node *new;

						new = (SlonikStmt_restart_node *)
								malloc(sizeof(SlonikStmt_restart_node));
						memset(new, 0, sizeof(SlonikStmt_restart_node));
						new->hdr.stmt_type		= STMT_RESTART_NODE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						new->no_id = $4;

						$$ = (SlonikStmt *)new;
					}
					;

exit_code			: T_NUMBER
						{ $$ = strtol(yytext, NULL, 10); }
					| '-' exit_code
						{ $$ = -$2; }
					;

stmt_error			: lno error
					{
						SlonikStmt *new;

						new = (SlonikStmt *)
								malloc(sizeof(SlonikStmt));
						memset(new, 0, sizeof(SlonikStmt));
						new->stmt_type		= STMT_ERROR;
						new->stmt_filename	= current_file;
						new->stmt_lno		= $1;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_init_cluster	: lno K_INIT K_CLUSTER option_list
					{
						SlonikStmt_init_cluster *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, 1 ),
							STMT_OPTION_STR( O_COMMENT, "Primary Node 1" ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_init_cluster *)
								malloc(sizeof(SlonikStmt_init_cluster));
						memset(new, 0, sizeof(SlonikStmt_init_cluster));
						new->hdr.stmt_type		= STMT_INIT_CLUSTER;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->no_id			= opt[0].ival;
							new->no_comment		= opt[1].str;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_store_node		: lno K_STORE K_NODE option_list
					{
						SlonikStmt_store_node *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_STR( O_COMMENT, NULL ),
							STMT_OPTION_YN( O_SPOOLNODE, 0 ),
							STMT_OPTION_INT( O_EVENT_NODE, 1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_store_node *)
								malloc(sizeof(SlonikStmt_store_node));
						memset(new, 0, sizeof(SlonikStmt_store_node));
						new->hdr.stmt_type		= STMT_STORE_NODE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->no_id			= opt[0].ival;
							new->no_comment		= opt[1].str;
							new->no_spool		= opt[2].ival;
							new->ev_origin		= opt[3].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_drop_node		: lno K_DROP K_NODE option_list
					{
						SlonikStmt_drop_node *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_EVENT_NODE, 1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_drop_node *)
								malloc(sizeof(SlonikStmt_drop_node));
						memset(new, 0, sizeof(SlonikStmt_drop_node));
						new->hdr.stmt_type		= STMT_DROP_NODE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->no_id			= opt[0].ival;
							new->ev_origin		= opt[1].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_failed_node	: lno K_FAILOVER option_list
					{
						SlonikStmt_failed_node *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_BACKUP_NODE, 1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_failed_node *)
								malloc(sizeof(SlonikStmt_failed_node));
						memset(new, 0, sizeof(SlonikStmt_failed_node));
						new->hdr.stmt_type		= STMT_FAILED_NODE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $3) == 0)
						{
							new->no_id			= opt[0].ival;
							new->backup_node	= opt[1].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_uninstall_node	: lno K_UNINSTALL K_NODE option_list
					{
						SlonikStmt_uninstall_node *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_uninstall_node *)
								malloc(sizeof(SlonikStmt_uninstall_node));
						memset(new, 0, sizeof(SlonikStmt_uninstall_node));
						new->hdr.stmt_type		= STMT_UNINSTALL_NODE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->no_id			= opt[0].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_store_path		: lno K_STORE K_PATH option_list
					{
						SlonikStmt_store_path *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_SERVER, -1 ),
							STMT_OPTION_INT( O_CLIENT, -1 ),
							STMT_OPTION_STR( O_CONNINFO, NULL ),
							STMT_OPTION_INT( O_CONNRETRY, 10 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_store_path *)
								malloc(sizeof(SlonikStmt_store_path));
						memset(new, 0, sizeof(SlonikStmt_store_path));
						new->hdr.stmt_type		= STMT_STORE_PATH;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->pa_server		= opt[0].ival;
							new->pa_client		= opt[1].ival;
							new->pa_conninfo	= opt[2].str;
							new->pa_connretry	= opt[3].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_drop_path		: lno K_DROP K_PATH option_list
					{
						SlonikStmt_drop_path *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_SERVER, -1 ),
							STMT_OPTION_INT( O_CLIENT, -1 ),
							STMT_OPTION_INT( O_EVENT_NODE, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_drop_path *)
								malloc(sizeof(SlonikStmt_drop_path));
						memset(new, 0, sizeof(SlonikStmt_drop_path));
						new->hdr.stmt_type		= STMT_DROP_PATH;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->pa_server		= opt[0].ival;
							new->pa_client		= opt[1].ival;
							new->ev_origin		= opt[2].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_store_listen	: lno K_STORE K_LISTEN option_list
					{
						SlonikStmt_store_listen *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_INT( O_RECEIVER, -1 ),
							STMT_OPTION_INT( O_PROVIDER, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_store_listen *)
								malloc(sizeof(SlonikStmt_store_listen));
						memset(new, 0, sizeof(SlonikStmt_store_listen));
						new->hdr.stmt_type		= STMT_STORE_LISTEN;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->li_origin		= opt[0].ival;
							new->li_receiver	= opt[1].ival;
							new->li_provider	= opt[2].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_drop_listen	: lno K_DROP K_LISTEN option_list
					{
						SlonikStmt_drop_listen *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_INT( O_RECEIVER, -1 ),
							STMT_OPTION_INT( O_PROVIDER, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_drop_listen *)
								malloc(sizeof(SlonikStmt_drop_listen));
						memset(new, 0, sizeof(SlonikStmt_drop_listen));
						new->hdr.stmt_type		= STMT_DROP_LISTEN;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->li_origin		= opt[0].ival;
							new->li_receiver	= opt[1].ival;
							new->li_provider	= opt[2].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_create_set		: lno K_CREATE K_SET option_list
					{
						SlonikStmt_create_set *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_STR( O_COMMENT, NULL ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_create_set *)
								malloc(sizeof(SlonikStmt_create_set));
						memset(new, 0, sizeof(SlonikStmt_create_set));
						new->hdr.stmt_type		= STMT_CREATE_SET;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->set_id			= opt[0].ival;
							new->set_origin		= opt[1].ival;
							new->set_comment	= opt[2].str;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_drop_set		: lno K_DROP K_SET option_list
					{
						SlonikStmt_drop_set *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_drop_set *)
								malloc(sizeof(SlonikStmt_drop_set));
						memset(new, 0, sizeof(SlonikStmt_drop_set));
						new->hdr.stmt_type		= STMT_DROP_SET;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->set_id			= opt[0].ival;
							new->set_origin		= opt[1].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_merge_set		: lno K_MERGE K_SET option_list
					{
						SlonikStmt_merge_set *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_ADD_ID, -1 ),
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_merge_set *)
								malloc(sizeof(SlonikStmt_merge_set));
						memset(new, 0, sizeof(SlonikStmt_merge_set));
						new->hdr.stmt_type		= STMT_MERGE_SET;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->set_id			= opt[0].ival;
							new->add_id			= opt[1].ival;
							new->set_origin		= opt[2].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_table_add_key	: lno K_TABLE K_ADD K_KEY option_list
					{
						SlonikStmt_table_add_key *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_NODE_ID, -1 ),
							STMT_OPTION_STR( O_FQNAME, NULL ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_table_add_key *)
								malloc(sizeof(SlonikStmt_table_add_key));
						memset(new, 0, sizeof(SlonikStmt_table_add_key));
						new->hdr.stmt_type		= STMT_TABLE_ADD_KEY;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $5) == 0)
						{
							new->no_id			= opt[0].ival;
							new->tab_fqname		= opt[1].str;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_set_add_table	: lno K_SET K_ADD K_TABLE option_list
					{
						SlonikStmt_set_add_table *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_SET_ID, -1 ),
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_STR( O_FQNAME, NULL ),
							STMT_OPTION_STR( O_USE_KEY, NULL ),
							STMT_OPTION_INT( O_SER_KEY, 0 ),
							STMT_OPTION_STR( O_COMMENT, NULL ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_set_add_table *)
								malloc(sizeof(SlonikStmt_set_add_table));
						memset(new, 0, sizeof(SlonikStmt_set_add_table));
						new->hdr.stmt_type		= STMT_SET_ADD_TABLE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $5) == 0)
						{
							new->set_id			= opt[0].ival;
							new->set_origin		= opt[1].ival;
							new->tab_id			= opt[2].ival;
							new->tab_fqname		= opt[3].str;
							new->use_key		= opt[4].str;
							new->use_serial		= opt[5].ival;
							new->tab_comment	= opt[6].str;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_set_add_sequence : lno K_SET K_ADD K_SEQUENCE option_list
					{
						SlonikStmt_set_add_sequence *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_SET_ID, -1 ),
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_STR( O_FQNAME, NULL ),
							STMT_OPTION_STR( O_COMMENT, NULL ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_set_add_sequence *)
								malloc(sizeof(SlonikStmt_set_add_sequence));
						memset(new, 0, sizeof(SlonikStmt_set_add_sequence));
						new->hdr.stmt_type		= STMT_SET_ADD_SEQUENCE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $5) == 0)
						{
							new->set_id			= opt[0].ival;
							new->set_origin		= opt[1].ival;
							new->seq_id			= opt[2].ival;
							new->seq_fqname		= opt[3].str;
							new->seq_comment	= opt[4].str;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_set_drop_table	: lno K_SET K_DROP K_TABLE option_list
					{
						SlonikStmt_set_drop_table *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_END
						};
						new = (SlonikStmt_set_drop_table *)
							malloc(sizeof(SlonikStmt_set_drop_table));
						memset(new, 0, sizeof(SlonikStmt_set_drop_table));
						new->hdr.stmt_type		= STMT_SET_DROP_TABLE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $5) == 0) {
							new->set_origin		= opt[0].ival;
							new->tab_id			= opt[1].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_set_drop_sequence : lno K_SET K_DROP K_SEQUENCE option_list
					{
						SlonikStmt_set_drop_sequence *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_set_drop_sequence *)
								malloc(sizeof(SlonikStmt_set_drop_sequence));
						memset(new, 0, sizeof(SlonikStmt_set_drop_sequence));
						new->hdr.stmt_type		= STMT_SET_DROP_SEQUENCE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $5) == 0)
						{
							new->set_origin		= opt[0].ival;
							new->seq_id			= opt[1].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_set_move_table	: lno K_SET K_MOVE K_TABLE option_list
					{
						SlonikStmt_set_move_table *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_NEW_SET, -1 ),
							STMT_OPTION_END
						};
						new = (SlonikStmt_set_move_table *)
							malloc(sizeof(SlonikStmt_set_move_table));
						memset(new, 0, sizeof(SlonikStmt_set_move_table));
						new->hdr.stmt_type		= STMT_SET_MOVE_TABLE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $5) == 0) {
							new->set_origin		= opt[0].ival;
							new->tab_id			= opt[1].ival;
							new->new_set_id		= opt[2].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_set_move_sequence : lno K_SET K_MOVE K_SEQUENCE option_list
					{
						SlonikStmt_set_move_sequence *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_NEW_SET, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_set_move_sequence *)
								malloc(sizeof(SlonikStmt_set_move_sequence));
						memset(new, 0, sizeof(SlonikStmt_set_move_sequence));
						new->hdr.stmt_type		= STMT_SET_MOVE_SEQUENCE;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $5) == 0)
						{
							new->set_origin		= opt[0].ival;
							new->seq_id			= opt[1].ival;
							new->new_set_id		= opt[2].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_store_trigger	: lno K_STORE K_TRIGGER option_list
					{
						SlonikStmt_store_trigger *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_TAB_ID, -1 ),
							STMT_OPTION_STR( O_TRIG_NAME, NULL ),
							STMT_OPTION_INT( O_EVENT_NODE, 1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_store_trigger *)
								malloc(sizeof(SlonikStmt_store_trigger));
						memset(new, 0, sizeof(SlonikStmt_store_trigger));
						new->hdr.stmt_type		= STMT_STORE_TRIGGER;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->trig_tabid		= opt[0].ival;
							new->trig_tgname	= opt[1].str;
							new->ev_origin		= opt[2].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_drop_trigger	: lno K_DROP K_TRIGGER option_list
					{
						SlonikStmt_drop_trigger *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_TAB_ID, -1 ),
							STMT_OPTION_STR( O_TRIG_NAME, NULL ),
							STMT_OPTION_INT( O_EVENT_NODE, 1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_drop_trigger *)
								malloc(sizeof(SlonikStmt_drop_trigger));
						memset(new, 0, sizeof(SlonikStmt_drop_trigger));
						new->hdr.stmt_type		= STMT_DROP_TRIGGER;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->trig_tabid		= opt[0].ival;
							new->trig_tgname	= opt[1].str;
							new->ev_origin		= opt[2].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_subscribe_set	: lno K_SUBSCRIBE K_SET option_list
					{
						SlonikStmt_subscribe_set *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_PROVIDER, -1 ),
							STMT_OPTION_INT( O_RECEIVER, -1 ),
							STMT_OPTION_YN( O_FORWARD, 0 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_subscribe_set *)
								malloc(sizeof(SlonikStmt_subscribe_set));
						memset(new, 0, sizeof(SlonikStmt_subscribe_set));
						new->hdr.stmt_type		= STMT_SUBSCRIBE_SET;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->sub_setid		= opt[0].ival;
							new->sub_provider	= opt[1].ival;
							new->sub_receiver	= opt[2].ival;
							new->sub_forward	= opt[3].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_unsubscribe_set	: lno K_UNSUBSCRIBE K_SET option_list
					{
						SlonikStmt_unsubscribe_set *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_RECEIVER, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_unsubscribe_set *)
								malloc(sizeof(SlonikStmt_unsubscribe_set));
						memset(new, 0, sizeof(SlonikStmt_unsubscribe_set));
						new->hdr.stmt_type		= STMT_UNSUBSCRIBE_SET;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->sub_setid		= opt[0].ival;
							new->sub_receiver	= opt[1].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_lock_set		: lno K_LOCK K_SET option_list
					{
						SlonikStmt_lock_set *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_lock_set *)
								malloc(sizeof(SlonikStmt_lock_set));
						memset(new, 0, sizeof(SlonikStmt_lock_set));
						new->hdr.stmt_type		= STMT_LOCK_SET;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->set_id			= opt[0].ival;
							new->set_origin		= opt[1].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_unlock_set		: lno K_UNLOCK K_SET option_list
					{
						SlonikStmt_unlock_set *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_unlock_set *)
								malloc(sizeof(SlonikStmt_unlock_set));
						memset(new, 0, sizeof(SlonikStmt_unlock_set));
						new->hdr.stmt_type		= STMT_UNLOCK_SET;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->set_id			= opt[0].ival;
							new->set_origin		= opt[1].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_move_set		: lno K_MOVE K_SET option_list
					{
						SlonikStmt_move_set *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_INT( O_OLD_ORIGIN, -1 ),
							STMT_OPTION_INT( O_NEW_ORIGIN, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_move_set *)
								malloc(sizeof(SlonikStmt_move_set));
						memset(new, 0, sizeof(SlonikStmt_move_set));
						new->hdr.stmt_type		= STMT_MOVE_SET;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->set_id			= opt[0].ival;
							new->old_origin		= opt[1].ival;
							new->new_origin		= opt[2].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_ddl_script		: lno K_EXECUTE K_SCRIPT option_list
					{
						SlonikStmt_ddl_script *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_SET_ID, -1 ),
							STMT_OPTION_STR( O_FILENAME, NULL ),
							STMT_OPTION_INT( O_EVENT_NODE, 1 ),
							STMT_OPTION_INT( O_EXECUTE_ONLY_ON, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_ddl_script *)
								malloc(sizeof(SlonikStmt_ddl_script));
						memset(new, 0, sizeof(SlonikStmt_ddl_script));
						new->hdr.stmt_type		= STMT_DDL_SCRIPT;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->ddl_setid		= opt[0].ival;
							new->ddl_fname		= opt[1].str;
							new->ev_origin		= opt[2].ival;
							new->only_on_node	= opt[3].ival;
							new->ddl_fd			= -1;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_update_functions	: lno K_UPDATE K_FUNCTIONS option_list
					{
						SlonikStmt_update_functions *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, 1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_update_functions *)
								malloc(sizeof(SlonikStmt_update_functions));
						memset(new, 0, sizeof(SlonikStmt_update_functions));
						new->hdr.stmt_type		= STMT_UPDATE_FUNCTIONS;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $4) == 0)
						{
							new->no_id			= opt[0].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;
stmt_repair_config		: lno K_REPAIR K_CONFIG option_list
					{
						SlonikStmt_repair_config *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_SET_ID, -1 ),
							STMT_OPTION_INT( O_EVENT_NODE, 1 ),
							STMT_OPTION_INT( O_EXECUTE_ONLY_ON, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_repair_config *)
							malloc(sizeof(SlonikStmt_repair_config));
						memset(new, 0, sizeof(SlonikStmt_repair_config));
                                                new->hdr.stmt_type              = STMT_REPAIR_CONFIG;
                                                new->hdr.stmt_filename  = current_file;
                                                new->hdr.stmt_lno               = $1;

                                                if (assign_options(opt, $4) == 0)
						{
							new->set_id		= opt[0].ival;
							new->ev_origin		= opt[1].ival;
							new->only_on_node	= opt[2].ival;
						}
						else
						{
							parser_errors++;
						}
                                                $$ = (SlonikStmt *)new;
                                        }
                                        ;

stmt_wait_event		: lno K_WAIT K_FOR K_EVENT option_list
					{
						SlonikStmt_wait_event *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ORIGIN, -1 ),
							STMT_OPTION_INT( O_WAIT_CONFIRMED, -1 ),
							STMT_OPTION_INT( O_WAIT_ON, 1 ),
							STMT_OPTION_INT( O_TIMEOUT, 600 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_wait_event *)
								malloc(sizeof(SlonikStmt_wait_event));
						memset(new, 0, sizeof(SlonikStmt_wait_event));
						new->hdr.stmt_type		= STMT_WAIT_EVENT;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $5) == 0)
						{
							new->wait_origin	= opt[0].ival;
							new->wait_confirmed	= opt[1].ival;
							new->wait_on		= opt[2].ival;
							new->wait_timeout	= opt[3].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_sync			: lno K_SYNC option_list
					{
						SlonikStmt_sync *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_ID, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_sync *)
								malloc(sizeof(SlonikStmt_sync));
						memset(new, 0, sizeof(SlonikStmt_sync));
						new->hdr.stmt_type		= STMT_SYNC;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $3) == 0)
						{
							new->no_id			= opt[0].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

stmt_sleep			: lno K_SLEEP option_list
					{
						SlonikStmt_sleep *new;
						statement_option opt[] = {
							STMT_OPTION_INT( O_SECONDS, -1 ),
							STMT_OPTION_END
						};

						new = (SlonikStmt_sleep *)
								malloc(sizeof(SlonikStmt_sleep));
						memset(new, 0, sizeof(SlonikStmt_sleep));
						new->hdr.stmt_type		= STMT_SLEEP;
						new->hdr.stmt_filename	= current_file;
						new->hdr.stmt_lno		= $1;

						if (assign_options(opt, $3) == 0)
						{
							new->num_secs			= opt[0].ival;
						}
						else
							parser_errors++;

						$$ = (SlonikStmt *)new;
					}
					;

option_list			: ';'
					{ $$ = NULL; }
					| '(' option_list_items ')' ';'
					{ $$ = $2; }
					;

option_list_items	: option_list_item
					{ $$ = $1; }
					| option_list_item ',' option_list_items
					{ $1->next = $3; $$ = $1; }
					;

option_list_item	: K_ID '=' option_item_id
					{
						$3->opt_code	= O_ID;
						$$ = $3;
					}
					| K_BACKUP K_NODE '=' option_item_id
					{
						$4->opt_code	= O_BACKUP_NODE;
						$$ = $4;
					}
					| K_EVENT K_NODE '=' option_item_id
					{
						$4->opt_code	= O_EVENT_NODE;
						$$ = $4;
					}
					| K_SERVER '=' option_item_id
					{
						$3->opt_code	= O_SERVER;
						$$ = $3;
					}
					| K_CLIENT '=' option_item_id
					{
						$3->opt_code	= O_CLIENT;
						$$ = $3;
					}
					| K_ORIGIN '=' option_item_id
					{
						$3->opt_code	= O_ORIGIN;
						$$ = $3;
					}
					| K_OLD K_ORIGIN '=' option_item_id
					{
						$4->opt_code	= O_OLD_ORIGIN;
						$$ = $4;
					}
					| K_NEW K_ORIGIN '=' option_item_id
					{
						$4->opt_code	= O_NEW_ORIGIN;
						$$ = $4;
					}
					| K_NEW K_SET '=' option_item_id
					{
						$4->opt_code	= O_NEW_SET;
						$$ = $4;
					}
					| K_RECEIVER '=' option_item_id
					{
						$3->opt_code	= O_RECEIVER;
						$$ = $3;
					}
					| K_PROVIDER '=' option_item_id
					{
						$3->opt_code	= O_PROVIDER;
						$$ = $3;
					}
					| K_CONNRETRY '=' option_item_id
					{
						$3->opt_code	= O_CONNRETRY;
						$$ = $3;
					}
					| K_COMMENT '=' option_item_literal
					{
						$3->opt_code	= O_COMMENT;
						$$ = $3;
					}
					| K_CONNINFO '=' option_item_literal
					{
						$3->opt_code	= O_CONNINFO;
						$$ = $3;
					}
					| K_SET K_ID '=' option_item_id
					{
						$4->opt_code	= O_SET_ID;
						$$ = $4;
					}
					| K_ADD K_ID '=' option_item_id
					{
						$4->opt_code	= O_ADD_ID;
						$$ = $4;
					}
					| K_NODE K_ID '=' option_item_id
					{
						$4->opt_code	= O_NODE_ID;
						$$ = $4;
					}
					| K_TABLE K_ID '=' option_item_id
					{
						$4->opt_code	= O_TAB_ID;
						$$ = $4;
					}
					| K_TRIGGER K_NAME '=' option_item_literal
					{
						$4->opt_code	= O_TRIG_NAME;
						$$ = $4;
					}
					| K_FULL K_QUALIFIED K_NAME '=' option_item_literal
					{
						$5->opt_code	= O_FQNAME;
						$$ = $5;
					}
					| K_KEY '=' option_item_literal
					{
						$3->opt_code	= O_USE_KEY;
						$$ = $3;
					}
					| K_KEY '=' K_SERIAL
					{
						option_list *new;
						new = (option_list *)malloc(sizeof(option_list));

						new->opt_code	= O_SER_KEY;
						new->ival	= 1;
						new->str	= NULL;
						new->lineno	= yylineno;
						new->next	= NULL;

						$$ = new;
					}
					| K_FORWARD '=' option_item_yn
					{
						$3->opt_code	= O_FORWARD;
						$$ = $3;
					}
					| K_FILENAME '=' option_item_literal
					{
						$3->opt_code	= O_FILENAME;
						$$ = $3;
					}
					| K_ORIGIN '=' K_ALL
					{
						option_list *new;
						new = (option_list *)malloc(sizeof(option_list));

						new->opt_code	= O_ORIGIN;
						new->ival	= -2;
						new->str	= NULL;
						new->lineno	= yylineno;
						new->next	= NULL;

						$$ = new;
					}
					| K_CONFIRMED '=' option_item_id
					{
						$3->opt_code	= O_WAIT_CONFIRMED;
						$$ = $3;
					}
					| K_CONFIRMED '=' K_ALL
					{
						option_list *new;
						new = (option_list *)malloc(sizeof(option_list));

						new->opt_code	= O_WAIT_CONFIRMED;
						new->ival	= -2;
						new->str	= NULL;
						new->lineno	= yylineno;
						new->next	= NULL;

						$$ = new;
					}
					| K_WAIT K_ON '=' option_item_id
					{
						$4->opt_code	= O_WAIT_ON;
						$$ = $4;
					}
					| K_TIMEOUT '=' option_item_id
					{
						$3->opt_code	= O_TIMEOUT;
						$$ = $3;
					}
					| K_EXECUTE K_ONLY K_ON '=' option_item_id
					{
						$5->opt_code	= O_EXECUTE_ONLY_ON;
						$$ = $5;
					}
					| K_SPOOLNODE '=' option_item_yn
					{
						$3->opt_code	= O_SPOOLNODE;
						$$ = $3;
					}
					| K_SECONDS '=' option_item_id
					{
						$3->opt_code	= O_SECONDS;
						$$ = $3;
					}
					;

option_item_id		: id
					{
						option_list *new;
						new = (option_list *)malloc(sizeof(option_list));

						new->ival	= $1;
						new->str	= NULL;
						new->lineno	= yylineno;
						new->next	= NULL;

						$$ = new;
					}
					;

option_item_literal	: literal
					{
						option_list *new;
						new = (option_list *)malloc(sizeof(option_list));

						new->ival	= -1;
						new->str	= $1;
						new->lineno	= yylineno;
						new->next	= NULL;

						$$ = new;
					}
					;

option_item_yn		: option_item_yn_yes
					{
						option_list *new;
						new = (option_list *)malloc(sizeof(option_list));

						new->ival	= 1;
						new->str	= NULL;
						new->lineno	= yylineno;
						new->next	= NULL;

						$$ = new;
					}
					| option_item_yn_no
					{
						option_list *new;
						new = (option_list *)malloc(sizeof(option_list));

						new->ival	= 0;
						new->str	= NULL;
						new->lineno	= yylineno;
						new->next	= NULL;

						$$ = new;
					}
					;

option_item_yn_yes	: K_YES
					| K_ON
					| K_TRUE
					;

option_item_yn_no	: K_NO
					| K_OFF
					| K_FALSE
					;

id					: T_NUMBER
					{
						$$ = strtol(yytext, NULL, 10);
					}
					;

ident				: T_IDENT
					{
						char   *ret;

						ret = malloc(yyleng + 1);
						memcpy(ret, yytext, yyleng);
						ret[yyleng] = '\0';

						$$ = ret;
					}
					;

literal				: T_LITERAL
					{
						char   *ret;

						ret = malloc(yyleng + 1);
						memcpy(ret, yytext, yyleng);
						ret[yyleng] = '\0';

						$$ = ret;
					}
					;

lno					:
					{ $$ = yylineno; }
					;

%%


/* ----------
 * option_str
 *
 *	Returns a string representation of a common option type
 * ----------
 */
static char *
option_str(option_code opt_code)
{
	switch (opt_code)
	{
		case O_ADD_ID:			return "add id";
		case O_BACKUP_NODE:		return "backup node";
		case O_CLIENT:			return "client";
		case O_COMMENT:			return "comment";
		case O_CONNINFO:		return "conninfo";
		case O_CONNRETRY:		return "connretry";
		case O_EVENT_NODE:		return "event node";
		case O_EXECUTE_ONLY_ON:	return "execute only on";
		case O_FILENAME:		return "filename";
		case O_FORWARD:			return "forward";
		case O_FQNAME:			return "full qualified name";
		case O_ID:				return "id";
		case O_NEW_ORIGIN:		return "new origin";
		case O_NEW_SET:			return "new set";
		case O_NODE_ID:			return "node id";
		case O_OLD_ORIGIN:		return "old origin";
		case O_ORIGIN:			return "origin";
		case O_PROVIDER:		return "provider";
		case O_RECEIVER:		return "receiver";
    	case O_SECONDS:         return "seconds";
		case O_SERVER:			return "server";
		case O_SER_KEY:			return "key";
		case O_SET_ID:			return "set id";
		case O_SPOOLNODE:		return "spoolnode";
		case O_TAB_ID:			return "table id";
		case O_TIMEOUT:			return "timeout";
		case O_TRIG_NAME:		return "trigger name";
		case O_USE_KEY:			return "key";
		case O_WAIT_CONFIRMED:	return "confirmed";
		case O_WAIT_ON:			return "wait on";
		case END_OF_OPTIONS:	return "???";
	}
	return "???";
}

/* ----------
 * assign_options
 *
 *	Try to map the actually given options to the statements specific
 *	possible options.
 * ----------
 */
static int
assign_options(statement_option *so, option_list *ol)
{
	statement_option	   *s_opt;
	option_list			   *u_opt;
	int						errors = 0;

	for (u_opt = ol; u_opt; u_opt = u_opt->next)
	{
		for (s_opt = so; s_opt->opt_code >= 0; s_opt++)
		{
			if (s_opt->opt_code == u_opt->opt_code)
				break;
		}

		if (s_opt->opt_code < 0)
		{
			fprintf(stderr, "%s:%d: option %s not allowed here\n",
					current_file, u_opt->lineno,
					option_str(u_opt->opt_code));
			errors++;
			continue;
		}

		if (s_opt->lineno >= 0)
		{
			fprintf(stderr, "%s:%d: option %s already defined on line %d\n",
					current_file, u_opt->lineno,
					option_str(u_opt->opt_code), s_opt->lineno);
			errors++;
			continue;
		}

		s_opt->lineno	= u_opt->lineno;
		s_opt->ival		= u_opt->ival;
		s_opt->str		= u_opt->str;
	}

	return errors;
}


void
yyerror(const char *msg)
{
	fprintf(stderr, "%s:%d: ERROR: %s at or near %s\n", current_file,
				yylineno, msg, yytext);
	parser_errors++;
}


/*
 * Include the output of fles for the scanner here.
 */
#include "scan.c"



/*
 * Local Variables:
 *  tab-width: 4
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 */
