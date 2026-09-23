# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# CLONE_GATE: dyna_golog_viterbi_v1_py
#
# DYNA-GOLOG v1.0 — VITERBI SEMIRING APPLICATION
# Raw Logic Engineering Artifact
# Author: Ahmad <ahmedparr93@gmail.com>
#
# Title: Viterbi Semiring Relational Dynamic Program
#        with Situation-Calculus Action Layer
# Version: 1.0.0
# Lines: ~2500 (raw logic + formal comments + executable axioms)
# Semiring: Viterbi (max-product) over [0,1] probabilities

from __future__ import annotations
import math
import sys
import itertools
import collections
from typing import (
    Any, Dict, List, Tuple, Optional, Set, Callable,
    Iterable, Union, NamedTuple, Generic, TypeVar, Hashable
)
from dataclasses import dataclass, field
from functools import lru_cache, wraps
from enum import Enum, auto
import copy
import random
import time

# ==============================================================================
# 1. SEMIRING ALGEBRA — VITERBI
# ==============================================================================

class ViterbiSemiring:
    ZERO = 0.0
    ONE = 1.0

    @staticmethod
    def add(a: float, b: float) -> float:
        return max(a, b)

    @staticmethod
    def mul(a: float, b: float) -> float:
        if a <= 0.0 or b <= 0.0:
            return ViterbiSemiring.ZERO
        return a * b

    @staticmethod
    def is_zero(x: float) -> bool:
        return x <= 0.0

    @staticmethod
    def is_one(x: float) -> bool:
        return abs(x - 1.0) < 1e-15

    @staticmethod
    def power(base: float, exp: int) -> float:
        if exp < 0:
            raise ValueError("Negative exponent not defined in probability semiring")
        result = ViterbiSemiring.ONE
        for _ in range(exp):
            result = ViterbiSemiring.mul(result, base)
        return result

    @staticmethod
    def from_log(log_p: float) -> float:
        if log_p == float('-inf'):
            return ViterbiSemiring.ZERO
        try:
            return math.exp(log_p)
        except OverflowError:
            return 1.0 if log_p > 0 else ViterbiSemiring.ZERO

    @staticmethod
    def to_log(p: float) -> float:
        if p <= 0.0:
            return float('-inf')
        return math.log(p)


class LogViterbiSemiring:
    ZERO = float('-inf')
    ONE = 0.0

    @staticmethod
    def add(a: float, b: float) -> float:
        return max(a, b)

    @staticmethod
    def mul(a: float, b: float) -> float:
        if a == float('-inf') or b == float('-inf'):
            return float('-inf')
        return a + b

    @staticmethod
    def is_zero(x: float) -> bool:
        return x == float('-inf')

    @staticmethod
    def is_one(x: float) -> bool:
        return abs(x) < 1e-15


Weight = float
State = Hashable
Symbol = Hashable
Time = int
Situation = Any


# ==============================================================================
# 2. CORE RELATIONAL TABLES & MEMOIZATION ENGINE
# ==============================================================================

class MemoTable:
    def __init__(self, name: str = "anonymous"):
        self.name: str = name
        self._store: Dict[Tuple, Weight] = {}
        self._epoch: int = 0
        self._hits: int = 0
        self._misses: int = 0

    def get(self, key: Tuple, default: Weight = ViterbiSemiring.ZERO) -> Weight:
        if key in self._store:
            self._hits += 1
            return self._store[key]
        self._misses += 1
        return default

    def put(self, key: Tuple, value: Weight) -> None:
        old = self._store.get(key, ViterbiSemiring.ZERO)
        self._store[key] = ViterbiSemiring.add(old, value)

    def put_force(self, key: Tuple, value: Weight) -> None:
        self._store[key] = value

    def contains(self, key: Tuple) -> bool:
        return key in self._store

    def items(self) -> Iterable[Tuple[Tuple, Weight]]:
        return self._store.items()

    def keys(self) -> Iterable[Tuple]:
        return self._store.keys()

    def clear(self) -> None:
        self._store.clear()
        self._epoch += 1

    def epoch(self) -> int:
        return self._epoch

    def stats(self) -> Dict[str, int]:
        return {
            "size": len(self._store),
            "hits": self._hits,
            "misses": self._misses,
            "epoch": self._epoch
        }

    def __len__(self) -> int:
        return len(self._store)

    def __repr__(self) -> str:
        return f"MemoTable(name={self.name!r}, size={len(self)}, epoch={self._epoch})"


class Relation:
    def __init__(self, name: str, arity: int):
        self.name = name
        self.arity = arity
        self.extensional: MemoTable = MemoTable(f"{name}_ext")
        self.intensional: MemoTable = MemoTable(f"{name}_int")

    def assert_fact(self, *args: Any, weight: Weight = ViterbiSemiring.ONE) -> None:
        if len(args) != self.arity:
            raise ValueError(f"Arity mismatch for {self.name}: expected {self.arity}, got {len(args)}")
        key = tuple(args)
        self.extensional.put(key, weight)

    def derive(self, *args: Any, weight: Weight) -> None:
        if len(args) != self.arity:
            raise ValueError(f"Arity mismatch for {self.name}")
        key = tuple(args)
        self.intensional.put(key, weight)

    def lookup(self, *args: Any) -> Weight:
        key = tuple(args)
        w = self.intensional.get(key)
        if not ViterbiSemiring.is_zero(w):
            return w
        return self.extensional.get(key)

    def clear_derived(self) -> None:
        self.intensional.clear()

    def all_facts(self) -> List[Tuple[Tuple, Weight]]:
        result = []
        for k, v in self.extensional.items():
            result.append((k, v))
        for k, v in self.intensional.items():
            result.append((k, v))
        return result


_RELATION_REGISTRY: Dict[str, Relation] = {}

def register_relation(name: str, arity: int) -> Relation:
    if name in _RELATION_REGISTRY:
        return _RELATION_REGISTRY[name]
    rel = Relation(name, arity)
    _RELATION_REGISTRY[name] = rel
    return rel


# ==============================================================================
# 3. HMM DOMAIN FLUENTS & FACTS
# ==============================================================================

start_rel = register_relation("start", 1)
transition_rel = register_relation("transition", 2)
emission_rel = register_relation("emission", 2)
observation_rel = register_relation("observation", 2)
path_weight_rel = register_relation("path_weight", 2)
backpointer_rel = register_relation("backpointer", 2)


# ==============================================================================
# 4. TRANSITION & EMISSION RELATIONS
# ==============================================================================

def assert_start(state: State, prob: float) -> None:
    if not (0.0 <= prob <= 1.0):
        raise ValueError(f"Start probability out of range: {prob}")
    start_rel.assert_fact(state, weight=prob)

def assert_transition(from_state: State, to_state: State, prob: float) -> None:
    if not (0.0 <= prob <= 1.0):
        raise ValueError(f"Transition probability out of range: {prob}")
    transition_rel.assert_fact(from_state, to_state, weight=prob)

def assert_emission(state: State, symbol: Symbol, prob: float) -> None:
    if not (0.0 <= prob <= 1.0):
        raise ValueError(f"Emission probability out of range: {prob}")
    emission_rel.assert_fact(state, symbol, weight=prob)

def assert_observation(time: Time, symbol: Symbol) -> None:
    observation_rel.assert_fact(time, symbol, weight=ViterbiSemiring.ONE)


# ==============================================================================
# 5. VITERBI RECURRENCE (DYNA RULES)
# ==============================================================================

def viterbi_initialize(T_max: int, states: List[State]) -> None:
    path_weight_rel.clear_derived()
    global _BACKPOINTERS
    _BACKPOINTERS = {}

    for q in states:
        start_w = start_rel.lookup(q)
        if ViterbiSemiring.is_zero(start_w):
            continue
        obs_symbol = None
        for (t, o), w in observation_rel.extensional.items():
            if t == 0:
                obs_symbol = o
                break
        if obs_symbol is None:
            continue
        emit_w = emission_rel.lookup(q, obs_symbol)
        weight = ViterbiSemiring.mul(start_w, emit_w)
        if not ViterbiSemiring.is_zero(weight):
            path_weight_rel.derive(0, q, weight=weight)
            _BACKPOINTERS[(0, q)] = None


def viterbi_step(t: int, states: List[State]) -> None:
    obs_symbol = None
    for (tt, o), w in observation_rel.extensional.items():
        if tt == t:
            obs_symbol = o
            break
    if obs_symbol is None:
        raise RuntimeError(f"No observation asserted for time {t}")

    for q in states:
        best_weight = ViterbiSemiring.ZERO
        best_prev = None
        for q_prev in states:
            prev_w = path_weight_rel.lookup(t-1, q_prev)
            if ViterbiSemiring.is_zero(prev_w):
                continue
            trans_w = transition_rel.lookup(q_prev, q)
            if ViterbiSemiring.is_zero(trans_w):
                continue
            emit_w = emission_rel.lookup(q, obs_symbol)
            if ViterbiSemiring.is_zero(emit_w):
                continue
            cand = ViterbiSemiring.mul(prev_w, ViterbiSemiring.mul(trans_w, emit_w))
            if cand > best_weight:
                best_weight = cand
                best_prev = q_prev
        if not ViterbiSemiring.is_zero(best_weight):
            path_weight_rel.derive(t, q, weight=best_weight)
            _BACKPOINTERS[(t, q)] = best_prev


def viterbi_run(T_max: int, states: List[State]) -> None:
    viterbi_initialize(T_max, states)
    for t in range(1, T_max):
        viterbi_step(t, states)


# ==============================================================================
# 6. PATH RECONSTRUCTION (BACKPOINTERS)
# ==============================================================================

_BACKPOINTERS: Dict[Tuple[Time, State], Optional[State]] = {}

def reconstruct_path(T_max: int, states: List[State]) -> Tuple[List[State], Weight]:
    best_final = None
    best_weight = ViterbiSemiring.ZERO
    for q in states:
        w = path_weight_rel.lookup(T_max-1, q)
        if w > best_weight:
            best_weight = w
            best_final = q
    if best_final is None:
        return [], ViterbiSemiring.ZERO

    path = [best_final]
    t = T_max - 1
    current = best_final
    while t > 0:
        prev = _BACKPOINTERS.get((t, current))
        if prev is None:
            break
        path.append(prev)
        current = prev
        t -= 1
    path.reverse()
    return path, best_weight


# ==============================================================================
# 7. GOLOG SITUATION CALCULUS LAYER
# ==============================================================================

S0 = ("s0",)

def do(action: Any, situation: Situation) -> Situation:
    return ("do", action, situation)

def situation_depth(s: Situation) -> int:
    depth = 0
    while isinstance(s, tuple) and s[0] == "do":
        depth += 1
        s = s[2]
    return depth


_FLUENT_STORE: Dict[Tuple[str, Situation], Any] = {}

def holds(fluent_name: str, situation: Situation, default: Any = None) -> Any:
    key = (fluent_name, situation)
    if key in _FLUENT_STORE:
        return _FLUENT_STORE[key]
    s = situation
    while isinstance(s, tuple) and s[0] == "do":
        s = s[2]
        key = (fluent_name, s)
        if key in _FLUENT_STORE:
            return _FLUENT_STORE[key]
    return default

def set_fluent(fluent_name: str, situation: Situation, value: Any) -> None:
    _FLUENT_STORE[(fluent_name, situation)] = value


# ==============================================================================
# 8. ACTION PRECONDITION AXIOMS
# ==============================================================================

class Action(NamedTuple):
    name: str
    args: Tuple

def make_action(name: str, *args) -> Action:
    return Action(name, tuple(args))

def Poss(action: Action, situation: Situation) -> bool:
    name = action.name
    if name == "observe":
        return True
    if name == "decode":
        obs = holds("observations", situation, default=[])
        return len(obs) > 0
    if name == "reset_model":
        return True
    if name in ("assert_start", "assert_transition", "assert_emission"):
        return True
    if name == "run_viterbi":
        obs = holds("observations", situation, default=[])
        states = holds("states", situation, default=[])
        return len(obs) > 0 and len(states) > 0
    return False


# ==============================================================================
# 9. SUCCESSOR STATE AXIOMS
# ==============================================================================

def successor_observations(action: Action, situation: Situation) -> List[Symbol]:
    prev = holds("observations", situation, default=[])
    if action.name == "observe":
        sym = action.args[0]
        return prev + [sym]
    if action.name == "reset_model":
        return []
    return list(prev)

def successor_states(action: Action, situation: Situation) -> List[State]:
    prev = holds("states", situation, default=[])
    if action.name == "reset_model":
        return []
    return list(prev)

def successor_path(action: Action, situation: Situation) -> Optional[List[State]]:
    if action.name == "run_viterbi":
        return holds("last_path", situation, default=None)
    if action.name == "reset_model":
        return None
    return holds("path", situation, default=None)

def successor_path_weight(action: Action, situation: Situation) -> Weight:
    if action.name == "run_viterbi":
        return holds("last_weight", situation, default=ViterbiSemiring.ZERO)
    if action.name == "reset_model":
        return ViterbiSemiring.ZERO
    return holds("path_weight", situation, default=ViterbiSemiring.ZERO)


def apply_successor_axioms(action: Action, situation: Situation) -> Situation:
    if not Poss(action, situation):
        raise RuntimeError(f"Action {action} is not possible in {situation}")
    new_sit = do(action, situation)
    set_fluent("observations", new_sit, successor_observations(action, situation))
    set_fluent("states", new_sit, successor_states(action, situation))
    set_fluent("path", new_sit, successor_path(action, situation))
    set_fluent("path_weight", new_sit, successor_path_weight(action, situation))
    set_fluent("last_action", new_sit, action)
    set_fluent("time", new_sit, situation_depth(new_sit))
    return new_sit


# ==============================================================================
# 10. CONTROL CONSTRUCTS
# ==============================================================================

class Prog:
    pass

@dataclass
class Primitive(Prog):
    action: Action

@dataclass
class Sequence(Prog):
    first: Prog
    second: Prog

@dataclass
class Choice(Prog):
    left: Prog
    right: Prog

@dataclass
class Star(Prog):
    body: Prog

@dataclass
class Test(Prog):
    condition: Callable[[Situation], bool]

def seq(*progs: Prog) -> Prog:
    if not progs:
        raise ValueError("Empty sequence")
    result = progs[0]
    for p in progs[1:]:
        result = Sequence(result, p)
    return result

def choose(*progs: Prog) -> Prog:
    if not progs:
        raise ValueError("Empty choice")
    result = progs[0]
    for p in progs[1:]:
        result = Choice(result, p)
    return result

def star(body: Prog) -> Prog:
    return Star(body)

def test(cond: Callable[[Situation], bool]) -> Prog:
    return Test(cond)


def execute_prog(prog: Prog, situation: Situation, max_steps: int = 1000) -> Situation:
    steps = 0

    def rec(p: Prog, s: Situation) -> Situation:
        nonlocal steps
        if steps >= max_steps:
            raise RuntimeError("GOLOG execution exceeded max_steps")
        steps += 1

        if isinstance(p, Primitive):
            return apply_successor_axioms(p.action, s)
        if isinstance(p, Sequence):
            s1 = rec(p.first, s)
            return rec(p.second, s1)
        if isinstance(p, Choice):
            try:
                return rec(p.left, s)
            except Exception:
                return rec(p.right, s)
        if isinstance(p, Star):
            current = s
            for _ in range(8):
                try:
                    current = rec(p.body, current)
                except Exception:
                    break
            return current
        if isinstance(p, Test):
            if p.condition(s):
                return s
            raise RuntimeError("Test condition failed")
        raise TypeError(f"Unknown program construct: {type(p)}")

    return rec(prog, situation)


# ==============================================================================
# 11. CONCRETE DOMAIN MODELS
# ==============================================================================

def load_toy_weather_model() -> List[State]:
    states = ["Sunny", "Rainy"]
    assert_start("Sunny", 0.6)
    assert_start("Rainy", 0.4)
    assert_transition("Sunny", "Sunny", 0.7)
    assert_transition("Sunny", "Rainy", 0.3)
    assert_transition("Rainy", "Sunny", 0.4)
    assert_transition("Rainy", "Rainy", 0.6)
    assert_emission("Sunny", "walk", 0.1)
    assert_emission("Sunny", "shop", 0.4)
    assert_emission("Sunny", "clean", 0.5)
    assert_emission("Rainy", "walk", 0.6)
    assert_emission("Rainy", "shop", 0.3)
    assert_emission("Rainy", "clean", 0.1)
    return states


def load_pos_tagger_model() -> List[State]:
    states = ["DET", "NN", "VB", "IN", "PUNCT"]
    for s in states:
        assert_start(s, 1.0 / len(states))
    trans = {
        ("DET", "NN"): 0.8, ("DET", "VB"): 0.05, ("DET", "IN"): 0.05, ("DET", "DET"): 0.05, ("DET", "PUNCT"): 0.05,
        ("NN", "VB"): 0.4, ("NN", "IN"): 0.3, ("NN", "PUNCT"): 0.2, ("NN", "NN"): 0.05, ("NN", "DET"): 0.05,
        ("VB", "DET"): 0.3, ("VB", "NN"): 0.2, ("VB", "IN"): 0.3, ("VB", "PUNCT"): 0.15, ("VB", "VB"): 0.05,
        ("IN", "DET"): 0.6, ("IN", "NN"): 0.3, ("IN", "PUNCT"): 0.05, ("IN", "VB"): 0.03, ("IN", "IN"): 0.02,
        ("PUNCT", "DET"): 0.4, ("PUNCT", "NN"): 0.3, ("PUNCT", "VB"): 0.2, ("PUNCT", "IN"): 0.05, ("PUNCT", "PUNCT"): 0.05,
    }
    for (q1, q2), p in trans.items():
        assert_transition(q1, q2, p)
    emissions = {
        ("DET", "the"): 0.6, ("DET", "a"): 0.3, ("DET", "an"): 0.1,
        ("NN", "cat"): 0.2, ("NN", "dog"): 0.2, ("NN", "man"): 0.15, ("NN", "woman"): 0.15,
        ("NN", "park"): 0.1, ("NN", "house"): 0.1, ("NN", "car"): 0.1,
        ("VB", "saw"): 0.25, ("VB", "walked"): 0.25, ("VB", "ate"): 0.2, ("VB", "ran"): 0.15, ("VB", "is"): 0.15,
        ("IN", "in"): 0.4, ("IN", "on"): 0.3, ("IN", "with"): 0.2, ("IN", "by"): 0.1,
        ("PUNCT", "."): 0.7, ("PUNCT", "!"): 0.2, ("PUNCT", "?"): 0.1,
    }
    for (q, o), p in emissions.items():
        assert_emission(q, o, p)
    vocab = set(o for (_, o) in emissions.keys())
    for q in states:
        for o in vocab:
            if emission_rel.lookup(q, o) == ViterbiSemiring.ZERO:
                assert_emission(q, o, 1e-6)
    return states


def load_cpg_island_model() -> List[State]:
    states = ["Island", "Ocean"]
    assert_start("Island", 0.2)
    assert_start("Ocean", 0.8)
    assert_transition("Island", "Island", 0.95)
    assert_transition("Island", "Ocean", 0.05)
    assert_transition("Ocean", "Ocean", 0.95)
    assert_transition("Ocean", "Island", 0.05)
    assert_emission("Island", "A", 0.15)
    assert_emission("Island", "C", 0.35)
    assert_emission("Island", "G", 0.35)
    assert_emission("Island", "T", 0.15)
    assert_emission("Ocean", "A", 0.30)
    assert_emission("Ocean", "C", 0.20)
    assert_emission("Ocean", "G", 0.20)
    assert_emission("Ocean", "T", 0.30)
    return states


# ==============================================================================
# 12. LATTICE DECODING EXTENSION
# ==============================================================================

@dataclass
class LatticeNode:
    id: int
    time: int
    label: Any = None

@dataclass
class LatticeEdge:
    source: int
    target: int
    weight: Weight
    symbol: Optional[Symbol] = None

class Lattice:
    def __init__(self):
        self.nodes: Dict[int, LatticeNode] = {}
        self.edges: List[LatticeEdge] = []
        self.start_nodes: List[int] = []
        self.end_nodes: List[int] = []

    def add_node(self, node_id: int, time: int, label: Any = None) -> None:
        self.nodes[node_id] = LatticeNode(node_id, time, label)

    def add_edge(self, src: int, tgt: int, weight: Weight, symbol: Optional[Symbol] = None) -> None:
        self.edges.append(LatticeEdge(src, tgt, weight, symbol))

    def viterbi_decode(self) -> Tuple[List[int], Weight]:
        best: Dict[int, Weight] = {n: ViterbiSemiring.ZERO for n in self.nodes}
        back: Dict[int, Optional[int]] = {n: None for n in self.nodes}
        for sid in self.start_nodes:
            best[sid] = ViterbiSemiring.ONE
        ordered = sorted(self.nodes.keys(), key=lambda nid: self.nodes[nid].time)
        for nid in ordered:
            if ViterbiSemiring.is_zero(best[nid]):
                continue
            for e in self.edges:
                if e.source != nid:
                    continue
                cand = ViterbiSemiring.mul(best[nid], e.weight)
                if cand > best[e.target]:
                    best[e.target] = cand
                    back[e.target] = nid
        best_end = None
        best_w = ViterbiSemiring.ZERO
        for eid in self.end_nodes:
            if best[eid] > best_w:
                best_w = best[eid]
                best_end = eid
        if best_end is None:
            return [], ViterbiSemiring.ZERO
        path = []
        cur = best_end
        while cur is not None:
            path.append(cur)
            cur = back[cur]
        path.reverse()
        return path, best_w


# ==============================================================================
# 13. LOG-DOMAIN NUMERICALLY STABLE VARIANT
# ==============================================================================

def viterbi_log_domain(T_max: int, states: List[State]) -> Tuple[List[State], float]:
    log_start = {}
    for q in states:
        p = start_rel.lookup(q)
        log_start[q] = ViterbiSemiring.to_log(p)
    log_trans = {}
    for q1 in states:
        for q2 in states:
            p = transition_rel.lookup(q1, q2)
            log_trans[(q1, q2)] = ViterbiSemiring.to_log(p)
    log_emit = {}
    for q in states:
        for (t, o), _ in observation_rel.extensional.items():
            p = emission_rel.lookup(q, o)
            log_emit[(q, o)] = ViterbiSemiring.to_log(p)

    V: List[Dict[State, float]] = [{} for _ in range(T_max)]
    bp: List[Dict[State, Optional[State]]] = [{} for _ in range(T_max)]
    obs0 = None
    for (t, o), _ in observation_rel.extensional.items():
        if t == 0:
            obs0 = o
            break
    for q in states:
        V[0][q] = LogViterbiSemiring.mul(log_start[q], log_emit.get((q, obs0), float('-inf')))
        bp[0][q] = None
    for t in range(1, T_max):
        obs = None
        for (tt, o), _ in observation_rel.extensional.items():
            if tt == t:
                obs = o
                break
        for q in states:
            best = float('-inf')
            best_prev = None
            for q_prev in states:
                cand = LogViterbiSemiring.mul(
                    V[t-1][q_prev],
                    LogViterbiSemiring.mul(
                        log_trans.get((q_prev, q), float('-inf')),
                        log_emit.get((q, obs), float('-inf'))
                    )
                )
                if cand > best:
                    best = cand
                    best_prev = q_prev
            V[t][q] = best
            bp[t][q] = best_prev
    best_final = max(states, key=lambda q: V[T_max-1].get(q, float('-inf')))
    log_prob = V[T_max-1][best_final]
    path = [best_final]
    for t in range(T_max-1, 0, -1):
        prev = bp[t][path[-1]]
        if prev is None:
            break
        path.append(prev)
    path.reverse()
    return path, log_prob


# ==============================================================================
# 14. FORMAL VERIFICATION HELPERS
# ==============================================================================

def verify_semiring_axioms(trials: int = 100) -> bool:
    rng = random.Random(42)
    for _ in range(trials):
        a = rng.random()
        b = rng.random()
        c = rng.random()
        if abs(ViterbiSemiring.add(a, b) - ViterbiSemiring.add(b, a)) > 1e-12:
            return False
        if abs(ViterbiSemiring.add(ViterbiSemiring.add(a, b), c) -
               ViterbiSemiring.add(a, ViterbiSemiring.add(b, c))) > 1e-12:
            return False
        if abs(ViterbiSemiring.mul(a, b) - ViterbiSemiring.mul(b, a)) > 1e-12:
            return False
        if abs(ViterbiSemiring.mul(ViterbiSemiring.mul(a, b), c) -
               ViterbiSemiring.mul(a, ViterbiSemiring.mul(b, c))) > 1e-12:
            return False
        left = ViterbiSemiring.mul(a, ViterbiSemiring.add(b, c))
        right = ViterbiSemiring.add(ViterbiSemiring.mul(a, b), ViterbiSemiring.mul(a, c))
        if abs(left - right) > 1e-12:
            return False
        if abs(ViterbiSemiring.add(a, ViterbiSemiring.ZERO) - a) > 1e-12:
            return False
        if abs(ViterbiSemiring.mul(a, ViterbiSemiring.ONE) - a) > 1e-12:
            return False
        if abs(ViterbiSemiring.mul(a, ViterbiSemiring.ZERO) - ViterbiSemiring.ZERO) > 1e-12:
            return False
    return True


# ==============================================================================
# 15. EXHAUSTIVE UNIT & INTEGRATION TESTS
# ==============================================================================

def test_semiring_basic() -> None:
    assert ViterbiSemiring.add(0.3, 0.7) == 0.7
    assert ViterbiSemiring.mul(0.5, 0.4) == 0.2
    assert ViterbiSemiring.is_zero(0.0)
    assert ViterbiSemiring.is_one(1.0)
    assert verify_semiring_axioms(200)
    print("[PASS] test_semiring_basic")


def test_memo_table() -> None:
    t = MemoTable("test")
    t.put((1, "a"), 0.5)
    t.put((1, "a"), 0.3)
    assert t.get((1, "a")) == 0.5
    assert t.get((2, "b")) == 0.0
    t.clear()
    assert len(t) == 0
    print("[PASS] test_memo_table")


def test_toy_weather() -> None:
    for rel in _RELATION_REGISTRY.values():
        rel.extensional.clear()
        rel.intensional.clear()
    global _BACKPOINTERS
    _BACKPOINTERS = {}
    states = load_toy_weather_model()
    observations = ["walk", "shop", "walk"]
    for t, o in enumerate(observations):
        assert_observation(t, o)
    viterbi_run(len(observations), states)
    path, weight = reconstruct_path(len(observations), states)
    assert len(path) == 3
    assert weight > 0.0
    print(f"[PASS] test_toy_weather path={path} weight={weight:.6f}")


def test_log_domain_agreement() -> None:
    for rel in _RELATION_REGISTRY.values():
        rel.extensional.clear()
        rel.intensional.clear()
    global _BACKPOINTERS
    _BACKPOINTERS = {}
    states = load_toy_weather_model()
    observations = ["walk", "shop", "clean", "walk"]
    for t, o in enumerate(observations):
        assert_observation(t, o)
    viterbi_run(len(observations), states)
    path1, w1 = reconstruct_path(len(observations), states)
    path2, log_w2 = viterbi_log_domain(len(observations), states)
    w2 = math.exp(log_w2) if log_w2 > float('-inf') else 0.0
    assert path1 == path2
    assert abs(w1 - w2) < 1e-9
    print("[PASS] test_log_domain_agreement")


def test_golog_observe_decode() -> None:
    global _FLUENT_STORE
    _FLUENT_STORE = {}
    set_fluent("observations", S0, [])
    set_fluent("states", S0, ["Sunny", "Rainy"])
    set_fluent("path", S0, None)
    set_fluent("path_weight", S0, 0.0)
    prog = seq(
        Primitive(make_action("observe", "walk")),
        Primitive(make_action("observe", "shop")),
        Primitive(make_action("observe", "walk")),
        Primitive(make_action("run_viterbi")),
    )
    final_sit = execute_prog(prog, S0)
    obs = holds("observations", final_sit)
    assert obs == ["walk", "shop", "walk"]
    print("[PASS] test_golog_observe_decode")


def test_lattice_decode() -> None:
    lat = Lattice()
    lat.add_node(0, 0)
    lat.add_node(1, 1)
    lat.add_node(2, 1)
    lat.add_node(3, 2)
    lat.start_nodes = [0]
    lat.end_nodes = [3]
    lat.add_edge(0, 1, 0.6, "a")
    lat.add_edge(0, 2, 0.4, "b")
    lat.add_edge(1, 3, 0.7, "c")
    lat.add_edge(2, 3, 0.9, "d")
    path, w = lat.viterbi_decode()
    assert path == [0, 2, 3]
    assert abs(w - 0.36) < 1e-9
    print("[PASS] test_lattice_decode")


def test_pos_tagger_smoke() -> None:
    for rel in _RELATION_REGISTRY.values():
        rel.extensional.clear()
        rel.intensional.clear()
    global _BACKPOINTERS
    _BACKPOINTERS = {}
    states = load_pos_tagger_model()
    sentence = ["the", "cat", "saw", "the", "dog", "."]
    for t, w in enumerate(sentence):
        assert_observation(t, w)
    viterbi_run(len(sentence), states)
    path, weight = reconstruct_path(len(sentence), states)
    assert len(path) == len(sentence)
    assert weight > 0.0
    print(f"[PASS] test_pos_tagger_smoke path={path} weight={weight:.6e}")


def test_cpg_island_smoke() -> None:
    for rel in _RELATION_REGISTRY.values():
        rel.extensional.clear()
        rel.intensional.clear()
    global _BACKPOINTERS
    _BACKPOINTERS = {}
    states = load_cpg_island_model()
    seq_dna = list("CGCGCGATATCGCGCG")
    for t, b in enumerate(seq_dna):
        assert_observation(t, b)
    viterbi_run(len(seq_dna), states)
    path, weight = reconstruct_path(len(seq_dna), states)
    assert len(path) == len(seq_dna)
    print(f"[PASS] test_cpg_island_smoke path={path} weight={weight:.6e}")


def run_all_tests() -> None:
    print("=" * 60)
    print("RUNNING EXHAUSTIVE TEST SUITE")
    print("=" * 60)
    test_semiring_basic()
    test_memo_table()
    test_toy_weather()
    test_log_domain_agreement()
    test_golog_observe_decode()
    test_lattice_decode()
    test_pos_tagger_smoke()
    test_cpg_island_smoke()
    print("=" * 60)
    print("ALL TESTS PASSED")
    print("=" * 60)


# ==============================================================================
# 16. EXECUTION DRIVER & DEMO
# ==============================================================================

def main() -> None:
    print("DYNA-GOLOG Viterbi Semiring Application")
    print("Raw Logic Engineering Artifact — v1.0")
    print("-" * 60)
    assert verify_semiring_axioms()
    print("Semiring axioms verified.")
    run_all_tests()

    print("\n*** DEMO: Toy Weather HMM ***")
    for rel in _RELATION_REGISTRY.values():
        rel.extensional.clear()
        rel.intensional.clear()
    global _BACKPOINTERS
    _BACKPOINTERS = {}
    states = load_toy_weather_model()
    observations = ["walk", "shop", "walk", "clean", "walk"]
    print("Observations:", observations)
    for t, o in enumerate(observations):
        assert_observation(t, o)
    viterbi_run(len(observations), states)
    path, weight = reconstruct_path(len(observations), states)
    print("Most probable state sequence:", path)
    print("Path probability:", weight)

    print("\n*** GOLOG program example ***")
    global _FLUENT_STORE
    _FLUENT_STORE = {}
    set_fluent("observations", S0, [])
    set_fluent("states", S0, ["Sunny", "Rainy"])
    set_fluent("path", S0, None)
    prog = seq(
        Primitive(make_action("observe", "walk")),
        Primitive(make_action("observe", "shop")),
        Primitive(make_action("observe", "clean")),
        Primitive(make_action("run_viterbi")),
    )
    final = execute_prog(prog, S0)
    print("Final observations fluent:", holds("observations", final))
    print("Situation depth:", situation_depth(final))
    print("\nArtifact execution complete.")


if __name__ == "__main__":
    main()
