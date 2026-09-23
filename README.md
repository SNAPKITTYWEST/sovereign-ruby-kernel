# Sovereign Ruby Kernel — Symbolic AST → Self Synthesis

**License**: GPL-3.0-or-later OR Apache-2.0 (dual-licensed)

A symbolic kernel that builds abstract syntax trees over Q(√5), verifies them
through a 4-stage pipeline (Clojure TRS → APL verify → AXIOM proof → WORM seal),
then synthesizes the Ruby AST into Self-language prototype objects via an
11-agent swarm.

## Repository Map

```
sovereign-ruby-kernel/
├── lib/
│   ├── ast/                         # φ-algebra AST
│   ├── golog/                       # Multi-language GOLOG & agent artifacts
│   ├── kernel/                      # Symbolic kernel + governance + WORM chain
│   ├── stages/                      # 4-stage verification pipeline
│   └── swarm/                       # 11-agent swarm topology
├── quantum-holographic/             # SGMT 3-agent EGG crystallization pipeline
├── ruby-family-stack/               # 8-runtime Ruby language family specification
├── spec/                            # Test suites
├── bin/                             # Entrypoint
├── CLONE_GATE.md
├── SWARM_BLUEPRINT.md
└── README.md
```

---

## Core Kernel

```
lib/
├── ast/
│   ├── node.rb             # Immutable AST node (transform, fold, to_sexp)
│   ├── phi_algebra.rb      # φ-algebra: literals, phi, galois conjugate, norm
│   └── rewrite.rb          # Term rewriting: φ²=φ+1, normalize, confluence check
├── kernel/
│   ├── symbolic_kernel.rb  # TRS evaluation, verification, AST forest
│   ├── worm.rb             # WORM append-only chain (SHA-256, thread-safe)
│   └── governance.rb       # State machine: init → verified → sealed
├── stages/
│   ├── clojure_trs.rb      # Stage 1: Clojure symbolic TRS (inline fallback)
│   ├── apl_verify.rb       # Stage 2: APL geometric verification
│   ├── axiom_proof.rb      # Stage 3: AXIOM formal proof / rewrite engine
│   └── worm_seal.rb        # Stage 4: Final WORM seal with governance
└── swarm/
    ├── agent.rb            # 8 agent roles (scout→parser→rewriter→...→sealer)
    ├── topology.rb         # DAG pipeline: 11 agents, fan-out/converge
    └── self_synthesis.rb   # Ruby AST → Self prototype objects
```

### Key Properties

- **Canonical TRS**: 388.985128 (φ-weighted sum over BOW-Ω depths)
- **Galois norm**: TRS × σ(TRS) ∈ Q (rational, verifiable)
- **Confluence**: rewrite rules are order-independent (proven by exhaustive check)
- **Self synthesis**: AST nodes → Self prototype slots + parent chains
- **WORM chain**: every stage sealed with SHA-256 append-only log
- **Governance**: fail-closed state machine (init→verified→sealed, no rollback from sealed)

### Run

```bash
ruby bin/orchestrate          # Full pipeline: build AST → verify → synthesize Self
ruby spec/kernel_spec.rb      # 24 tests across AST, kernel, stages, swarm
```

---

## GOLOG — Multi-Language Agent Implementations

`lib/golog/` contains formal logic artifacts across 9 languages implementing
situation-calculus GOLOG programs, the Dyna-GOLOG Viterbi semiring, holographic
execution engines, and the EDAULC hardened agent spec. See [`lib/golog/README.md`](lib/golog/README.md).

| File | Language | Description |
|------|----------|-------------|
| `agents_framework.rb` | Ruby | FSL agent-to-agent dialect framework (581 LOC) |
| `agent_dsl.rb` | Ruby | Agent DSL definitions (474 LOC) |
| `fsl_compiler.rb` | Ruby | FSL compiler (733 LOC) |
| `protocol_enforcement.rb` | Ruby | Protocol enforcement (573 LOC) |
| `dyna_golog_viterbi.pl` | SWI-Prolog | Dyna-GOLOG Viterbi semiring v2.0 |
| `dyna_golog_viterbi.oz` | Oz/Mozart | Hand-written by Ahmad — Oz version |
| `dyna_golog_viterbi.ecl` | ECLiPSe CLP | ECLiPSe version with lib(ic) verification |
| `dyna_golog_viterbi_v1.py` | Python | Original v1.0 source (~2500 LOC) |
| `holographic_golog_engine.py` | Python | Holographic GOLOG engine (Blocks/Elevator/Coffee) |
| `holographic_golog.scm` | Scheme μKanren | Pure relational μKanren situation calculus |
| `constrained_golog.pl` | ISO Prolog | CLP(FD) + CLP(R) constrained GOLOG (~1500 LOC) |
| `edaulc_agent.pl` | SWI-Prolog | EDAULC hardened agent spec v2.0 (17 plunit tests) |

### Run GOLOG artifacts

```bash
# SWI-Prolog Dyna-GOLOG
swipl lib/golog/dyna_golog_viterbi.pl

# ECLiPSe Dyna-GOLOG
eclipse -b lib/golog/dyna_golog_viterbi.ecl -e "main, halt."

# Oz/Mozart
ozengine lib/golog/dyna_golog_viterbi.oz

# Python holographic engine
python lib/golog/holographic_golog_engine.py

# EDAULC agent tests
swipl -g "use_module(lib/golog/edaulc_agent), run_tests, halt." /dev/null

# Scheme μKanren
chez --script lib/golog/holographic_golog.scm   # or guile
```

---

## Quantum-Holographic EGG Crystallization

`quantum-holographic/` implements the SGMT 3-agent deterministic pipeline that
generates 8,192 immutable quantum-holographic EGG capsules under full constraint
satisfaction.

```
quantum-holographic/
├── submissions/
│   ├── agent-1-quantum-logic.xml      # Quantum state space formalization (Prolog)
│   ├── agent-2-holographic-principle.xml  # Holographic mapping (Datalog)
│   └── agent-3-egg-crystallizer.xml   # EGG synthesis (CLP(FD))
├── sgmt-crystallization.pl            # SWI-Prolog crystallization engine
├── xslt-normalize.xsl                 # XML → canonical form
└── README.md
```

**Constraints**: C1 normalization, C2 unitarity, C3 no-cloning, C4 CFT central charge,
C5 Ryu-Takayanagi bound, C6 DAG acyclic, C7 DAG closed, C8 semantic uniqueness.

```bash
swipl -f quantum-holographic/sgmt-crystallization.pl -t halt
```

---

## Ruby Family Language Stack

`ruby-family-stack/` specifies 8 runtime profiles under a unified governance model.

| Runtime | Tier | Notes |
|---------|------|-------|
| CRuby (MRI) | Reference | C extension ABI, GVL, YARV |
| JRuby | JVM | True parallelism, Java interop |
| Rubinius | LLVM | Native threads, object-space access |
| mruby | Embedded | ISO subset, no GC pause guarantees |
| TruffleRuby | GraalVM | Polyglot, Truffle partial eval |
| Crystal | LLVM | Static types, Crystal stdlib ≠ Ruby stdlib |
| Opal | JS | Browser-only subset, no blocking I/O |
| Mirah | JVM | Java-typed, minimal runtime |

```
ruby-family-stack/
├── ARCHITECTURE.md
├── README.md
├── spec/
│   ├── LANGUAGE_SPECIFICATION.md
│   └── FORMAL_INVARIANTS.md
├── parser/
│   └── PARSER_ARCHITECTURE.md
├── ir/
│   └── INTERMEDIATE_REPRESENTATION.md
├── runtimes/
│   └── RUNTIME_ABSTRACTION.md
└── governance/
    └── GOVERNANCE.md
```

---

## Agent Tests

`spec/agent_tests.rb` — 53 test cases covering the Golog agent-to-agent FSL dialect
(agents_framework, fsl_compiler, protocol_enforcement, agent_dsl).
