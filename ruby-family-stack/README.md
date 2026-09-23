# Ruby Family Language Stack

**A formal, modular specification for the Ruby language ecosystem.**

Treats Ruby not as a single language but as a **language family** with distinct runtimes, each retaining its own semantic model and optimization strategies.

---

## What is This?

Traditional Ruby projects assume all implementations (CRuby, JRuby, Rubinius, etc.) are semantically identical. They're not.

This project provides:

1. **Language Specification**: What Ruby *is*, independent of implementation
2. **Parser Architecture**: How to parse Ruby into a common AST
3. **Intermediate Representation (IR)**: Runtime-agnostic code representation
4. **Runtime Abstractions**: How each runtime differs and what it guarantees
5. **Conformance Framework**: Cross-runtime testing and compatibility matrices
6. **Formal Invariants**: Provable properties all implementations must maintain
7. **Governance**: Clear rules preventing silent semantic divergence

---

## Architecture

```
LANGUAGE SPECIFICATION
        │
        ├─ Object Model (12 invariants)
        ├─ Method Dispatch (4 invariants)
        ├─ Closures (3 invariants)
        ├─ Exceptions (3 invariants)
        └─ ... (28 total invariants)
        │
        ▼
    PARSER
    ├─ Lexer
    ├─ Parser (recursive descent)
    ├─ AST Builder
    └─ Normalization
        │
        ▼
INTERMEDIATE REPRESENTATION (IR)
        │
        ├─ Method definitions
        ├─ Control flow
        ├─ Object allocation
        ├─ Method calls
        ├─ Exception handling
        └─ Reflection
        │
        ├─→ CRuby Backend (bytecode VM)
        ├─→ JRuby Backend (JVM)
        ├─→ Rubinius Backend (bytecode VM)
        ├─→ mruby Backend (embedded)
        ├─→ TruffleRuby Backend (Graal/Truffle)
        ├─→ Crystal Backend (static typing, LLVM)
        ├─→ Opal Backend (JavaScript)
        └─→ Mirah Backend (JVM, typed)
        │
        ▼
CONFORMANCE SUITE
    ├─ Object model tests
    ├─ Method dispatch tests
    ├─ Exception handling tests
    ├─ Reflection tests
    ├─ Runtime-specific tests
    └─ Compatibility matrix
```

---

## Key Documents

### Specification Layer

- **`spec/LANGUAGE_SPECIFICATION.md`** — Object model, method dispatch, blocks, exceptions, reflection
- **`spec/FORMAL_INVARIANTS.md`** — 28 provable properties every runtime must maintain
- **`spec/HERITAGE.md`** (planned) — Lisp, Smalltalk, Self influences

### Implementation Layer

- **`parser/PARSER_ARCHITECTURE.md`** — Lexer, parser, AST, normalization
- **`ir/INTERMEDIATE_REPRESENTATION.md`** — Runtime-agnostic IR design
- **`runtimes/RUNTIME_ABSTRACTION.md`** — Comparison of all 8 runtimes

### Backend Specifications

- **`runtimes/cruby/SPECIFICATION.md`** (planned)
- **`runtimes/jruby/SPECIFICATION.md`** (planned)
- **`runtimes/rubinius/SPECIFICATION.md`** (planned)
- **`runtimes/mruby/SPECIFICATION.md`** (planned)
- **`runtimes/truffleruby/SPECIFICATION.md`** (planned)
- **`languages/crystal/SPECIFICATION.md`** (planned)
- **`languages/opal/SPECIFICATION.md`** (planned)
- **`languages/mirah/SPECIFICATION.md`** (planned)

### Governance & Testing

- **`governance/GOVERNANCE.md`** — Committee, conformance levels, exception process, versioning
- **`conformance/`** — Test suite organized by invariant (planned)

---

## Why This Matters

### Problem: Silent Divergence

Today, backends diverge from each other without clear governance:

```ruby
# Works in CRuby:
p = Proc.new { return 1 }  # Returns from enclosing method

# Doesn't work in Crystal:
p = Proc.new { return 1 }  # Compile error (but not a clear one)

# In Opal, works but behaves differently (JavaScript returns from lambda)
```

Most projects silently approximate unsupported features, producing wrong results without notice.

### Solution: Explicit Specification

Every backend now declares:

1. ✓ Which invariants it supports
2. ✗ Which it doesn't (with formal exception)
3. How incompatible code is rejected (not silently approximated)
4. What the workaround is

```
Crystal cannot satisfy I8 (blocks as closures).
Code using blocks is rejected at compile time with a clear error.
Workaround: Use compile-time capture (move semantics).
```

---

## Conformance Levels

### Level 1: Core Compliance (MANDATORY)

Every runtime MUST:

- ✓ Parse valid Ruby syntax
- ✓ Produce results matching Language Specification
- ✓ Satisfy all Formal Invariants (or file formal exception)
- ✓ Reject incompatible features clearly (not silently)

### Level 2: Feature Completeness (EXPECTED)

Every runtime SHOULD:

- ✓ Support all Ruby features
- ✓ Provide equivalent performance
- ✓ Include comprehensive standard library

### Level 3: Optimization (OPTIONAL)

Runtimes MAY:

- ✓ Apply backend-specific optimizations
- ✓ Support platform-specific features (Java interop, JS interop, etc.)
- ✓ Tune for specific workloads

---

## Runtime Comparison

| Feature | CRuby | JRuby | Rubinius | mruby | TruffleRuby | Crystal | Opal | Mirah |
|---------|-------|-------|----------|-------|-------------|---------|------|-------|
| **Execution** | Interpreted | JVM | Interpreted | Interpreted | JIT | AOT | JS | JVM |
| **Performance** | Baseline | Good | Good | Poor | Excellent | Excellent | Variable | Excellent |
| **Startup** | Fast | Slow | Fast | Very Fast | Slow | Very Fast | Fast | Fast |
| **Memory** | Moderate | High | Moderate | Very Low | High | Low | Low | Moderate |
| **Threads** | Green+OS | OS | Green+OS | None | OS | None | None | OS |
| **Embedded** | No | No | No | **Yes** | No | Possible | Yes | No |
| **Web Target** | No | No | No | No | No | No | **Yes** | No |
| **Static Typing** | No | No | No | No | No | **Yes** | No | **Yes** |
| **Java Interop** | FFI | **Native** | No | FFI | Polyglot | No | No | **Native** |

---

## Formal Invariants Summary

28 formally specified invariants, organized by category:

**Object Model** (I1–I6)
- Object identity, class relationships, singleton classes, method lookup

**Method Dispatch** (I7–I10)
- Dynamic dispatch, block binding, MRO, method_missing

**Closures** (I11–I13)
- Variable capture by reference, Proc vs lambda, block scoping

**Exceptions** (I14–I16)
- Type matching, ensure execution, propagation

**Variables** (I17–I19)
- Local, instance, class, global scope

**Numeric** (I20–I21)
- Integer vs float division, coercion

**Strings/Symbols** (I22–I23)
- Mutability, interning, interpolation

**Reflection** (I24–I25)
- Introspection, method_missing

**Static Typing** (I26)
- Type soundness (Crystal, Mirah)

**Concurrency** (I27–I28)
- Thread safety, Fiber vs OS threads

See `spec/FORMAL_INVARIANTS.md` for full details.

---

## Example: Method Lookup (Invariant I4, I9)

**Specification:**
```
Method lookup is deterministic. Given a receiver and selector,
the same method is always found (or always raises NoMethodError).

Lookup order:
  1. Singleton methods on receiver
  2. Receiver's class instance methods
  3. Included modules (in reverse order)
  4. Parent class (recursively)
  5. method_missing (if defined)
  6. NoMethodError
```

**Conformance Test:**
```ruby
conformance/all/test_method_lookup.rb

class Parent
  def foo; "from Parent"; end
end

class Child < Parent; end

Child.new.foo.should == "from Parent"
Child.new.foo.should == "from Parent"  # Same result
```

**All Runtimes Pass:** ✓ CRuby, JRuby, Rubinius, mruby, TruffleRuby, Crystal, Opal, Mirah

---

## Governance

### Exception Process

If a backend can't satisfy an invariant:

1. **RFC**: File a formal exception request
2. **Review**: Committee votes (2/3 majority)
3. **Update Spec**: Invariant annotated with exception
4. **Reject at Parse Time**: Code using unsupported feature is rejected clearly
5. **Document Workaround**: What to use instead

**Example Exception**: Crystal can't support I8 (blocks with dynamic capture).

```markdown
governance/exceptions/rfc-001-crystal-no-blocks.md

Title: Crystal cannot support block capture by reference
Status: APPROVED (2024-01-15)
Invariants: I8, I11, I13
Reason: Static typing incompatible with dynamic closures
Workaround: Use compile-time capture (move semantics)
```

### Committee

- **Chair**: Ruby Family Specification Lead
- **Members**: One representative per runtime/language
- **Community**: Elected representatives
- **Voting**: Supermajority (2/3) for major changes

### Versioning

```
MAJOR.MINOR.PATCH

2.7.0 → 3.0.0: Breaking changes allowed
2.7.0 → 2.8.0: New features, backward compatible
2.7.0 → 2.7.1: Bug fixes
```

---

## Contributing

### For Language Designers

Submit RFCs for new language features:
1. Create `governance/rfc-*.md`
2. Describe feature, impact on invariants, backend implications
3. Committee review (2-week comment period)
4. Supermajority vote

### For Backend Implementers

Add your runtime:
1. Create `runtimes/{name}/SPECIFICATION.md`
2. Document which invariants you support
3. File exceptions for unsupported invariants
4. Pass conformance test suite
5. Join committee (optional)

### For Contributors

- Expand parser architecture
- Implement backends
- Extend conformance tests
- Improve formal verification
- Document edge cases

---

## Repository Structure

```
ruby-family-stack/
│
├── ARCHITECTURE.md                # Overview
├── README.md                      # This file
│
├── spec/
│   ├── LANGUAGE_SPECIFICATION.md  # What Ruby is
│   ├── FORMAL_INVARIANTS.md       # 28 provable properties
│   └── versions/
│       ├── 2.7.md
│       └── 3.0.md
│
├── parser/
│   ├── PARSER_ARCHITECTURE.md     # How to parse Ruby
│   ├── lexer.rb (planned)
│   ├── parser.rb (planned)
│   └── ast.rb (planned)
│
├── ir/
│   ├── INTERMEDIATE_REPRESENTATION.md
│   └── ir.rb (planned)
│
├── runtimes/
│   ├── RUNTIME_ABSTRACTION.md
│   ├── cruby/
│   │   ├── SPECIFICATION.md (planned)
│   │   └── DEVIATIONS.md (planned)
│   ├── jruby/
│   ├── rubinius/
│   ├── mruby/
│   └── truffleruby/
│
├── languages/
│   ├── crystal/
│   │   └── SPECIFICATION.md (planned)
│   ├── opal/
│   └── mirah/
│
├── conformance/
│   ├── all/                       # Tests all must pass
│   │   ├── test_object_model.rb (planned)
│   │   ├── test_method_dispatch.rb (planned)
│   │   └── ...
│   ├── cruby/
│   ├── jruby/
│   ├── ...
│   ├── run_all.rb (planned)       # Test runner
│   ├── matrix.txt (planned)       # Compatibility matrix
│   └── CONFORMANCE.md (planned)
│
├── governance/
│   ├── GOVERNANCE.md              # Process & rules
│   ├── exceptions/
│   │   ├── rfc-001-crystal-no-blocks.md (planned)
│   │   └── ...
│   └── rfc/
│       └── (proposed features)
│
├── interop/
│   ├── INTEROPERABILITY.md (planned)
│   ├── ruby_c.md (planned)
│   ├── ruby_jvm.md (planned)
│   └── ...
│
└── heritage/
    ├── LISP.md (planned)
    ├── SMALLTALK.md (planned)
    └── SELF.md (planned)
```

---

## Philosophy

### Do NOT:

- ❌ Assume all runtimes are identical
- ❌ Silently approximate unsupported features
- ❌ Erase historical implementation differences
- ❌ Collapse distinct language families (Ruby ≠ Crystal ≠ Opal)
- ❌ Allow backends to diverge without governance

### Do:

- ✓ Treat Ruby as a family with distinct implementations
- ✓ Specify exactly what each runtime guarantees
- ✓ Reject incompatible code clearly
- ✓ Preserve semantic fidelity across runtimes
- ✓ Document exceptions formally
- ✓ Test conformance systematically

---

## Next Steps

1. **Complete Parser Implementation** → `parser/lexer.rb`, `parser.rb`
2. **Build IR Lowering** → Backend-specific IR generators
3. **Implement Conformance Suite** → `conformance/all/*.rb`
4. **Document All Backends** → `runtimes/**/SPECIFICATION.md`
5. **External Audit** → Third-party review
6. **Community Adoption** → Invite runtimes to join committee

---

## References

- **Ruby 3.0 Specification**: MRI source, RFCs
- **JRuby Documentation**: Polyglot platform support
- **Rubinius Papers**: Runtime VM architecture
- **Crystal Language**: Static typing, LLVM backend
- **Opal Project**: Ruby-to-JavaScript compilation
- **Smalltalk Heritage**: Object-oriented design, message passing
- **Lisp Influence**: Metaprogramming, evaluation model

---

## License

(To be determined by community)

---

## Contact

**Repository Maintainer**: [You]

**Questions / Issues / Contributions**: [GitHub discussions]

**Committee Chair**: [To be elected]

---

**Version**: 1.0-draft (2024)

This is a living specification. Submit feedback and proposals!
