-module(oa_set_tests).

-include_lib("eunit/include/eunit.hrl").

new_is_empty_test() ->
    S = oa_set:new(),
    ?assert(oa_set:is_empty(S)),
    ?assertEqual(0, oa_set:size(S)).

insert_member_test() ->
    S0 = oa_set:new(),
    S1 = oa_set:insert(1, S0),
    ?assert(oa_set:member(1, S1)),
    ?assertNot(oa_set:member(2, S1)),
    ?assertNot(oa_set:member(1, S0)).

delete_test() ->
    S0 = oa_set:from_list([1,2,3]),
    S1 = oa_set:delete(2, S0),
    ?assertNot(oa_set:member(2, S1)),
    ?assert(oa_set:member(1, S1)),
    ?assert(oa_set:member(3, S1)).

map_filter_fold_test() ->
    S  = oa_set:from_list([1,2,3]),
    S2 = oa_set:map(fun(X) -> X * 2 end, S),
    ?assert(oa_set:member(4, S2)),
    ?assertNot(oa_set:member(1, S2)),
    S3 = oa_set:filter(fun(X) -> X rem 2 =:= 0 end, S2),
    ?assertEqual(true, oa_set:equal(S3, oa_set:from_list([2,4,6]))),
    Sum = oa_set:foldl(fun(X, Acc) -> X + Acc end, 0, S3),
    ?assertEqual(12, Sum).

monoid_unit_test() ->
    E = oa_set:empty(),
    A = oa_set:from_list([1,2]),
    B = oa_set:from_list([2,3]),
    ?assert(oa_set:equal(oa_set:union(E, A), A)),
    ?assert(oa_set:equal(oa_set:union(A, E), A)),
    ?assert(oa_set:equal(
              oa_set:union(A, oa_set:union(B, E)),
              oa_set:union(oa_set:union(A, B), E))).
