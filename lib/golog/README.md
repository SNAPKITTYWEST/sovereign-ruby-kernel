# lib/golog — Multi-Language GOLOG & Agent Artifacts

**License**: GPL-3.0-or-later OR Apache-2.0

This directory contains formal logic artifacts implementing the GOLOG
situation-calculus programming language, the Dyna-GOLOG Viterbi semiring
application, holographic GOLOG execution engines, and the EDAULC hardened
agent specification — across 9 languages.

---

## Files

### Ruby — FSL Agent Framework

| File | LOC | Description |
|------|-----|-------------|
| `agents_framework.rb` | 581 | Golog agent-to-agent FSL dialect runtime |
| `agent_dsl.rb` | 474 | Agent DSL: primitive, seq, choice, star, test |
| `fsl_compiler.rb` | 733 | FSL compiler: parse → normalize → emit |
| `protocol_enforcement.rb` | 573 | Runtime enforcement of FSL protocols |

Run tests: `ruby ../../spec/agent_tests.rb` (53 test cases)

---

### Dyna-GOLOG Viterbi Semiring — Cross-Language Implementations

The Dyna-GOLOG Viterbi artifact implements the Viterbi max-product semiring
`(R, max, ×, 0, 1)` over a situation-calculus GOLOG layer with:
- HMM domains (toy weather, POS tagger, CpG island)
- GOLOG control constructs (seq, choice, star, test)
- Log-domain numerically stable variant
- Lattice decoding extension
- Full test suites

| File | Language | Version | Author | Notes |
|------|----------|---------|--------|-------|
| `dyna_golog_viterbi.pl` | SWI-Prolog | v2.0 | — | Native Prolog; tabled backtracking |
| `dyna_golog_viterbi.oz` | Oz/Mozart | v2.0 | Ahmad | Hand-written; OOP + store memoization |
| `dyna_golog_viterbi.ecl` | ECLiPSe CLP | v2.0 | Ahmad | lib(ic) interval arithmetic verification |
| `dyna_golog_viterbi_v1.py` | Python | v1.0 | Ahmad | Original source ~2500 LOC; reference artifact |

**Semiring axioms** verified in each implementation:
- Commutativity and associativity of ⊕ (max) and ⊗ (×)
- Distributivity: a ⊗ (b ⊕ c) = (a ⊗ b) ⊕ (a ⊗ c)
- Additive identity: a ⊕ 0 = a
- Multiplicative identity: a ⊗ 1 = a
- Annihilator: a ⊗ 0 = 0

```bash
swipl lib/golog/dyna_golog_viterbi.pl          # SWI-Prolog
eclipse -b lib/golog/dyna_golog_viterbi.ecl -e "main, halt."
ozengine lib/golog/dyna_golog_viterbi.oz
python lib/golog/dyna_golog_viterbi_v1.py
```

---

### Holographic GOLOG Engine — Cross-Language Implementations

The holographic GOLOG engine implements the full GOLOG programming language with
the **holographic invariant**: every fluent value at any situation is completely
determined by the situation term `do(a, s)` and the successor-state axioms alone.
No external mutable store is required for correctness.

| File | Language | Author | Description |
|------|----------|--------|-------------|
| `holographic_golog_engine.py` | Python | Ahmad | Full engine: Blocks/Elevator/Coffee domains, 7 tests, BFS/DFS search |
| `holographic_golog.scm` | Scheme μKanren | Ahmad | Pure relational; no host imports; `transo`/`finalo`/`executo` as goals |

**Domains**: Blocks World (pickup/putdown/stack/unstack), Elevator (floor/door/requests),
Coffee Delivery (go_shop/buy/deliver with weather preconditions).

**Programs**: `Prim`, `Seq`, `Choice`, `Star`, `Test`, `IfThenElse`, `While`,
`Concurrent`, `PrioChoice`, `ProcCall`.

```bash
python lib/golog/holographic_golog_engine.py
chez --script lib/golog/holographic_golog.scm   # or: guile -s
```

---

### Constrained GOLOG

| File | Language | Author | Description |
|------|----------|--------|-------------|
| `constrained_golog.pl` | ISO Prolog | Ahmad | CLP(FD) + CLP(R) ~1500 LOC |

Extends classical GOLOG with:
- **FD constraints** on fluent values (energy budget, time windows, domain bounds)
- **Linear arithmetic store** (lightweight CLP(R) via dynamic predicates)
- `do_bounded/4` — depth-bounded execution with constraint propagation
- Temporal STN stub, cumulative resource constraint
- Domains: Blocks World + energy, Elevator + time, Coffee Delivery + weather

```bash
swipl lib/golog/constrained_golog.pl
?- demo_blocks.
?- demo_coffee.
```

---

### EDAULC Agent — Hardened Specification v2.0

| File | Language | Author | Description |
|------|----------|--------|-------------|
| `edaulc_agent.pl` | SWI-Prolog | Ahmad | Default-deny enterprise agent, 17 plunit tests |

A formally specified default-deny agent with 7 documented defect fixes over v1:

| ID | Fix |
|----|-----|
| E1 | Groundness guard on `permitted/1` — eliminates floundering under `\+` |
| E2 | Class-based prohibition (medical/legal/financial) replaces atom equality |
| E3 | Roles ↔ competencies separated; `maps_to/2` referential integrity enforced |
| E4 | Governing principles enforced via `principle_gate/2` hooks |
| E5 | `validate_kb/0` static self-check: arity, groundness, referential integrity |
| E6 | 17 plunit tests: trust axioms, classifier, qualification, hard denials |
| E7 | Self-identified as `edaulc`; inactive agent refuses everything deterministically |

```bash
# Load and run all tests
swipl -g "use_module('lib/golog/edaulc_agent'), run_tests, halt." /dev/null

# Interactive queries
swipl lib/golog/edaulc_agent.pl
?- execution_decision(configure_aws_infrastructure, devops_specialist, D).
D = permit.
?- execution_decision(draft_contract, devops_specialist, D).
D = deny(prohibited_class(advisory_legal)).
```

---

## Theoretical Foundations

- **Situation Calculus**: Reiter (2001) — `S0`, `do(a,s)`, fluents, SSA, Poss
- **GOLOG**: Levesque et al. (1997) — seq, choice, star, test, concurrent
- **Dyna**: Eisner & Goldlust (2011) — semiring DP over relational rules
- **Viterbi Semiring**: `(R, max, ×, 0, 1)` — most-probable-path inference
- **μKanren**: Hemann & Friedman (2013) — interleaving streams, unification
- **CLP(FD/R)**: Jaffar & Maher (1994) — constraint logic programming

## Language Stack Policy

- **Allowed in this directory**: Prolog, ECLiPSe, Oz/Mozart, Python (existing artifacts only), Scheme, Ruby
- **No new Python**: Python kernel retired for new work; use Prolog/Scheme/Oz
- **License**: GPL-3.0-or-later OR Apache-2.0 on all files; no MIT
