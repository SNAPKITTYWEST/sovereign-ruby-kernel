# Ruby Family Language Stack — Architecture

## Executive Summary

A modular, formally-specified ecosystem treating Ruby not as a single language but as a **language family** with distinct runtimes, semantics, and implementations.

```
                    LISP (ancestry)
                      │
                 Smalltalk (influence)
                      │
                      ├──────────────┐
                      │              │
                    Ruby          Self (prototype model)
                      │
        ┌─────────────┼───────────────┐
        │             │               │
     CRuby          JRuby          Rubinius
        │
   ┌────┴────┐
   │         │
 mruby    TruffleRuby
   │
   └── embedded Ruby

Ruby descendants:
 ├── Crystal (static typing, LLVM)
 ├── Opal (JavaScript backend)
 └── Mirah (JVM, statically typed)
```

## Core Principles

1. **Semantic Fidelity**: Each runtime retains its distinct execution model
2. **Formal Specification**: Language semantics defined independently of implementation
3. **Explicit Differences**: Backend-specific behavior is marked, not hidden
4. **Modular Architecture**: Parser → AST → IR → Backend
5. **Conformance Testing**: Cross-runtime test matrices, not assumed compatibility
6. **Auditable Governance**: Clear separation between specification and implementation

## Layers

### Layer 1: Language Specification
- Ruby object model
- Method dispatch semantics
- Block/closure formalization
- Exception semantics
- Reflection capabilities
- Formal invariants

### Layer 2: Syntax & Parsing
- Language-independent lexer
- Recursive descent parser
- Normalized AST
- Source location preservation
- Error recovery

### Layer 3: Intermediate Representation (IR)
- Runtime-agnostic IR
- Method call abstraction
- Control flow graph
- Exception edges
- Reflection operations

### Layer 4: Backend Implementations
- **CRuby**: Dynamic object model, C integration
- **JRuby**: JVM integration, Java interop
- **Rubinius**: Bytecode VM, method dispatch
- **mruby**: Embedded profile, constrained runtime
- **TruffleRuby**: Truffle/Graal specialization
- **Crystal**: Static typing, LLVM codegen
- **Opal**: JavaScript backend
- **Mirah**: Static typing, JVM bytecode

### Layer 5: Conformance & Governance
- Cross-runtime test suite
- Compatibility matrices
- Invariant verification
- Benchmark framework
- Formal proof of properties

## Key Distinctions

### Dynamic vs Static Typing
- **CRuby, JRuby, Rubinius, TruffleRuby, mruby**: Dynamic dispatch, runtime type checking
- **Crystal**: Static typing at compile time (not Ruby 1:1)
- **Mirah**: Static typing, explicit type annotations

### Execution Model
- **CRuby**: Bytecode VM, C-backed objects
- **JRuby**: JVM bytecode, Java object integration
- **Rubinius**: Custom bytecode, Ruby-implemented runtime primitives
- **mruby**: Minimal bytecode, embedded host binding
- **TruffleRuby**: Partial evaluation, polymorphic inline caches

### Target Platform
- **CRuby, JRuby, Rubinius, TruffleRuby**: Desktop/server
- **mruby**: Embedded, microcontroller, RTOS
- **Crystal**: Native compilation, LLVM backend
- **Opal**: Browser execution
- **Mirah**: JVM execution

## Non-Goals

- Do NOT claim all runtimes are semantically identical
- Do NOT silently convert dynamic semantics to static
- Do NOT erase historical implementation differences
- Do NOT replace backend-specific behavior with approximations
- Do NOT assume compatibility without conformance testing

## Deliverables

1. ✓ Language specification (`spec/`)
2. ✓ Parser architecture (`parser/`)
3. ✓ AST normalization (`ast/`)
4. ✓ Common IR (`ir/`)
5. ✓ Runtime abstractions (`runtimes/`)
6. ✓ Backend specifications (per runtime)
7. ✓ Conformance suite (`conformance/`)
8. ✓ Formal invariants (`spec/invariants.md`)
9. ✓ Interoperability bridges (`interop/`)
10. ✓ Governance rules (`governance/`)

---

See individual layer documentation for detailed specifications.
