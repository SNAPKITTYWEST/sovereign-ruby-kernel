#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: GPL-3.0-or-later OR Apache-2.0
# CLONE_GATE: holographic_golog_engine_py
#
# HOLOGRAPHIC GOLOG ENGINE v1.0
# DYNA-GOLOG Sovereign Reasoning Kernel — Situation Calculus Core
# Author: Ahmad <ahmedparr93@gmail.com>
#
# Complete Situation-Calculus Interpreter & Executor.
# The engine is "holographic" in the precise sense that every fluent value
# at any situation is completely determined by the situation term itself
# (the history of actions) together with the successor-state axioms.

from __future__ import annotations
import sys
import copy
import itertools
import collections
from typing import (
    Any, Dict, List, Tuple, Optional, Set, Callable,
    Iterable, Union, NamedTuple, Generic, TypeVar, Hashable, FrozenSet
)
from dataclasses import dataclass, field
from functools import lru_cache, wraps
from enum import Enum, auto
import random
import time
import math

# ==============================================================================
# 1. FOUNDATIONAL TYPES — SITUATIONS, ACTIONS, FLUENTS
# ==============================================================================

Situation = Tuple

S0: Situation = ("s0",)

def do(action: "Action", situation: Situation) -> Situation:
    return ("do", action, situation)

def is_s0(s: Situation) -> bool:
    return isinstance(s, tuple) and len(s) == 1 and s[0] == "s0"

def is_do(s: Situation) -> bool:
    return isinstance(s, tuple) and len(s) == 3 and s[0] == "do"

def action_of(s: Situation) -> "Action":
    if not is_do(s):
        raise ValueError("action_of requires a do-situation")
    return s[1]

def prior_situation(s: Situation) -> Situation:
    if not is_do(s):
        raise ValueError("prior_situation requires a do-situation")
    return s[2]

def situation_history(s: Situation) -> List["Action"]:
    hist = []
    while is_do(s):
        hist.append(action_of(s))
        s = prior_situation(s)
    hist.reverse()
    return hist

def situation_depth(s: Situation) -> int:
    d = 0
    while is_do(s):
        d += 1
        s = prior_situation(s)
    return d

def situation_prefix(s: Situation, n: int) -> Situation:
    hist = situation_history(s)
    if n > len(hist):
        raise ValueError("prefix longer than history")
    result = S0
    for a in hist[:n]:
        result = do(a, result)
    return result


class Action(NamedTuple):
    name: str
    args: Tuple[Any, ...]

    def __str__(self) -> str:
        if not self.args:
            return self.name
        return f"{self.name}({', '.join(map(str, self.args))})"

    def __repr__(self) -> str:
        return f"Action({self.name!r}, {self.args!r})"

def act(name: str, *args: Any) -> Action:
    return Action(name, tuple(args))


# ==============================================================================
# 2. FLUENT SYSTEM — HOLOGRAPHIC RECONSTRUCTION
# ==============================================================================

class Fluent:
    def __init__(self, name: str):
        self.name = name
        self._cache: Dict[Situation, Any] = {}

    def clear_cache(self) -> None:
        self._cache.clear()

    def holds(self, situation: Situation, *args: Any) -> Any:
        cache_key = (situation, args)
        if cache_key in self._cache:
            return self._cache[cache_key]
        value = self._evaluate(situation, *args)
        self._cache[cache_key] = value
        return value

    def _evaluate(self, situation: Situation, *args: Any) -> Any:
        raise NotImplementedError

    def ssa(self, action: Action, situation: Situation, *args: Any) -> Any:
        raise NotImplementedError


class RelationalFluent(Fluent):
    def __init__(self, name: str,
                 initially: Optional[Callable[..., bool]] = None,
                 positive_effect: Optional[Callable[[Action, Situation, Tuple], bool]] = None,
                 negative_effect: Optional[Callable[[Action, Situation, Tuple], bool]] = None):
        super().__init__(name)
        self.initially = initially or (lambda *a: False)
        self.pos = positive_effect or (lambda a, s, args: False)
        self.neg = negative_effect or (lambda a, s, args: False)

    def _evaluate(self, situation: Situation, *args: Any) -> bool:
        if is_s0(situation):
            return bool(self.initially(*args))
        a = action_of(situation)
        s = prior_situation(situation)
        if self.pos(a, s, args):
            return True
        if self.neg(a, s, args):
            return False
        return self._evaluate(s, *args)

    def ssa(self, action: Action, situation: Situation, *args: Any) -> bool:
        if self.pos(action, situation, args):
            return True
        if self.neg(action, situation, args):
            return False
        return self.holds(situation, *args)


class FunctionalFluent(Fluent):
    def __init__(self, name: str,
                 initially: Callable[..., Any],
                 update: Callable[[Action, Situation, Any, Tuple], Any]):
        super().__init__(name)
        self.initially = initially
        self.update = update

    def _evaluate(self, situation: Situation, *args: Any) -> Any:
        if is_s0(situation):
            return self.initially(*args)
        a = action_of(situation)
        s = prior_situation(situation)
        prev = self._evaluate(s, *args)
        return self.update(a, s, prev, args)

    def ssa(self, action: Action, situation: Situation, *args: Any) -> Any:
        prev = self.holds(situation, *args)
        return self.update(action, situation, prev, args)


# ==============================================================================
# 3. DOMAIN CLASS
# ==============================================================================

class Domain:
    def __init__(self, name: str):
        self.name = name
        self.fluents: Dict[str, Fluent] = {}
        self.poss_axioms: Dict[str, Callable[[Action, Situation], bool]] = {}
        self.procedures: Dict[str, "Prog"] = {}
        self.action_generators: Dict[str, Callable[[Situation], List[Action]]] = {}

    def add_fluent(self, fluent: Fluent) -> None:
        self.fluents[fluent.name] = fluent

    def add_poss(self, action_name: str, axiom: Callable[[Action, Situation], bool]) -> None:
        self.poss_axioms[action_name] = axiom

    def add_procedure(self, name: str, body: "Prog") -> None:
        self.procedures[name] = body

    def add_action_generator(self, action_name: str,
                             generator: Callable[[Situation], List[Action]]) -> None:
        self.action_generators[action_name] = generator

    def Poss(self, action: Action, situation: Situation) -> bool:
        axiom = self.poss_axioms.get(action.name)
        if axiom is None:
            return False
        return bool(axiom(action, situation))

    def holds(self, fluent_name: str, situation: Situation, *args: Any) -> Any:
        f = self.fluents.get(fluent_name)
        if f is None:
            raise KeyError(f"Unknown fluent: {fluent_name}")
        return f.holds(situation, *args)

    def clear_caches(self) -> None:
        for f in self.fluents.values():
            f.clear_cache()

    def all_ground_actions(self, situation: Situation) -> List[Action]:
        result = []
        for name, gen in self.action_generators.items():
            result.extend(gen(situation))
        return result


# ==============================================================================
# 4. GOLOG PROGRAM LANGUAGE
# ==============================================================================

class Prog:
    pass

@dataclass(frozen=True)
class Prim(Prog):
    action: Action

@dataclass(frozen=True)
class Seq(Prog):
    first: Prog
    second: Prog

@dataclass(frozen=True)
class Choice(Prog):
    left: Prog
    right: Prog

@dataclass(frozen=True)
class Star(Prog):
    body: Prog

@dataclass(frozen=True)
class Test(Prog):
    condition: Callable[[Situation], bool]

@dataclass(frozen=True)
class IfThenElse(Prog):
    condition: Callable[[Situation], bool]
    then_branch: Prog
    else_branch: Prog

@dataclass(frozen=True)
class While(Prog):
    condition: Callable[[Situation], bool]
    body: Prog

@dataclass(frozen=True)
class Concurrent(Prog):
    left: Prog
    right: Prog

@dataclass(frozen=True)
class PrioChoice(Prog):
    preferred: Prog
    alternative: Prog

@dataclass(frozen=True)
class ProcCall(Prog):
    name: str
    args: Tuple[Any, ...] = ()

def prim(a: Action) -> Prog:
    return Prim(a)

def seq(*progs: Prog) -> Prog:
    if not progs:
        raise ValueError("empty sequence")
    result = progs[0]
    for p in progs[1:]:
        result = Seq(result, p)
    return result

def choose(*progs: Prog) -> Prog:
    if not progs:
        raise ValueError("empty choice")
    result = progs[0]
    for p in progs[1:]:
        result = Choice(result, p)
    return result

def star(body: Prog) -> Prog:
    return Star(body)

def test(cond: Callable[[Situation], bool]) -> Prog:
    return Test(cond)

def if_(cond, then: Prog, else_: Prog) -> Prog:
    return IfThenElse(cond, then, else_)

def while_(cond, body: Prog) -> Prog:
    return While(cond, body)

def concurrent(left: Prog, right: Prog) -> Prog:
    return Concurrent(left, right)

def prio(preferred: Prog, alternative: Prog) -> Prog:
    return PrioChoice(preferred, alternative)

def call(name: str, *args: Any) -> Prog:
    return ProcCall(name, tuple(args))


# ==============================================================================
# 5. EXECUTION ENGINE
# ==============================================================================

class ExecutionError(Exception):
    pass

class GologEngine:
    def __init__(self, domain: Domain, max_star_unroll: int = 12, max_steps: int = 5000):
        self.domain = domain
        self.max_star_unroll = max_star_unroll
        self.max_steps = max_steps
        self.trace: List[Tuple[Situation, Action]] = []

    def Poss(self, action: Action, s: Situation) -> bool:
        return self.domain.Poss(action, s)

    def do_action(self, action: Action, s: Situation) -> Situation:
        if not self.Poss(action, s):
            raise ExecutionError(f"Action {action} not possible")
        news = do(action, s)
        self.trace.append((s, action))
        return news

    def trans(self, prog: Prog, s: Situation) -> List[Tuple[Prog, Situation]]:
        if isinstance(prog, Prim):
            if self.Poss(prog.action, s):
                news = self.do_action(prog.action, s)
                return [(None, news)]
            return []
        if isinstance(prog, Seq):
            steps = self.trans(prog.first, s)
            results = []
            for rem, news in steps:
                if rem is None:
                    results.append((prog.second, news))
                else:
                    results.append((Seq(rem, prog.second), news))
            if self.final(prog.first, s):
                results.extend(self.trans(prog.second, s))
            return results
        if isinstance(prog, Choice):
            return self.trans(prog.left, s) + self.trans(prog.right, s)
        if isinstance(prog, Star):
            results = []
            for rem, news in self.trans(prog.body, s):
                if rem is None:
                    results.append((Star(prog.body), news))
                else:
                    results.append((Seq(rem, Star(prog.body)), news))
            return results
        if isinstance(prog, Test):
            if prog.condition(s):
                return [(None, s)]
            return []
        if isinstance(prog, IfThenElse):
            if prog.condition(s):
                return self.trans(prog.then_branch, s)
            else:
                return self.trans(prog.else_branch, s)
        if isinstance(prog, While):
            if prog.condition(s):
                return self.trans(Seq(prog.body, prog), s)
            else:
                return [(None, s)]
        if isinstance(prog, Concurrent):
            results = []
            for rem, news in self.trans(prog.left, s):
                if rem is None:
                    results.append((prog.right, news))
                else:
                    results.append((Concurrent(rem, prog.right), news))
            for rem, news in self.trans(prog.right, s):
                if rem is None:
                    results.append((prog.left, news))
                else:
                    results.append((Concurrent(prog.left, rem), news))
            return results
        if isinstance(prog, PrioChoice):
            pref = self.trans(prog.preferred, s)
            if pref:
                return pref
            return self.trans(prog.alternative, s)
        if isinstance(prog, ProcCall):
            body = self.domain.procedures.get(prog.name)
            if body is None:
                raise ExecutionError(f"Undefined procedure: {prog.name}")
            return self.trans(body, s)
        raise TypeError(f"Unknown program construct: {type(prog)}")

    def final(self, prog: Prog, s: Situation) -> bool:
        if prog is None:
            return True
        if isinstance(prog, Prim):
            return False
        if isinstance(prog, Seq):
            return self.final(prog.first, s) and self.final(prog.second, s)
        if isinstance(prog, Choice):
            return self.final(prog.left, s) or self.final(prog.right, s)
        if isinstance(prog, Star):
            return True
        if isinstance(prog, Test):
            return prog.condition(s)
        if isinstance(prog, IfThenElse):
            if prog.condition(s):
                return self.final(prog.then_branch, s)
            else:
                return self.final(prog.else_branch, s)
        if isinstance(prog, While):
            if prog.condition(s):
                return False
            return True
        if isinstance(prog, Concurrent):
            return self.final(prog.left, s) and self.final(prog.right, s)
        if isinstance(prog, PrioChoice):
            return self.final(prog.preferred, s) or self.final(prog.alternative, s)
        if isinstance(prog, ProcCall):
            body = self.domain.procedures.get(prog.name)
            if body is None:
                return False
            return self.final(body, s)
        return False

    def execute(self, prog: Prog, s: Situation = S0,
                search: str = "dfs", max_depth: int = 200) -> Optional[Situation]:
        self.trace = []
        self.domain.clear_caches()
        if search == "dfs":
            return self._dfs(prog, s, 0, max_depth)
        elif search == "bfs":
            return self._bfs(prog, s, max_depth)
        else:
            raise ValueError(f"Unknown search strategy: {search}")

    def _dfs(self, prog: Prog, s: Situation, depth: int, max_depth: int) -> Optional[Situation]:
        if depth > max_depth:
            return None
        if self.final(prog, s):
            return s
        for rem, news in self.trans(prog, s):
            if rem is None:
                rem = Test(lambda sit: True)
            result = self._dfs(rem, news, depth + 1, max_depth)
            if result is not None:
                return result
        return None

    def _bfs(self, prog: Prog, s: Situation, max_depth: int) -> Optional[Situation]:
        from collections import deque
        queue = deque([(prog, s, 0)])
        visited = set()
        while queue:
            p, sit, d = queue.popleft()
            if d > max_depth:
                continue
            key = (id(p), sit)
            if key in visited:
                continue
            visited.add(key)
            if self.final(p, sit):
                return sit
            for rem, news in self.trans(p, sit):
                if rem is None:
                    rem = Test(lambda x: True)
                queue.append((rem, news, d + 1))
        return None

    def run_online(self, prog: Prog, s: Situation = S0) -> Situation:
        self.trace = []
        self.domain.clear_caches()
        steps = 0
        current_prog = prog
        current_sit = s
        while not self.final(current_prog, current_sit):
            if steps >= self.max_steps:
                raise ExecutionError("max_steps exceeded in online execution")
            transitions = self.trans(current_prog, current_sit)
            if not transitions:
                raise ExecutionError(f"Program blocked")
            rem, news = transitions[0]
            if rem is None:
                rem = Test(lambda x: True)
            current_prog = rem
            current_sit = news
            steps += 1
        return current_sit


# ==============================================================================
# 6. CLASSIC DOMAIN: BLOCKS WORLD
# ==============================================================================

def make_blocks_world(blocks: List[str]) -> Domain:
    dom = Domain("BlocksWorld")
    table = "table"

    def initially_on(x, y):
        return y == table and x in blocks

    def initially_clear(x):
        return x in blocks or x == table

    def initially_holding():
        return None

    def on_pos(a, s, args):
        x, y = args
        if a.name == "putdown" and a.args[0] == x and y == table:
            return True
        if a.name == "stack" and a.args[0] == x and a.args[1] == y:
            return True
        return False

    def on_neg(a, s, args):
        x, y = args
        if a.name == "pickup" and a.args[0] == x:
            return True
        if a.name == "unstack" and a.args[0] == x:
            return True
        return False

    def clear_neg(a, s, args):
        x = args[0]
        if a.name == "stack" and a.args[1] == x:
            return True
        if a.name == "pickup" and a.args[0] == x:
            return True
        if a.name == "unstack" and a.args[0] == x:
            return True
        return False

    on_f = RelationalFluent("on", initially=initially_on,
                            positive_effect=on_pos, negative_effect=on_neg)
    clear_f = RelationalFluent("clear", initially=initially_clear,
                               negative_effect=clear_neg)

    def holding_update(a, s, prev, args):
        if a.name == "pickup":
            return a.args[0]
        if a.name == "unstack":
            return a.args[0]
        if a.name in ("putdown", "stack"):
            return None
        return prev

    holding_f = FunctionalFluent("holding", initially=initially_holding,
                                 update=holding_update)

    dom.add_fluent(on_f)
    dom.add_fluent(clear_f)
    dom.add_fluent(holding_f)

    def poss_pickup(a, s):
        x = a.args[0]
        return (dom.holds("clear", s, x) and
                dom.holds("on", s, x, table) and
                dom.holds("holding", s) is None)

    def poss_putdown(a, s):
        return dom.holds("holding", s) == a.args[0]

    def poss_stack(a, s):
        x, y = a.args
        return (dom.holds("holding", s) == x and
                dom.holds("clear", s, y) and y != table)

    def poss_unstack(a, s):
        x, y = a.args
        return (dom.holds("on", s, x, y) and
                dom.holds("clear", s, x) and
                dom.holds("holding", s) is None and y != table)

    dom.add_poss("pickup", poss_pickup)
    dom.add_poss("putdown", poss_putdown)
    dom.add_poss("stack", poss_stack)
    dom.add_poss("unstack", poss_unstack)

    for name in ("pickup", "putdown"):
        dom.add_action_generator(name, lambda s, n=name: [act(n, b) for b in blocks])
    dom.add_action_generator("stack", lambda s: [act("stack", x, y) for x in blocks for y in blocks if x != y])
    dom.add_action_generator("unstack", lambda s: [act("unstack", x, y) for x in blocks for y in blocks if x != y])

    return dom


# ==============================================================================
# 7. CLASSIC DOMAIN: ELEVATOR
# ==============================================================================

def make_elevator_domain(floors: int = 5) -> Domain:
    dom = Domain("Elevator")
    floor_list = list(range(1, floors + 1))

    def init_at():
        return 1

    def at_update(a, s, prev, args):
        if a.name == "up":
            return min(prev + 1, floors)
        if a.name == "down":
            return max(prev - 1, 1)
        return prev

    at_f = FunctionalFluent("at", initially=init_at, update=at_update)

    door_f = RelationalFluent("door_open",
                              initially=lambda: False,
                              positive_effect=lambda a, s, args: a.name == "open",
                              negative_effect=lambda a, s, args: a.name == "close")

    req_f = RelationalFluent("requested",
                             initially=lambda f: False,
                             positive_effect=lambda a, s, args: a.name == "request" and a.args[0] == args[0],
                             negative_effect=lambda a, s, args: a.name == "turnoff" and a.args[0] == args[0])

    dom.add_fluent(at_f)
    dom.add_fluent(door_f)
    dom.add_fluent(req_f)

    dom.add_poss("up", lambda a, s: not dom.holds("door_open", s) and dom.holds("at", s) < floors)
    dom.add_poss("down", lambda a, s: not dom.holds("door_open", s) and dom.holds("at", s) > 1)
    dom.add_poss("open", lambda a, s: not dom.holds("door_open", s))
    dom.add_poss("close", lambda a, s: dom.holds("door_open", s))
    dom.add_poss("request", lambda a, s: True)
    dom.add_poss("turnoff", lambda a, s: dom.holds("requested", s, a.args[0]))

    dom.add_action_generator("up", lambda s: [act("up")])
    dom.add_action_generator("down", lambda s: [act("down")])
    dom.add_action_generator("open", lambda s: [act("open")])
    dom.add_action_generator("close", lambda s: [act("close")])
    dom.add_action_generator("request", lambda s: [act("request", f) for f in floor_list])
    dom.add_action_generator("turnoff", lambda s: [act("turnoff", f) for f in floor_list])

    return dom


# ==============================================================================
# 8. CLASSIC DOMAIN: COFFEE DELIVERY
# ==============================================================================

def make_coffee_domain() -> Domain:
    dom = Domain("Coffee")

    has_coffee = RelationalFluent("has_coffee", initially=lambda: False,
                                  positive_effect=lambda a, s, args: a.name == "buy_coffee",
                                  negative_effect=lambda a, s, args: a.name == "deliver")
    at_office = RelationalFluent("at_office", initially=lambda: True,
                                 positive_effect=lambda a, s, args: a.name == "go_office",
                                 negative_effect=lambda a, s, args: a.name == "go_shop")
    at_shop = RelationalFluent("at_shop", initially=lambda: False,
                               positive_effect=lambda a, s, args: a.name == "go_shop",
                               negative_effect=lambda a, s, args: a.name == "go_office")
    rain = RelationalFluent("rain", initially=lambda: False)
    umbrella = RelationalFluent("umbrella", initially=lambda: False,
                                positive_effect=lambda a, s, args: a.name == "get_umbrella")

    for f in (has_coffee, at_office, at_shop, rain, umbrella):
        dom.add_fluent(f)

    dom.add_poss("go_office", lambda a, s: not dom.holds("at_office", s))
    dom.add_poss("go_shop", lambda a, s: (
        not dom.holds("at_shop", s) and
        (not dom.holds("rain", s) or dom.holds("umbrella", s))
    ))
    dom.add_poss("buy_coffee", lambda a, s: dom.holds("at_shop", s) and not dom.holds("has_coffee", s))
    dom.add_poss("get_umbrella", lambda a, s: not dom.holds("umbrella", s))
    dom.add_poss("deliver", lambda a, s: dom.holds("at_office", s) and dom.holds("has_coffee", s))

    for name in ("go_office", "go_shop", "buy_coffee", "get_umbrella", "deliver"):
        dom.add_action_generator(name, lambda s, n=name: [act(n)])

    get_coffee = seq(
        prio(prim(act("get_umbrella")), test(lambda s: True)),
        prim(act("go_shop")),
        prim(act("buy_coffee")),
        prim(act("go_office")),
        prim(act("deliver"))
    )
    dom.add_procedure("get_coffee", get_coffee)
    return dom


# ==============================================================================
# 9. PLANNING HELPERS
# ==============================================================================

def naive_forward_search(domain: Domain, goal: Callable[[Situation], bool],
                         start: Situation = S0, max_depth: int = 15) -> Optional[List[Action]]:
    from collections import deque
    queue = deque([(start, [])])
    visited = {start}
    while queue:
        s, path = queue.popleft()
        if len(path) > max_depth:
            continue
        if goal(s):
            return path
        for a in domain.all_ground_actions(s):
            if domain.Poss(a, s):
                news = do(a, s)
                if news not in visited:
                    visited.add(news)
                    queue.append((news, path + [a]))
    return None


# ==============================================================================
# 10. UNIT TESTS
# ==============================================================================

def test_situation_basics() -> None:
    s = S0
    assert is_s0(s)
    a1 = act("pickup", "A")
    s1 = do(a1, s)
    assert is_do(s1)
    assert action_of(s1) == a1
    assert prior_situation(s1) == S0
    assert situation_depth(s1) == 1
    assert situation_history(s1) == [a1]
    print("[PASS] test_situation_basics")

def test_blocks_pickup_putdown() -> None:
    blocks = ["A", "B", "C"]
    dom = make_blocks_world(blocks)
    eng = GologEngine(dom)
    s = S0
    assert dom.holds("on", s, "A", "table")
    assert dom.holds("clear", s, "A")
    assert dom.holds("holding", s) is None
    assert dom.Poss(act("pickup", "A"), s)
    s1 = eng.do_action(act("pickup", "A"), s)
    assert dom.holds("holding", s1) == "A"
    assert not dom.holds("on", s1, "A", "table")
    assert dom.Poss(act("putdown", "A"), s1)
    s2 = eng.do_action(act("putdown", "A"), s1)
    assert dom.holds("holding", s2) is None
    assert dom.holds("on", s2, "A", "table")
    print("[PASS] test_blocks_pickup_putdown")

def test_elevator_up_down() -> None:
    dom = make_elevator_domain(4)
    eng = GologEngine(dom)
    s = S0
    assert dom.holds("at", s) == 1
    assert not dom.holds("door_open", s)
    s1 = eng.do_action(act("up"), s)
    assert dom.holds("at", s1) == 2
    s2 = eng.do_action(act("up"), s1)
    assert dom.holds("at", s2) == 3
    s3 = eng.do_action(act("open"), s2)
    assert dom.holds("door_open", s3)
    assert not dom.Poss(act("up"), s3)
    s4 = eng.do_action(act("close"), s3)
    assert not dom.holds("door_open", s4)
    print("[PASS] test_elevator_up_down")

def test_coffee_procedure() -> None:
    dom = make_coffee_domain()
    eng = GologEngine(dom)
    prog = call("get_coffee")
    final = eng.execute(prog, S0, search="dfs", max_depth=20)
    assert final is not None
    assert dom.holds("has_coffee", final) is False
    assert dom.holds("at_office", final)
    print("[PASS] test_coffee_procedure")

def test_golog_sequence_choice() -> None:
    dom = make_elevator_domain(3)
    eng = GologEngine(dom)
    prog = seq(
        prim(act("up")),
        choose(prim(act("up")), prim(act("down"))),
        prim(act("open"))
    )
    final = eng.execute(prog, S0, search="dfs")
    assert final is not None
    assert dom.holds("door_open", final)
    print("[PASS] test_golog_sequence_choice")

def test_star_and_test() -> None:
    dom = make_elevator_domain(3)
    eng = GologEngine(dom)
    prog = star(
        seq(
            test(lambda s: dom.holds("at", s) < 3),
            prim(act("up"))
        )
    )
    final = eng.run_online(prog, S0)
    assert dom.holds("at", final) == 3
    print("[PASS] test_star_and_test")

def test_naive_planner() -> None:
    dom = make_elevator_domain(3)
    goal = lambda s: dom.holds("at", s) == 3 and dom.holds("door_open", s)
    plan = naive_forward_search(dom, goal, max_depth=6)
    assert plan is not None
    assert len(plan) >= 2
    print(f"[PASS] test_naive_planner plan={[str(a) for a in plan]}")

def run_all_tests() -> None:
    print("=" * 60)
    print("HOLOGRAPHIC GOLOG ENGINE — TEST SUITE")
    print("=" * 60)
    test_situation_basics()
    test_blocks_pickup_putdown()
    test_elevator_up_down()
    test_coffee_procedure()
    test_golog_sequence_choice()
    test_star_and_test()
    test_naive_planner()
    print("=" * 60)
    print("ALL TESTS PASSED")
    print("=" * 60)


# ==============================================================================
# 11. DEMO DRIVER
# ==============================================================================

def demo_blocks() -> None:
    print("\n*** DEMO: Blocks World ***")
    blocks = ["A", "B", "C"]
    dom = make_blocks_world(blocks)
    eng = GologEngine(dom)
    s = S0
    print("Initial: holding =", dom.holds("holding", s))
    s = eng.do_action(act("pickup", "A"), s)
    print("After pickup(A): holding =", dom.holds("holding", s))
    s = eng.do_action(act("putdown", "A"), s)
    print("After putdown(A): holding =", dom.holds("holding", s))
    print("History:", [str(a) for a in situation_history(s)])

def demo_elevator() -> None:
    print("\n*** DEMO: Elevator ***")
    dom = make_elevator_domain(4)
    eng = GologEngine(dom)
    prog = seq(
        prim(act("request", 3)),
        prim(act("up")),
        prim(act("up")),
        prim(act("open")),
        prim(act("turnoff", 3)),
        prim(act("close"))
    )
    final = eng.execute(prog, S0)
    print("Final floor:", dom.holds("at", final))
    print("Door open:", dom.holds("door_open", final))
    print("Requested(3):", dom.holds("requested", final, 3))

def demo_coffee() -> None:
    print("\n*** DEMO: Coffee Delivery ***")
    dom = make_coffee_domain()
    eng = GologEngine(dom)
    final = eng.execute(call("get_coffee"), S0, search="dfs")
    print("Final situation depth:", situation_depth(final))
    print("at_office:", dom.holds("at_office", final))
    print("has_coffee:", dom.holds("has_coffee", final))
    print("Actions:", [str(a) for a in situation_history(final)])

def main() -> None:
    print("HOLOGRAPHIC GOLOG ENGINE v1.0")
    print("Situation-Calculus Interpreter — DYNA-GOLOG Kernel")
    print("-" * 60)
    run_all_tests()
    demo_blocks()
    demo_elevator()
    demo_coffee()
    print("\nHolographic GOLOG engine execution complete.")


if __name__ == "__main__":
    main()
