%% SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
%% CLONE_GATE: dyna_golog_viterbi
%%
%% DYNA-GOLOG v2.0 — Viterbi Semiring Application
%% Situation calculus + HMM Viterbi decoder + GOLOG control constructs.
%% Pure SWI-Prolog, no external deps.

:- module(dyna_golog_viterbi, [
    viterbi_decode/4,
    viterbi_log_decode/4,
    execute_prog/4,
    demo/0,
    run_tests/0
]).

:- use_module(library(lists)).
:- use_module(library(assoc)).
:- use_module(library(apply)).

%% ============================================================================
%% 1. VITERBI SEMIRING — (R, max, *, 0, 1) over [0,1]
%% ============================================================================

sr_add(A, B, C) :- C is max(A, B).
sr_mul(A, B, C) :-
    ( A < 0.0 ; B < 0.0 ) ->
        throw(error(negative_weight(A, B), viterbi_semiring))
    ; C is A * B.
sr_zero(0.0).
sr_one(1.0).

log_sr_add(A, B, C) :- C is max(A, B).
log_sr_mul(A, B, C) :-
    ( A =:= -1.0e308 ; B =:= -1.0e308 ) -> C = -1.0e308
    ; C is A + B.
to_log(P, L) :- ( P =< 0.0 -> L = -1.0e308 ; L is log(P) ).

%% ============================================================================
%% 2. HMM MODEL (dynamic facts)
%% ============================================================================

:- dynamic hmm_start/2, hmm_trans/3, hmm_emit/3.

assert_start(State, Prob) :-
    ( Prob < 0.0 ; Prob > 1.0 ) ->
        throw(error(invalid_prob(start, State, Prob)))
    ; assertz(hmm_start(State, Prob)).

assert_transition(From, To, Prob) :-
    ( Prob < 0.0 ; Prob > 1.0 ) ->
        throw(error(invalid_prob(transition, From-To, Prob)))
    ; assertz(hmm_trans(From, To, Prob)).

assert_emission(State, Symbol, Prob) :-
    ( Prob < 0.0 ; Prob > 1.0 ) ->
        throw(error(invalid_prob(emission, State-Symbol, Prob)))
    ; assertz(hmm_emit(State, Symbol, Prob)).

reset_model :-
    retractall(hmm_start(_, _)),
    retractall(hmm_trans(_, _, _)),
    retractall(hmm_emit(_, _, _)).

%% ============================================================================
%% 3. VITERBI ALGORITHM — probability domain
%% ============================================================================

viterbi_decode(Observations, States, Path, Weight) :-
    viterbi_init(Observations, States, Trellis0, BP0),
    Observations = [_|RestObs],
    viterbi_forward(RestObs, States, 1, Trellis0, BP0, TrellisN, BPN),
    length(Observations, T),
    TMax is T - 1,
    viterbi_best_final(States, TMax, TrellisN, BestState, Weight),
    viterbi_traceback(BestState, TMax, BPN, PathRev),
    reverse(PathRev, Path).

viterbi_init([Obs0|_], States, Trellis, BP) :-
    empty_assoc(T0), empty_assoc(BP0),
    foldl(init_state(Obs0), States, T0-BP0, Trellis-BP).

init_state(Obs0, Q, Tin-BPin, Tout-BPout) :-
    ( hmm_start(Q, StartW) -> true ; StartW = 0.0 ),
    ( hmm_emit(Q, Obs0, EmitW) -> true ; EmitW = 0.0 ),
    sr_mul(StartW, EmitW, W),
    put_assoc(0-Q, Tin, W, Tout),
    put_assoc(0-Q, BPin, none, BPout).

viterbi_forward([], _, _, T, BP, T, BP).
viterbi_forward([Obs|Rest], States, Time, Tin, BPin, Tout, BPout) :-
    foldl(step_state(Obs, Time, States, Tin), States, Tin-BPin, Tmid-BPmid),
    Time1 is Time + 1,
    viterbi_forward(Rest, States, Time1, Tmid, BPmid, Tout, BPout).

step_state(Obs, Time, States, TrellisPrev, Q, Tin-BPin, Tout-BPout) :-
    ( hmm_emit(Q, Obs, EmitW) -> true ; EmitW = 0.0 ),
    PrevTime is Time - 1,
    foldl(candidate(Q, PrevTime, EmitW, TrellisPrev), States, 0.0-none, BestW-BestPrev),
    put_assoc(Time-Q, Tin, BestW, Tout),
    put_assoc(Time-Q, BPin, BestPrev, BPout).

candidate(Q, PrevTime, EmitW, Trellis, QPrev, CurW-CurBest, NewW-NewBest) :-
    ( get_assoc(PrevTime-QPrev, Trellis, PrevW) -> true ; PrevW = 0.0 ),
    ( hmm_trans(QPrev, Q, TransW) -> true ; TransW = 0.0 ),
    sr_mul(PrevW, TransW, PW1),
    sr_mul(PW1, EmitW, CandW),
    ( CandW > CurW -> NewW = CandW, NewBest = QPrev
    ; NewW = CurW, NewBest = CurBest ).

viterbi_best_final(States, TMax, Trellis, BestState, BestW) :-
    foldl(check_final(TMax, Trellis), States, none-0.0, BestState-BestW).

check_final(TMax, Trellis, Q, CurS-CurW, NewS-NewW) :-
    ( get_assoc(TMax-Q, Trellis, W) -> true ; W = 0.0 ),
    ( W > CurW -> NewS = Q, NewW = W
    ; NewS = CurS, NewW = CurW ).

viterbi_traceback(_, 0, _, [_]) :- !.  % base: time 0, no more backpointers
viterbi_traceback(State, Time, BP, [State|Rest]) :-
    Time > 0,
    get_assoc(Time-State, BP, Prev),
    Prev \= none,
    Time1 is Time - 1,
    viterbi_traceback(Prev, Time1, BP, Rest).
viterbi_traceback(State, 0, _, [State]).

%% ============================================================================
%% 4. VITERBI — log domain (numerically stable)
%% ============================================================================

viterbi_log_decode(Observations, States, Path, LogWeight) :-
    log_init(Observations, States, V0, BP0),
    Observations = [_|RestObs],
    log_forward(RestObs, States, 1, V0, BP0, VN, BPN),
    length(Observations, T), TMax is T - 1,
    log_best_final(States, TMax, VN, BestState, LogWeight),
    viterbi_traceback(BestState, TMax, BPN, PathRev),
    reverse(PathRev, Path).

log_init([Obs0|_], States, V, BP) :-
    empty_assoc(V0), empty_assoc(BP0),
    foldl(log_init_state(Obs0), States, V0-BP0, V-BP).

log_init_state(Obs0, Q, Vin-BPin, Vout-BPout) :-
    ( hmm_start(Q, SP) -> to_log(SP, LS) ; LS = -1.0e308 ),
    ( hmm_emit(Q, Obs0, EP) -> to_log(EP, LE) ; LE = -1.0e308 ),
    log_sr_mul(LS, LE, W),
    put_assoc(0-Q, Vin, W, Vout),
    put_assoc(0-Q, BPin, none, BPout).

log_forward([], _, _, V, BP, V, BP).
log_forward([Obs|Rest], States, Time, Vin, BPin, Vout, BPout) :-
    foldl(log_step(Obs, Time, States, Vin), States, Vin-BPin, Vmid-BPmid),
    T1 is Time + 1,
    log_forward(Rest, States, T1, Vmid, BPmid, Vout, BPout).

log_step(Obs, Time, States, VPrev, Q, Vin-BPin, Vout-BPout) :-
    ( hmm_emit(Q, Obs, EP) -> to_log(EP, LE) ; LE = -1.0e308 ),
    PT is Time - 1,
    foldl(log_cand(Q, PT, LE, VPrev), States, (-1.0e308)-none, BW-BP),
    put_assoc(Time-Q, Vin, BW, Vout),
    put_assoc(Time-Q, BPin, BP, BPout).

log_cand(Q, PT, LE, VPrev, QP, CW-CB, NW-NB) :-
    ( get_assoc(PT-QP, VPrev, PW) -> true ; PW = -1.0e308 ),
    ( hmm_trans(QP, Q, TP) -> to_log(TP, LT) ; LT = -1.0e308 ),
    log_sr_mul(PW, LT, W1),
    log_sr_mul(W1, LE, CandW),
    ( CandW > CW -> NW = CandW, NB = QP
    ; NW = CW, NB = CB ).

log_best_final(States, TMax, V, Best, BestW) :-
    foldl(log_check(TMax, V), States, none-(-1.0e308), Best-BestW).

log_check(TMax, V, Q, CS-CW, NS-NW) :-
    ( get_assoc(TMax-Q, V, W) -> true ; W = -1.0e308 ),
    ( W > CW -> NS = Q, NW = W ; NS = CS, NW = CW ).

%% ============================================================================
%% 5. SITUATION CALCULUS — fluents and successor state axioms
%% ============================================================================

:- dynamic fluent/3.

s0(s0).

do(Action, S, do(Action, S)).

situation_depth(s0, 0).
situation_depth(do(_, S), D) :- situation_depth(S, D0), D is D0 + 1.

set_fluent(Name, Sit, Value) :-
    retractall(fluent(Name, Sit, _)),
    assertz(fluent(Name, Sit, Value)).

get_fluent(Name, Sit, Value) :-
    fluent(Name, Sit, Value), !.
get_fluent(Name, do(_, S), Value) :-
    !, get_fluent(Name, S, Value).
get_fluent(_, _, nil).

%% Precondition axioms
poss(observe(_), _).
poss(reset_model, _).
poss(assert_start(_, _), _).
poss(assert_transition(_, _, _), _).
poss(assert_emission(_, _, _), _).
poss(run_viterbi, S) :-
    get_fluent(observations, S, Obs), Obs \= [], Obs \= nil,
    get_fluent(states, S, States), States \= [], States \= nil.

%% Successor state axioms
apply_action(observe(O), S, S1) :-
    do(observe(O), S, S1),
    get_fluent(observations, S, Obs),
    ( Obs = nil -> NewObs = [O] ; append(Obs, [O], NewObs) ),
    set_fluent(observations, S1, NewObs).

apply_action(run_viterbi, S, S1) :-
    do(run_viterbi, S, S1),
    get_fluent(observations, S, Obs),
    get_fluent(states, S, States),
    viterbi_decode(Obs, States, Path, Weight),
    set_fluent(path, S1, Path),
    set_fluent(path_weight, S1, Weight),
    set_fluent(observations, S1, Obs),
    set_fluent(states, S1, States).

apply_action(reset_model, S, S1) :-
    do(reset_model, S, S1),
    reset_model,
    set_fluent(observations, S1, []),
    set_fluent(states, S1, []),
    set_fluent(path, S1, nil),
    set_fluent(path_weight, S1, 0.0).

%% ============================================================================
%% 6. GOLOG CONTROL CONSTRUCTS
%% ============================================================================

%% execute_prog(+Program, +SitIn, -SitOut, +Options)
execute_prog(primitive(A), S, S1, _Opts) :-
    poss(A, S),
    apply_action(A, S, S1).

execute_prog(seq(P1, P2), S, S2, Opts) :-
    execute_prog(P1, S, S1, Opts),
    execute_prog(P2, S1, S2, Opts).

execute_prog(choice(P1, _P2), S, S1, Opts) :-
    execute_prog(P1, S, S1, Opts), !.
execute_prog(choice(_P1, P2), S, S1, Opts) :-
    execute_prog(P2, S, S1, Opts).

execute_prog(test(Cond), S, S, _Opts) :-
    call(Cond, S).

execute_prog(star(Body), S, SOut, Opts) :-
    ( member(star_bound(Bound), Opts) -> true ; Bound = 16 ),
    star_loop(Body, S, SOut, Bound, Opts).

star_loop(_, S, S, 0, _) :- !.
star_loop(Body, S, SOut, N, Opts) :-
    N > 0,
    ( execute_prog(Body, S, S1, Opts) ->
        N1 is N - 1,
        star_loop(Body, S1, SOut, N1, Opts)
    ; SOut = S
    ).

%% ============================================================================
%% 7. CONCRETE DOMAIN MODELS
%% ============================================================================

load_toy_weather :-
    reset_model,
    assert_start(sunny, 0.6), assert_start(rainy, 0.4),
    assert_transition(sunny, sunny, 0.7), assert_transition(sunny, rainy, 0.3),
    assert_transition(rainy, sunny, 0.4), assert_transition(rainy, rainy, 0.6),
    assert_emission(sunny, walk, 0.1), assert_emission(sunny, shop, 0.4),
    assert_emission(sunny, clean, 0.5),
    assert_emission(rainy, walk, 0.6), assert_emission(rainy, shop, 0.3),
    assert_emission(rainy, clean, 0.1).

load_pos_tagger :-
    reset_model,
    States = [det, nn, vb, 'in', punct],
    maplist([S]>>(P is 1.0/5.0, assert_start(S, P)), States),
    Transitions = [
        det-nn-0.8, det-vb-0.05, det-'in'-0.05, det-det-0.05, det-punct-0.05,
        nn-vb-0.4, nn-'in'-0.3, nn-punct-0.2, nn-nn-0.05, nn-det-0.05,
        vb-det-0.3, vb-nn-0.2, vb-'in'-0.3, vb-punct-0.15, vb-vb-0.05,
        'in'-det-0.6, 'in'-nn-0.3, 'in'-punct-0.05, 'in'-vb-0.03, 'in'-'in'-0.02,
        punct-det-0.4, punct-nn-0.3, punct-vb-0.2, punct-'in'-0.05, punct-punct-0.05
    ],
    maplist([F-T-P]>>assert_transition(F, T, P), Transitions),
    Emissions = [
        det-the-0.6, det-a-0.3, det-an-0.1,
        nn-cat-0.2, nn-dog-0.2, nn-man-0.15, nn-woman-0.15,
        nn-park-0.1, nn-house-0.1, nn-car-0.1,
        vb-saw-0.25, vb-walked-0.25, vb-ate-0.2, vb-ran-0.15, vb-is-0.15,
        'in'-in-0.4, 'in'-on-0.3, 'in'-with-0.2, 'in'-by-0.1,
        punct-'.'-0.7, punct-'!'-0.2, punct-'?'-0.1
    ],
    maplist([S-O-P]>>assert_emission(S, O, P), Emissions).

load_cpg_island :-
    reset_model,
    assert_start(island, 0.2), assert_start(ocean, 0.8),
    assert_transition(island, island, 0.95), assert_transition(island, ocean, 0.05),
    assert_transition(ocean, ocean, 0.95), assert_transition(ocean, island, 0.05),
    assert_emission(island, 'A', 0.15), assert_emission(island, 'C', 0.35),
    assert_emission(island, 'G', 0.35), assert_emission(island, 'T', 0.15),
    assert_emission(ocean, 'A', 0.30), assert_emission(ocean, 'C', 0.20),
    assert_emission(ocean, 'G', 0.20), assert_emission(ocean, 'T', 0.30).

%% ============================================================================
%% 8. LATTICE DECODING
%% ============================================================================

:- dynamic lat_node/3, lat_edge/4, lat_start/1, lat_end/1.

lattice_decode(Path, Weight) :-
    findall(NID, lat_start(NID), Starts),
    findall(NID, lat_end(NID), Ends),
    findall(NID-Time, lat_node(NID, Time, _), Nodes),
    sort(2, @=<, Nodes, Sorted),
    empty_assoc(Best0), empty_assoc(Back0),
    foldl([NID-_,Bi-Bki,Bo-Bko]>>(
        ( member(NID, Starts) -> put_assoc(NID, Bi, 1.0, B1), put_assoc(NID, Bki, none, BK1)
        ; B1 = Bi, BK1 = Bki ),
        ( get_assoc(NID, B1, NW) ->
            findall(T-TW-TNID, (
                lat_edge(NID, T, EW, _),
                sr_mul(NW, EW, TW)
            ), Targets),
            foldl([T2-TW2-_,Bx-BKx,By-BKy]>>(
                ( get_assoc(T2, Bx, OldW) ->
                    ( TW2 > OldW -> put_assoc(T2, Bx, TW2, By), put_assoc(T2, BKx, NID, BKy)
                    ; By = Bx, BKy = BKx )
                ; put_assoc(T2, Bx, TW2, By), put_assoc(T2, BKx, NID, BKy)
                )
            ), Targets, B1-BK1, Bo-Bko)
        ; Bo = B1, Bko = BK1 )
    ), Sorted, Best0-Back0, BestN-BackN),
    foldl([EID, CS-CW, NS-NW]>>(
        ( get_assoc(EID, BestN, W), W > CW -> NS = EID, NW = W
        ; NS = CS, NW = CW )
    ), Ends, none-0.0, BestEnd-Weight),
    lattice_traceback(BestEnd, BackN, PathRev),
    reverse(PathRev, Path).

lattice_traceback(none, _, []) :- !.
lattice_traceback(Node, Back, [Node|Rest]) :-
    ( get_assoc(Node, Back, Prev), Prev \= none ->
        lattice_traceback(Prev, Back, Rest)
    ; Rest = []
    ).

%% ============================================================================
%% 9. SEMIRING VERIFICATION
%% ============================================================================

verify_semiring :-
    numlist(1, 100, Ns),
    forall(member(_, Ns), (
        P1 is random_float, P2 is random_float, P3 is random_float,
        sr_add(P1, P2, A1), sr_add(P2, P1, A2), A1 =:= A2,
        sr_mul(P1, P2, M1), sr_mul(P2, P1, M2), abs(M1 - M2) < 1.0e-12,
        sr_mul(P1, 1.0, I1), abs(I1 - P1) < 1.0e-12,
        sr_mul(P1, 0.0, Z1), Z1 =:= 0.0
    )),
    format('[PASS] verify_semiring~n').

%% ============================================================================
%% 10. TESTS
%% ============================================================================

run_tests :-
    format('~n============================================================~n'),
    format('RUNNING DYNA-GOLOG VITERBI TEST SUITE~n'),
    format('============================================================~n'),
    verify_semiring,
    test_toy_weather,
    test_log_agreement,
    test_golog_wired,
    format('============================================================~n'),
    format('ALL TESTS PASSED~n'),
    format('============================================================~n').

test_toy_weather :-
    load_toy_weather,
    viterbi_decode([walk, shop, walk], [sunny, rainy], Path, Weight),
    length(Path, 3),
    Weight > 0.0,
    format('[PASS] test_toy_weather path=~w weight=~6f~n', [Path, Weight]).

test_log_agreement :-
    load_toy_weather,
    Obs = [walk, shop, clean, walk],
    States = [sunny, rainy],
    viterbi_decode(Obs, States, Path1, W1),
    viterbi_log_decode(Obs, States, Path2, LogW2),
    W2 is exp(LogW2),
    Path1 = Path2,
    Diff is abs(W1 - W2),
    Diff < 1.0e-9,
    format('[PASS] test_log_agreement~n').

test_golog_wired :-
    load_toy_weather,
    retractall(fluent(_, _, _)),
    set_fluent(observations, s0, []),
    set_fluent(states, s0, [sunny, rainy]),
    Prog = seq(
        seq(primitive(observe(walk)),
        seq(primitive(observe(shop)),
            primitive(observe(clean)))),
        primitive(run_viterbi)
    ),
    execute_prog(Prog, s0, Final, []),
    get_fluent(path, Final, Path),
    get_fluent(path_weight, Final, Weight),
    Path \= nil, length(Path, 3), Weight > 0.0,
    format('[PASS] test_golog_wired path=~w weight=~6f~n', [Path, Weight]).

%% ============================================================================
%% 11. DEMO
%% ============================================================================

demo :-
    format('~nDYNA-GOLOG v2.0 — Viterbi Semiring (Prolog)~n'),
    format('------------------------------------------------------------~n'),

    format('~n*** Toy Weather HMM ***~n'),
    load_toy_weather,
    viterbi_decode([walk, shop, walk, clean, walk], [sunny, rainy], P1, W1),
    format('Path: ~w~nWeight: ~6f~n', [P1, W1]),

    format('~n*** POS Tagger ***~n'),
    load_pos_tagger,
    viterbi_decode([the, man, saw, a, cat, in, the, park, '.'],
                   [det, nn, vb, 'in', punct], P2, W2),
    format('Tags: ~w~nWeight: ~e~n', [P2, W2]),

    format('~n*** CpG Island ***~n'),
    load_cpg_island,
    atom_chars('TCGCGCGATCGCGCGATAATCGCGCG', DNA),
    maplist([C,A]>>atom_chars(A,[C]), DNA, Symbols),
    viterbi_decode(Symbols, [island, ocean], P3, W3),
    format('Path: ~w~nWeight: ~e~n', [P3, W3]),

    format('~n*** GOLOG Wired ***~n'),
    load_toy_weather,
    retractall(fluent(_, _, _)),
    set_fluent(observations, s0, []),
    set_fluent(states, s0, [sunny, rainy]),
    Prog = seq(
        seq(primitive(observe(walk)),
        seq(primitive(observe(shop)),
            primitive(observe(clean)))),
        primitive(run_viterbi)
    ),
    execute_prog(Prog, s0, Final, []),
    get_fluent(path, Final, FPath),
    get_fluent(path_weight, Final, FWeight),
    format('GOLOG path: ~w~nGOLOG weight: ~6f~n', [FPath, FWeight]),

    run_tests,
    format('~nArtifact complete.~n').

:- initialization(demo, main).
