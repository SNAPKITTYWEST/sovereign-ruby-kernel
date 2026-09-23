# Governance & Compatibility Rules

## Purpose

Establish clear rules preventing backends from silently diverging from the specification and ensuring cross-runtime compatibility.

---

## Specification Authority

```
LANGUAGE SPECIFICATION
        │
        ├─ Approved by: Ruby Family Committee
        ├─ Review cycle: Annual or per major change
        └─ Versioned: Major.Minor (e.g., 2.7, 3.0)

FORMAL INVARIANTS
        │
        ├─ Legally binding for all backends
        ├─ Cannot be violated without explicit exception
        └─ Tested by conformance suite

BACKEND SPECIFICATIONS
        │
        ├─ Each backend documents its own semantics
        ├─ Must declare deviations from spec
        └─ Must pass conformance tests where applicable
```

---

## Conformance Levels

### Level 1: Core Compliance

A runtime **MUST**:

- ✓ Parse valid Ruby syntax without errors
- ✓ Produce results matching Language Specification
- ✓ Satisfy all Formal Invariants (except explicitly exempted)
- ✓ Provide error messages matching specification
- ✓ Not silently approximate unsupported features

### Level 2: Feature Completeness

A runtime **SHOULD**:

- ✓ Support all Ruby features (blocks, Fibers, threads, reflection, etc.)
- ✓ Provide equivalent performance characteristics
- ✓ Include comprehensive standard library

### Level 3: Optimization

A runtime **MAY**:

- ✓ Apply backend-specific optimizations (JIT, AOT, partial evaluation, etc.)
- ✓ Support platform-specific features (Java interop for JRuby, JS interop for Opal)
- ✓ Tune performance for specific workloads

---

## Exception Process

If a backend **cannot** satisfy an invariant:

### Step 1: Document the Exception

Create an RFC (Request for Comment) in the governance directory:

```
governance/exceptions/rfc-crystal-no-closures.md

Title: Crystal does not support closure capture by reference
RFC: 001
Backend: Crystal
Invariants Affected: I11, I8, I13
Reason: Static typing incompatible with dynamic closure capture
Workaround: Use compile-time capture (move semantics)
Status: APPROVED by Ruby Family Committee
Date: 2024-01-15
```

### Step 2: Update Specification

Annotate affected invariants:

```markdown
### I11: Closure Variable Capture

[EXCEPTION: Crystal does not support this invariant.
See governance/exceptions/rfc-001-crystal-no-closures.md]

Affected runtimes: Crystal
Workaround: Compile-time capture with move semantics
```

### Step 3: Reject at Parse Time

The backend **MUST** reject incompatible code with a clear error:

```ruby
# Crystal source
f = lambda { x }  # Error: closure capture not supported in Crystal

# Not this (silent approximation):
f = lambda { x }  # Compiles, but x is captured by value (wrong semantics)
```

### Step 4: Conformance Test

Add a test that verifies the rejection:

```ruby
# conformance/crystal/test_closure_rejection.cr
# This should fail to compile:
#
# f = lambda { x }
#
# Expected error:
# "Closure capture not supported (I11 exception)"
```

---

## Conformance Testing

### Test Organization

```
conformance/
├── all/                          # Tests all runtimes must pass
│   ├── object_model.rb
│   ├── method_dispatch.rb
│   ├── exceptions.rb
│   └── ... (one per invariant)
│
├── cruby/                        # CRuby-specific
│   ├── fibers.rb
│   └── c_extensions.rb
│
├── jruby/                        # JRuby-specific
│   ├── java_interop.rb
│   └── threads.rb
│
├── crystal/                      # Crystal-specific
│   ├── static_typing.rb
│   └── exception_list.rb
│
└── matrix.txt                    # Compatibility matrix
```

### Test Format

Every test identifies:

```ruby
# conformance/all/test_method_dispatch.rb
#
# Invariant: I4, I9 (Method lookup determinism)
# Runtimes: all
# Category: Method Dispatch
# Status: MANDATORY

describe "Method Dispatch" do
  it "resolves methods deterministically" do
    class C
      def foo; "from C"; end
    end

    class D < C; end

    obj = D.new
    obj.foo.should == "from C"
    obj.foo.should == "from C"  # Same result
  end

  it "follows ancestor chain" do
    module M
      def bar; "from M"; end
    end

    class E
      include M
    end

    E.new.bar.should == "from M"
  end
end
```

### Test Execution

```bash
# Run all tests for all runtimes
ruby conformance/run_all.rb

# Run subset for a specific runtime
ruby conformance/run_for.rb cruby

# Run a specific invariant
ruby conformance/run_invariant.rb I4

# Generate compatibility matrix
ruby conformance/generate_matrix.rb
```

### Compatibility Matrix

```
Invariant  │ CRuby │ JRuby │ Rubinius │ mruby │ TruffleRuby │ Crystal │ Opal │ Mirah
-----------|-------|-------|----------|-------|-------------|---------|------|-------
I1         │  ✓   │   ✓   │    ✓     │  ✓   │     ✓       │   ✓    │  ✓   │  ✓
I2         │  ✓   │   ✓   │    ✓     │  ✓   │     ✓       │   ✓    │  ✓   │  ✓
I3         │  ✓   │   ✓   │    ✓     │  ✓   │     ✓       │   ✓    │  ✓   │  ✗
...        │  ... │  ... │   ...    │ ... │    ...      │  ...   │ ... │ ...
I8         │  ✓   │   ✓   │    ✓     │  ✓   │     ✓       │   ✗*   │  ✓   │  ✗
I11        │  ✓   │   ✓   │    ✓     │  ✗   │     ✓       │   ✗*   │  ✓   │  ✗
...        │      │       │          │      │            │        │      │
Legend:    │  ✓ = Supported
           │  ✗ = Not supported, rejected at parse/compile
           │  * = Exception filed (see governance/exceptions/)
```

---

## Deviation Tracking

Every backend deviation is tracked:

```
runtimes/crystal/DEVIATIONS.md

# Crystal Deviations from Ruby Specification

## Unsupported Features

### Blocks and Procs (I8, I11, I13)
- Reason: Static typing incompatible with dynamic block capture
- Status: Deliberately rejected
- Workaround: Use function pointers or structs
- Test: conformance/crystal/test_no_blocks.cr

### Fibers (I28)
- Reason: No green-thread model; OS threads only
- Status: Not applicable to Crystal design
- Workaround: Use OS threads or async/await
- Test: conformance/crystal/test_no_fibers.cr

## Optimization Deviations

### Type Inference (I26)
- Crystal infers types at compile time
- Results in stricter checking than dynamic Ruby
- This is a feature, not a deviation
- Status: Approved

## Performance Characteristics

CRuby baseline (1.0x):
- Crystal: 10-100x faster (AOT compiled)
- JRuby: 0.8-2x (depends on warmup)
- Rubinius: 0.7-1.5x
- mruby: Highly variable (embedded)
```

---

## Version Management

### Semantic Versioning

```
MAJOR.MINOR.PATCH

2.7.0 → 3.0.0: Breaking changes allowed
2.7.0 → 2.8.0: New features, backward compatible
2.7.0 → 2.7.1: Bug fixes, no new features
```

### Deprecation Policy

```
Version N: Feature F works with deprecation warning
Version N+1: Feature F removed

Minimum 2 major versions of deprecation before removal.
```

### Backward Compatibility

```
New runtimes must support at least the previous spec version
(with explicit compatibility mode if needed).

Example: TruffleRuby 2.7 must support Ruby 2.7 spec,
ideally also 2.6 and 2.5 in compatibility modes.
```

---

## Committee Process

### Proposing Changes

1. **RFC**: Describe change in governance/rfc-*.md
2. **Discussion**: Comment period (2 weeks)
3. **Vote**: Committee votes (require 2/3 majority)
4. **Implementation**: Backends implement changes
5. **Release**: Included in next version

### Committee Members

- Ruby Family Specification Lead
- One representative per backend (CRuby, JRuby, Rubinius, mruby, TruffleRuby, Crystal, Opal, Mirah)
- Community representatives (elected)

### Voting Rules

```
Major changes (new features, invariants): 2/3 majority + chair approval
Minor changes (clarifications, bug fixes): Simple majority
Exception requests: 2/3 majority
```

---

## Publication & Review

### Specification Publication

```
ruby-family-stack/
├── spec/
│   ├── LANGUAGE_SPECIFICATION.md (current version)
│   ├── versions/
│   │   ├── 2.7.md
│   │   ├── 3.0.md
│   │   └── 3.1.md
│   └── CHANGELOG.md (all changes)
```

### Community Review

```
Quarterly review meetings (open to public)
GitHub discussions for issues/feedback
Annual external audit (3rd party expert review)
```

---

## Enforcement

### Compliance Checks

Every release must:

1. ✓ Pass all Level 1 conformance tests
2. ✓ Document any Level 2 gaps
3. ✓ Declare all exceptions formally
4. ✓ Pass external audit (annually)

### Non-Compliance

If a backend violates governance:

1. **Warning**: Public notice of violation
2. **Probation**: 1 release cycle to fix
3. **Delisting**: Removed from official compatibility matrix
4. **Reinstatement**: After compliance demonstrated for 2 releases

---

## Example: Adding a New Runtime

### Checklist

- [ ] Create `runtimes/{name}/SPECIFICATION.md`
- [ ] List all invariants (✓ supported or ✗ exception)
- [ ] File exceptions for unsupported invariants
- [ ] Implement conformance tests
- [ ] Pass external audit
- [ ] Join Ruby Family Committee (optional)
- [ ] Update compatibility matrix

### Timeline

- Week 1: Specification review
- Week 2-4: Implementation
- Week 5: Internal testing
- Week 6: External audit
- Week 7: Public release announcement
