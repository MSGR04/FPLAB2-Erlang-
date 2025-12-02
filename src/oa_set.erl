%%%-------------------------------------------------------------------
%%% oa_set: immutable open-addressing set
%%%-------------------------------------------------------------------
-module(oa_set).

-compile({no_auto_import, [size/1]}).

-export([
    new/0,
    empty/0,
    singleton/1,
    from_list/1,

    insert/2,
    delete/2,
    member/2,
    is_empty/1,
    size/1,

    foldl/3,
    foldr/3,
    filter/2,
    map/2,

    union/2,
    equal/2
]).

-record(oa_set, {
    size     = 0   :: non_neg_integer(),
    capacity = 16  :: pos_integer(),
    buckets        :: tuple()
}).

%%--------------------------------------------------------------------
%% Конструкторы
%%--------------------------------------------------------------------

empty() ->
    new().

new() ->
    #oa_set{
        size = 0,
        capacity = 16,
        buckets = empty_tuple(16)
    }.

singleton(X) ->
    insert(X, new()).

from_list(L) when is_list(L) ->
    lists:foldl(fun insert/2, new(), L).

%%--------------------------------------------------------------------
%% Базовые операции API
%%--------------------------------------------------------------------

size(#oa_set{size = S}) -> S.

is_empty(S) ->
    size(S) =:= 0.

member(X, #oa_set{capacity = Cap, buckets = Buckets}) ->
    H = hash(X),
    probe_member(X, H, Buckets, Cap, 0).

insert(X, Set0) ->
    Set1 = ensure_capacity(Set0),
    insert_no_resize(X, Set1).

delete(X, Set = #oa_set{capacity = Cap, buckets = Buckets, size = Size}) ->
    H = hash(X),
    case find_position_to_delete(X, H, Buckets, Cap, 0) of
        not_found ->
            Set;
        {found, Pos} ->
            NewBuckets = setelement(Pos + 1, Buckets, tombstone),
            Set#oa_set{size = Size - 1, buckets = NewBuckets}
    end.

%%--------------------------------------------------------------------
%% Свёртки, map, filter
%%--------------------------------------------------------------------

foldl(Fun, Acc0, #oa_set{capacity = Cap, buckets = Buckets}) ->
    fold_buckets_left(Fun, Acc0, Buckets, Cap, 0).

foldr(Fun, Acc0, Set) ->
    %% Правую свёртку сделаем через списковое представление
    List = to_list(Set),
    lists:foldr(Fun, Acc0, List).

filter(Pred, Set) ->
    foldl(
      fun(X, Acc) ->
          case Pred(X) of
              true  -> insert(X, Acc);
              false -> Acc
          end
      end,
      new(),
      Set).

map(Fun, Set) ->
    %% результат тоже множество – возможны коллизии по значению
    foldl(
      fun(X, Acc) ->
          insert(Fun(X), Acc)
      end,
      new(),
      Set).

%%--------------------------------------------------------------------
%% Моноид (по операции объединения)
%%--------------------------------------------------------------------

union(A, B) ->
    %% можно и наоборот – вставлять меньший в больший
    foldl(fun insert/2, B, A).

%% пустое множество – нейтральный элемент
%%   union(empty(), S) == S
%%   union(S, empty()) == S

%%--------------------------------------------------------------------
%% Сравнение множеств (эффективно, без сортировки списков)
%%--------------------------------------------------------------------

equal(A, B) ->
    case {size(A), size(B)} of
        {SA, SB} when SA =/= SB ->
            false;
        {0, 0} ->
            true;
        {SA, SB} ->
            %% Идём по меньшему множеству и проверяем member в другом
            case SA =< SB of
                true  -> subset_via_fold(A, B);
                false -> subset_via_fold(B, A)
            end
    end.

subset_via_fold(Small, Big) ->
    foldl(
      fun(X, Acc) ->
          Acc andalso member(X, Big)
      end,
      true,
      Small).

%%--------------------------------------------------------------------
%% Вспомогательные функции
%%--------------------------------------------------------------------

empty_tuple(N) ->
    list_to_tuple(lists:duplicate(N, empty)).

hash(X) ->
    erlang:phash2(X).

%% Увеличение таблицы при достижении load factor (примерно 0.7)
ensure_capacity(Set = #oa_set{size = Size, capacity = Cap}) ->
    %% Size / Cap >= 0.7  <=>  Size * 10 >= 7 * Cap
    case Size * 10 >= 7 * Cap of
        true  -> resize(Set);
        false -> Set
    end.

resize(Set = #oa_set{capacity = OldCap}) ->
    NewCap = OldCap bsl 1,
    Empty  = empty_tuple(NewCap),
    %% Перевставляем все элементы
    NewSet0 = #oa_set{size = 0, capacity = NewCap, buckets = Empty},
    foldl(fun insert_no_resize/2, NewSet0, Set).

%% Вставка без проверки и без изменения capacity (используется в resize/1)
insert_no_resize(X, Set = #oa_set{capacity = Cap, buckets = Buckets, size = Size}) ->
    H = hash(X),
    case find_slot_for_insert(X, H, Buckets, Cap, 0, none) of
        {found, _Pos} ->
            %% элемент уже есть
            Set;
        {free, Pos} ->
            NewBuckets = setelement(Pos + 1, Buckets, {X, H}),
            Set#oa_set{size = Size + 1, buckets = NewBuckets}
    end.

%% Поиск слота для вставки:
%%   - если нашли такой же элемент -> {found, Pos}
%%   - если нашли пустой/надгробие -> {free, Pos}
find_slot_for_insert(X, H, Buckets, Cap, Step, TombstonePos) when Step >= Cap ->
    %% таблица полна – теоретически не должно случаться из-за ensure_capacity/1
    case TombstonePos of
        none -> {free, (H band (Cap - 1))}; % fallback
        Pos  -> {free, Pos}
    end;
find_slot_for_insert(X, H, Buckets, Cap, Step, TombstonePos) ->
    Pos = (H + Step) band (Cap - 1),
    Cell = element(Pos + 1, Buckets),
    case Cell of
        empty ->
            case TombstonePos of
                none -> {free, Pos};
                Pos0 -> {free, Pos0}
            end;
        tombstone ->
            NewTombstonePos =
                case TombstonePos of
                    none -> Pos;
                    _    -> TombstonePos
                end,
            find_slot_for_insert(X, H, Buckets, Cap, Step + 1, NewTombstonePos);
        {Y, H2} ->
            case H2 =:= H andalso Y =:= X of
                true  -> {found, Pos};
                false -> find_slot_for_insert(X, H, Buckets, Cap, Step + 1, TombstonePos)
            end
    end.

%% Поиск ячейки для member/2
probe_member(_X, _H, _Buckets, Cap, Step) when Step >= Cap ->
    false;
probe_member(X, H, Buckets, Cap, Step) ->
    Pos  = (H + Step) band (Cap - 1),
    Cell = element(Pos + 1, Buckets),
    case Cell of
        empty ->
            false;            % дальше можно не искать
        tombstone ->
            probe_member(X, H, Buckets, Cap, Step + 1);
        {Y, H2} ->
            case H2 =:= H andalso Y =:= X of
                true  -> true;
                false -> probe_member(X, H, Buckets, Cap, Step + 1)
            end
    end.

%% Поиск позиции для delete/2
find_position_to_delete(_X, _H, _Buckets, Cap, Step) when Step >= Cap ->
    not_found;
find_position_to_delete(X, H, Buckets, Cap, Step) ->
    Pos  = (H + Step) band (Cap - 1),
    Cell = element(Pos + 1, Buckets),
    case Cell of
        empty ->
            not_found;
        tombstone ->
            find_position_to_delete(X, H, Buckets, Cap, Step + 1);
        {Y, H2} ->
            case H2 =:= H andalso Y =:= X of
                true  -> {found, Pos};
                false -> find_position_to_delete(X, H, Buckets, Cap, Step + 1)
            end
    end.

%% Свёртка по всем непустым ячейкам
fold_buckets_left(Fun, Acc0, Buckets, Cap, Pos) when Pos >= Cap ->
    Acc0;
fold_buckets_left(Fun, Acc0, Buckets, Cap, Pos) ->
    Cell = element(Pos + 1, Buckets),
    Acc1 =
        case Cell of
            {X, _H} -> Fun(X, Acc0);
            _       -> Acc0
        end,
    fold_buckets_left(Fun, Acc1, Buckets, Cap, Pos + 1).

%% Внутренний to_list/1 – только для удобства реализации foldr/3 и resize/1
to_list(Set) ->
    foldl(fun(X, Acc) -> [X | Acc] end, [], Set).
