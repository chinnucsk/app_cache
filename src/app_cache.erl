%%%-------------------------------------------------------------------
%%% @author Juan Jose Comellas <juanjo@comellas.org>
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @author Tom Heinan <me@tomheinan.com>
%%% @copyright (C) 2011-2012 Juan Jose Comellas, Mahesh Paolini-Subramanya
%%% @doc Generic app to provide caching
%%% @end
%%%
%%% This source file is subject to the New BSD License. You should have received
%%% a copy of the New BSD license with this software. If not, it can be
%%% retrieved from: http://www.opensource.org/licenses/bsd-license.php
%%%-------------------------------------------------------------------
-module(app_cache).

-author('Juan Jose Comellas <juanjo@comellas.org>').
-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').
-author('Tom Heinan <me@tomheinan.com>').

-compile([{parse_transform, dynarec}]).
-compile([{parse_transform, lager_transform}]).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

%% Mnesia utility APIs
-export([get_env/0, get_env/1, get_env/2]).
-export([setup/0, start/0, stop/0, 
         cache_init/1, cache_init/2,
         init_metatable/0, init_metatable/1, init_table/1, init_table/2,
         get_metatable/0,
         create_tables/0, create_tables/1, create_metatable/0, create_metatable/1, create_table/1, create_table/2,
         upgrade_metatable/0, upgrade_table/1, upgrade_table/2, upgrade_table/4,
         table_info/1, table_version/1, table_time_to_live/1, table_fields/1,
         update_table_time_to_live/2,
         last_update_to_datetime/1, current_time_in_gregorian_seconds/0,
         cache_time_to_live/1, get_ttl_and_field_index/1,
         get_record_fields/1
        ]).

%% Data accessor APIs
-export([key_exists/2, get_data_from_index/3, get_data/2, get_last_entered_data/1, get_after/2, set_data/1, remove_data/2]).
-export([key_exists/3, get_data_from_index/4, get_data/3, get_last_entered_data/2, get_after/3, set_data/2, remove_data/3]).

%% ------------------------------------------------------------------
%% Includes & Defines
%% ------------------------------------------------------------------

-include("defaults.hrl").

-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
%%
%% Environment helper functions
%%

%% @doc Retrieve all key/value pairs in the env for the specified app.
-spec get_env() -> [{Key :: atom(), Value :: term()}].
get_env() ->
    application:get_all_env(?SERVER).

%% @doc The official way to get a value from the app's env.
%%      Will return the 'undefined' atom if that key is unset.
-spec get_env(Key :: atom()) -> term().
get_env(Key) ->
    get_env(Key, undefined).

%% @doc The official way to get a value from this application's env.
%%      Will return Default if that key is unset.
-spec get_env(Key :: atom(), Default :: term()) -> term().
get_env(Key, Default) ->
    case application:get_env(?SERVER, Key) of
        {ok, Value} ->
            Value;
        _ ->
            Default
    end.
%%
%% Application utility functions
%%

%% @doc Start the application and all its dependencies.
-spec start() -> ok.
start() ->
    start_deps(?SERVER).

-spec start_deps(App :: atom()) -> ok.
start_deps(App) ->
    application:load(App),
    {ok, Deps} = application:get_key(App, applications),
    lists:foreach(fun start_deps/1, Deps),
    start_app(App).

-spec start_app(App :: atom()) -> ok.
start_app(App) ->
    case application:start(App) of
        {error, {already_started, _}} -> ok;
        ok                            -> ok
    end.


%% @doc Stop the application and all its dependencies.
-spec stop() -> ok.
stop() ->
    stop_deps(?SERVER).

-spec stop_deps(App :: atom()) -> ok.
stop_deps(App) ->
    stop_app(App),
    {ok, Deps} = application:get_key(App, applications),
    lists:foreach(fun stop_deps/1, lists:reverse(Deps)).

-spec stop_app(App :: atom()) -> ok.
stop_app(kernel) ->
    ok;
stop_app(stdlib) ->
    ok;
stop_app(App) ->
    case application:stop(App) of
        {error, {not_started, _}} -> ok;
        ok                        -> ok
    end.


%%
%% Mnesia utility functions
%%
%% @doc setup mnesia on this node for disc copies
-spec setup() -> {atomic, ok} | {error, Reason::any()}.
setup() ->
    mnesia:create_schema([node()]).

-spec init_metatable() -> ok | {aborted, Reason :: any()}.
init_metatable() ->
    Nodes = get_env(cache_nodes, [node()]),
    init_metatable(Nodes).

-spec init_metatable([node()]) -> ok | {aborted, Reason :: any()}.
init_metatable(Nodes) ->
    gen_server:call(?PROCESSOR, {init_metatable, Nodes}).

-spec get_metatable() -> [#app_metatable{}] | {aborted, Reason :: any()}.
get_metatable() ->
    gen_server:call(?PROCESSOR, {get_metatable}).

-spec cache_init([#app_metatable{}]) -> ok | {aborted, Reason :: any()}.
cache_init(Tables) ->
    Nodes = get_env(cache_init, [node()]),
    cache_init(Nodes, Tables).

-spec cache_init([node()], [#app_metatable{}]) -> ok | {aborted, Reason :: any()}.
cache_init(Nodes, Tables) ->
    NewTables = lists:map(fun(TableInfo) ->
                    Fields = get_record_fields(TableInfo#app_metatable.table),
                    TableInfo#app_metatable{fields = Fields} 
            end, Tables),
    gen_server:call(?PROCESSOR, {cache_init, Nodes, NewTables}).


-spec create_tables() -> ok | {aborted, Reason :: any()}.
create_tables() ->
    Nodes = get_env(cache_nodes, [node()]),
    create_tables(Nodes).

-spec create_tables([node()]) -> ok | {aborted, Reason :: any()}.
create_tables(Nodes) ->
    gen_server:call(?PROCESSOR, {create_tables, Nodes}).


create_metatable() ->
    Nodes = get_env(cache_nodes, [node()]),
    create_metatable(Nodes).

-spec create_metatable([node()]) -> ok | {aborted, Reason :: any()}.
create_metatable(Nodes) ->
    app_cache_processor:create_metatable(Nodes).

-spec init_table(table()) -> ok | {aborted, Reason :: any()}.
init_table(Table) ->
    Nodes = get_env(cache_nodes, [node()]),
    init_table(Table, Nodes).

-spec init_table(table(), [node()]) -> ok | {aborted, Reason :: any()}.
init_table(Table, Nodes) ->
    gen_server:call(?PROCESSOR, {init_table, Table, Nodes}).

-spec create_table(#app_metatable{}) -> ok | {aborted, Reason :: any()}.
create_table(TableInfo) ->
    Nodes = get_env(cache_nodes, [node()]),
    create_table(TableInfo, Nodes).

-spec create_table(#app_metatable{}, [node()]) -> ok | {aborted, Reason :: any()}.
create_table(TableInfo, Nodes) ->
    Fields = get_record_fields(TableInfo#app_metatable.table),
    NewTableInfo = TableInfo#app_metatable{fields = Fields}, 
    gen_server:call(?PROCESSOR, {create_table, NewTableInfo, Nodes}).

% TODO make this dependant on the node
-spec upgrade_metatable() -> {atomic, ok} | {aborted, Reason :: any()}.
upgrade_metatable() ->
    app_cache_processor:upgrade_metatable().

-spec upgrade_table(table()) -> {atomic, ok} | {aborted, Reason :: any()}.
upgrade_table(Table) ->
    app_cache_processor:upgrade_table(Table).


-spec upgrade_table(table(), [app_field()]) -> {atomic, ok} | {aborted, Reason :: any()}.
upgrade_table(Table, Fields) ->
    app_cache_processor:upgrade_table(Table, Fields).

-spec upgrade_table(table(), OldVersion :: non_neg_integer(), NewVersion :: non_neg_integer(), [app_field()]) -> {atomic, ok} | {aborted, Reason :: any()}.
upgrade_table(Table, OldVersion, NewVersion, Fields) ->
    app_cache_processor:upgrade_table(Table, OldVersion, NewVersion, Fields).

-spec table_info(table()) -> #app_metatable{} | undefined.
table_info(Table) ->
    gen_server:call(?PROCESSOR, {table_info, Table}).

-spec table_version(table()) -> table_version().
table_version(Table) ->
    gen_server:call(?PROCESSOR, {table_version, Table}).

-spec table_time_to_live(table()) -> time_to_live().
table_time_to_live(Table) ->
    gen_server:call(?PROCESSOR, {table_time_to_live, Table}).

-spec table_fields(table()) -> table_fields().
table_fields(Table) ->
    app_cache_processor:table_fields(Table).

-spec current_time_in_gregorian_seconds() -> non_neg_integer().
current_time_in_gregorian_seconds() ->
    calendar:datetime_to_gregorian_seconds(calendar:universal_time()).

-spec cache_time_to_live(table()) -> time_to_live().
cache_time_to_live(Table) ->
    {TTL, _} = get_ttl_and_field_index(Table),
    TTL.

-spec last_update_to_datetime(last_update()) -> calendar:datetime().
last_update_to_datetime(LastUpdate) ->
    calendar:gregorian_seconds_to_datetime(LastUpdate).

-spec get_ttl_and_field_index(table()) -> {timestamp(), table_key_position()}.
get_ttl_and_field_index(Table) ->
    app_cache_processor:get_ttl_and_field_index(Table).

-spec update_table_time_to_live(table(), time_to_live()) -> {timestamp(), table_key_position()}.
update_table_time_to_live(Table, TTL) ->
    gen_server:call(?PROCESSOR, {update_table_time_to_live, Table, TTL}).

%%
%% Table accessors
%%
-spec key_exists(Table::table(), Key::table_key()) -> any().
key_exists(Table, Key) ->
    key_exists(?TRANSACTION_TYPE_SAFE, Table, Key).

-spec key_exists(transaction_type(), Table::table(), Key::table_key()) -> any().
key_exists(TransactionType, Table, Key) ->
    app_cache_processor:check_key_exists(TransactionType, Table, Key).

-spec get_data(Table::table(), Key::table_key()) -> any().
get_data(Table, Key) ->
    get_data(?TRANSACTION_TYPE_SAFE, Table, Key).

-spec get_data(transaction_type(), Table::table(), Key::table_key()) -> any().
get_data(TransactionType, Table, Key) ->
    app_cache_processor:read_data(TransactionType, Table, Key).

-spec get_data_from_index(Table::table(), Key::table_key(), IndexField::table_key()) -> any().
get_data_from_index(Table, Key, IndexField) ->
    get_data_from_index(?TRANSACTION_TYPE_SAFE, Table, Key, IndexField).

-spec get_data_from_index(transaction_type(), Table::table(), Key::table_key(), IndexField::table_key()) -> any().
get_data_from_index(TransactionType, Table, Key, IndexField) ->
    app_cache_processor:read_data_from_index(TransactionType, Table, Key, IndexField).

-spec get_last_entered_data(Table::table()) -> any().
get_last_entered_data(Table) ->
    get_last_entered_data(?TRANSACTION_TYPE_SAFE, Table).

-spec get_last_entered_data(transaction_type(), Table::table()) -> any().
get_last_entered_data(TransactionType, Table) ->
    app_cache_processor:read_last_entered_data(TransactionType, Table).

%% Get data after (in erlang term order) a value
-spec get_after(table(), table_key()) -> any().
get_after(Table, After) ->
    get_after(?TRANSACTION_TYPE_SAFE, Table, After).

%% Get data after (in erlang term order) a value
-spec get_after(transaction_type(), table(), table_key()) -> any().
get_after(TransactionType, Table, After) ->
    app_cache_processor:read_after(TransactionType, Table, After).

-spec set_data(Value::any()) -> ok | error().
set_data(Value) ->
    set_data(?TRANSACTION_TYPE_SAFE, Value).

-spec set_data(transaction_type(), Value::any()) -> ok | error().
set_data(TransactionType, Value) ->
    app_cache_processor:write_data(TransactionType, Value).

-spec remove_data(Table::table(), Key::table_key()) -> ok | error().
remove_data(Table, Key) ->
    remove_data(?TRANSACTION_TYPE_SAFE, Table, Key).

-spec remove_data(transaction_type(), Table::table(), Key::table_key()) -> ok | error().
remove_data(TransactionType, Table, Key) ->
    app_cache_processor:delete_data(TransactionType, Table, Key).

-spec get_record_fields(table_key()) -> list().
get_record_fields(RecordName) ->
    fields(RecordName).

