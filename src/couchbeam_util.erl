%%% -*- erlang -*-
%%%
%%% This file is part of couchbeam released under the MIT license. 
%%% See the NOTICE for more information.

-module(couchbeam_util).

-export([json_encode/1, json_decode/1]).
-export([encode_docid/1]).
-export([parse_options/1, parse_options/2]).
-export([to_list/1, to_binary/1, to_integer/1, to_atom/1]).
-export([encode_query/1, encode_query_value/2]).
-export([oauth_header/3]).
-export([propmerge/3, propmerge1/2]).
-export([get_value/2, get_value/3]).

-define(ENCODE_DOCID, true).


json_encode(V) ->
    Handler =
    fun({L}) when is_list(L) ->
        {struct,L};
    (Bad) ->
        exit({json_encode, {bad_term, Bad}})
    end,
    (mochijson2:encoder([{handler, Handler}]))(V).

json_decode(V) ->
    try (mochijson2:decoder([{object_hook, fun({struct,L}) -> {L} end}]))(V)
    catch
        _Type:_Error ->
            throw({invalid_json,V})
    end.


encode_docid(DocId) when is_binary(DocId) ->
    encode_docid(binary_to_list(DocId));
encode_docid(DocId)->
    case ?ENCODE_DOCID of
        true -> encode_docid1(DocId);
        false -> DocId
    end.
    
encode_docid1(DocId) ->
    case DocId of
        "_design/" ++ Rest ->
            Rest1 = encode_docid(Rest),
            "_design/" ++ Rest1;
        _ ->
            ibrowse_lib:url_encode(DocId)
    end.

%% @doc Encode needed value of Query proplists in json
encode_query([]) ->
    [];
encode_query(Query) when is_list(Query) ->
    lists:foldl(fun({K, V}, Acc) ->
        V1 = encode_query_value(K, V), 
        [{K, V1}|Acc]
    end, [], Query);
encode_query(Query) ->
    Query.

%% @doc Encode value in JSON if needed depending on the key 
encode_query_value(K, V) when is_atom(K) ->
    encode_query_value(atom_to_list(K), V);
encode_query_value(K, V) when is_binary(K) ->
    encode_query_value(binary_to_list(K), V);
encode_query_value(K, V) ->
    case K of
        "key" -> couchbeam_util:json_encode(V);
        "startkey" -> couchbeam_util:json_encode(V);
        "endkey" -> couchbeam_util:json_encode(V);
        _ -> V
    end.

% build oauth header
oauth_header(Url, Action, OauthProps) ->
    {_, _, _, QS, _} = mochiweb_util:urlsplit(Url),
    QSL = mochiweb_util:parse_qs(QS),

    % get oauth paramerers
    ConsumerKey = to_list(get_value(consumer_key, OauthProps)),
    Token = to_list(get_value(token, OauthProps)),
    TokenSecret = to_list(get_value(token_secret, OauthProps)),
    ConsumerSecret = to_list(get_value(consumer_secret, OauthProps)),
    SignatureMethodStr = to_list(get_value(signature_method, 
            OauthProps, "HMAC-SHA1")),

    SignatureMethodAtom = case SignatureMethodStr of
        "PLAINTEXT" ->
            plaintext;
        "HMAC-SHA1" ->
            hmac_sha1;
        "RSA-SHA1" ->
            rsa_sha1
    end,
    Consumer = {ConsumerKey, ConsumerSecret, SignatureMethodAtom},
    Method = case Action of
        delete -> "DELETE";
        get -> "GET";
        post -> "POST";
        put -> "PUT";
        head -> "HEAD"
    end,
    Params = oauth:signed_params(Method, Url, QSL, Consumer, Token, TokenSecret)
    -- QSL,
    {"Authorization", "OAuth " ++ oauth_uri:params_to_header_string(Params)}.


%% @doc merge 2 proplists. All the Key - Value pairs from both proplists
%% are included in the new proplists. If a key occurs in both dictionaries 
%% then Fun is called with the key and both values to return a new
%% value. This a wreapper around dict:merge
propmerge(F, L1, L2) ->
	dict:to_list(dict:merge(F, dict:from_list(L1), dict:from_list(L2))).

%% @doc Update a proplist with values of the second. In case the same
%% key is in 2 proplists, the value from the first are kept.
propmerge1(L1, L2) ->
    propmerge(fun(_, V1, _) -> V1 end, L1, L2).


get_value(Key, List) ->
    get_value(Key, List, undefined).

get_value(Key, List, Default) ->
    case lists:keysearch(Key, 1, List) of
    {value, {Key,Value}} ->
        Value;
    false ->
        Default
    end.
    

%% @doc make view options a list
parse_options(Options) ->
    parse_options(Options, []).

parse_options([], Acc) ->
    Acc;
parse_options([V|Rest], Acc) when is_atom(V) ->
    parse_options(Rest, [{atom_to_list(V), true}|Acc]);
parse_options([{K,V}|Rest], Acc) when is_list(K) ->    
    parse_options(Rest, [{K,V}|Acc]);
parse_options([{K,V}|Rest], Acc) when is_binary(K) ->
    parse_options(Rest, [{binary_to_list(K),V}|Acc]);
parse_options([{K,V}|Rest], Acc) when is_atom(K) ->   
    parse_options(Rest, [{atom_to_list(K),V}|Acc]);
parse_options(_,_) ->
    fail.

to_binary(V) when is_binary(V) ->
    V;
to_binary(V) when is_list(V) ->
    try
        list_to_binary(V)
    catch
        _ ->
            list_to_binary(io_lib:format("~p", [V]))
    end;
to_binary(V) when is_atom(V) ->
    list_to_binary(atom_to_list(V));
to_binary(V) ->
    list_to_binary(io_lib:format("~p", [V])).

to_integer(V) when is_integer(V) ->
    V;
to_integer(V) when is_list(V) ->
    erlang:list_to_integer(V);
to_integer(V) when is_binary(V) ->
    erlang:list_to_integer(binary_to_list(V)).

to_list(V) when is_list(V) ->
    V;
to_list(V) when is_binary(V) ->
    binary_to_list(V);
to_list(V) when is_atom(V) ->
    atom_to_list(V);
to_list(V) ->
    lists:flatten(io_lib:format("~p", [V])).

to_atom(V) when is_atom(V) ->
    V;
to_atom(V) when is_list(V) ->
    list_to_atom(V);
to_atom(V) when is_binary(V) ->
    list_to_atom(binary_to_list(V));
to_atom(V) ->
    list_to_atom(lists:flatten(io_lib:format("~p", [V]))).
