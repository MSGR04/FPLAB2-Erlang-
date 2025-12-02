-module(oa_set_props).

-include_lib("proper/include/proper.hrl").

-export([prop_monoid_identity/0,
         prop_monoid_associativity/0,
         prop_member_insert_delete/0]).

%% генератор произвольных списков целых
int_list() ->
    list(integer()).

set_from_list(L) ->
    oa_set:from_list(L).

%% 1) Свойства моноида: left/right identity

prop_monoid_identity() ->
    ?FORALL(L, int_list(),
        begin
            S = set_from_list(L),
            E = oa_set:empty(),
            oa_set:equal(oa_set:union(E, S), S)
            andalso
            oa_set:equal(oa_set:union(S, E), S)
        end).

%% 2) Ассоциативность union

prop_monoid_associativity() ->
    ?FORALL({L1, L2, L3}, {int_list(), int_list(), int_list()},
        begin
            A = set_from_list(L1),
            B = set_from_list(L2),
            C = set_from_list(L3),
            Left  = oa_set:union(A, oa_set:union(B, C)),
            Right = oa_set:union(oa_set:union(A, B), C),
            oa_set:equal(Left, Right)
        end).

%% 3) Инвариант вставки/удаления

prop_member_insert_delete() ->
    ?FORALL({X, L}, {integer(), int_list()},
        begin
            S0 = set_from_list(L),
            S1 = oa_set:insert(X, S0),
            S2 = oa_set:delete(X, S1),
            %% после insert элемент есть, после delete – нет
            oa_set:member(X, S1) andalso not oa_set:member(X, S2)
        end).
