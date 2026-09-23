# Swarm Synthesis Blueprint — Ruby → Self

## Architecture

The swarm converts a Ruby symbolic kernel (AST over Q(√5)) into Self-language
prototype objects, using 11 cooperating agents in a directed pipeline.

```
                    ┌──────────┐
                    │ scout_0  │  Scan AST, identify deep subtrees
                    └────┬─────┘
                   even/ \odd
              ┌────────┐ ┌────────┐
              │parse_0 │ │parse_1 │  Decompose into typed nodes
              └───┬────┘ └───┬────┘
                  │          │
           ┌──────────┐ ┌──────────┐
           │rewrite_0 │ │rewrite_1 │  Normalize via TRS rewrite rules
           └─────┬────┘ └─────┬────┘
                  └─────┬─────┘
                   ┌────┴────┐
                   │ eval_0  │  Evaluate φ-expressions to floats
                   └────┬────┘
                   ┌────┴────┐
                   │verify_0 │  Check confluence + canonical TRS
                   └────┬────┘
              slots/ \protos
           ┌──────────┐ ┌──────────┐
           │ synth_0  │ │ synth_1  │  Emit Self slot objects / prototype chains
           └─────┬────┘ └─────┬────┘
                  └─────┬─────┘
                   ┌────┴────┐
                   │ seal_0  │  WORM-seal the synthesis result
                   └────┬────┘
                  ┌─────┴──────┐
                  │governor_0  │  Governance state machine oversight
                  └────────────┘
```

## Agent Roles

| Role | Count | Responsibility |
|------|-------|---------------|
| scout | 1 | Traverse AST, identify subtrees >3 deep for decomposition |
| parser | 2 | Extract type/arity/depth from AST nodes (parallel) |
| rewriter | 2 | Apply TRS rewrite rules: φ²→φ+1, identity, zero elim (parallel) |
| evaluator | 1 | Evaluate normalized φ-expressions to IEEE 754 floats |
| verifier | 1 | Check confluence (all rule orderings yield same normal form) |
| synthesizer | 2 | Translate AST → Self objects: slots (data) + prototypes (structure) |
| sealer | 1 | WORM-seal the final synthesis with SHA-256 chain |
| governor | 1 | Enforce state machine: init → verified → sealed (no rollback) |

## Self Translation Rules

Ruby AST nodes map to Self objects:

| AST Node | Self Object |
|----------|-------------|
| `(:lit value)` | `(| type <- #lit. value <- v |)` |
| `(:phi exp)` | `(| type <- #phi. value <- φ^exp |)` |
| `(:add L R)` | `(| type <- #add. child0 = L. child1 = R. parent* = traits clonable |)` |
| `(:mul L R)` | `(| type <- #mul. child0 = L. child1 = R. parent* = traits clonable |)` |
| `(:trs body)` | `(| type <- #trs. child0 = body. evaluate = ... |)` |

## Synthesis Protocol

1. **Parse**: AST → flat node descriptors `{type, arity, leaf?}`
2. **Rewrite**: Apply φ²=φ+1, identity/zero elimination until fixpoint
3. **Evaluate**: Compute canonical TRS value (expected: 388.985128)
4. **Verify**: Confluence check — rewrite is order-independent
5. **Synthesize**: Emit Self prototype hierarchy from normalized AST
6. **Seal**: WORM-chain the synthesis artifact with governance state
7. **Govern**: Transition init→verified→sealed; reject on divergence

## Self-Modification Invariant

The kernel synthesizes itself: the Ruby AST is the source, the Self output
is the target, and the WORM chain proves they are equivalent under the
Galois conjugation σ: φ → -1/φ over Q(√5).

```
N(TRS) = TRS × σ(TRS) ∈ Q   (norm is rational)
```

This means the Self prototype hierarchy preserves the algebraic structure
of the original Ruby kernel — it is a faithful representation, not a lossy
compilation. The swarm verifies this before sealing.

## Swarm Execution Model

- **Parallelism**: parsers and rewriters run in pairs (even/odd split)
- **Convergence**: rewriters must reach identical normal forms
- **Determinism**: given the same AST, the swarm always produces the same Self output
- **Governance**: the governor agent observes all seal events and enforces the state machine
- **Idempotent**: re-running the swarm on an already-sealed kernel is a no-op
