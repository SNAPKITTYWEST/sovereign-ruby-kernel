# Sovereign Ruby Kernel — Symbolic AST → Self Synthesis

**License**: GPL-3.0-or-later OR Apache-2.0 (dual-licensed)

A symbolic kernel that builds abstract syntax trees over Q(√5), verifies them
through a 4-stage pipeline (Clojure TRS → APL verify → AXIOM proof → WORM seal),
then synthesizes the Ruby AST into Self-language prototype objects via an
11-agent swarm.

## Architecture

```
lib/
├── ast/                    # Abstract syntax trees
│   ├── node.rb             # Immutable AST node (transform, fold, to_sexp)
│   ├── phi_algebra.rb      # φ-algebra: literals, phi, galois conjugate, norm
│   └── rewrite.rb          # Term rewriting: φ²=φ+1, normalize, confluence check
├── kernel/                 # Core kernel
│   ├── symbolic_kernel.rb  # TRS evaluation, verification, AST forest
│   ├── worm.rb             # WORM append-only chain (SHA-256, thread-safe)
│   └── governance.rb       # State machine: init → verified → sealed
├── stages/                 # Pipeline stages
│   ├── clojure_trs.rb      # Stage 1: Clojure symbolic TRS (inline fallback)
│   ├── apl_verify.rb       # Stage 2: APL geometric verification
│   ├── axiom_proof.rb      # Stage 3: AXIOM formal proof / rewrite engine
│   └── worm_seal.rb        # Stage 4: Final WORM seal with governance
└── swarm/                  # Swarm synthesis
    ├── agent.rb            # 8 agent roles (scout→parser→rewriter→...→sealer)
    ├── topology.rb         # DAG pipeline: 11 agents, fan-out/converge
    └── self_synthesis.rb   # Ruby AST → Self prototype objects
```

## Run

```bash
ruby bin/orchestrate          # Full pipeline: build AST → verify → synthesize Self
ruby spec/kernel_spec.rb      # 24 tests across AST, kernel, stages, swarm
```

## Swarm Blueprint

See `SWARM_BLUEPRINT.md` for the full 11-agent topology, Self translation rules,
and the self-modification invariant (N(TRS) ∈ Q under Galois conjugation).

## Key Properties

- **Canonical TRS**: 388.985128 (φ-weighted sum over BOW-Ω depths)
- **Galois norm**: TRS × σ(TRS) ∈ Q (rational, verifiable)
- **Confluence**: rewrite rules are order-independent (proven by exhaustive check)
- **Self synthesis**: AST nodes → Self prototype slots + parent chains
- **WORM chain**: every stage sealed with SHA-256 append-only log
- **Governance**: fail-closed state machine (init→verified→sealed, no rollback from sealed)
