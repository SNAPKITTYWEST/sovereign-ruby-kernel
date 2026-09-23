# Runtime Abstraction Layer

## Purpose

Each Ruby runtime has distinct architecture, optimization strategies, and capabilities. The abstraction layer defines:

1. **Common interface** for all runtimes
2. **Required capabilities** that every runtime must implement
3. **Optional optimizations** that runtimes may support
4. **Incompatibilities** that are explicitly documented

---

## Runtime Interface

Every runtime implements:

```prolog
runtime(Name).
version(Name, Version).
target_platform(Name, Platform).  % :native, :jvm, :javascript, :embedded
gc_strategy(Name, Strategy).       % :generational, :mark_sweep, :no_gc, :host
threading(Name, Model).            % :green_threads, :os_threads, :none
concurrency_primitives(Name, Primitives).
supported_features(Name, Features).
```

### Capabilities

```
capability(runtime, feature) :- (true | false).

Examples:
  capability(cruby, integer_optimization) :- true.
  capability(jruby, java_interop) :- true.
  capability(mruby, gc_disabled) :- true.
  capability(crystal, static_typing) :- true.
  capability(opal, browser_execution) :- true.
```

---

## CRuby Backend Specification

**Target**: Desktop/server, portable

### Architecture

```
Ruby Source
    │
    ▼
Parser (C)
    │
    ▼
YARV Bytecode
    │
    ▼
VM (C-based)
    │
    ├── Object heap
    ├── Method dispatch table
    ├── Inline caches
    ├── Garbage collector (Mark & Sweep)
    └── C function bindings
```

### Key Properties

- **Objects**: C structs (VALUE type)
- **Method dispatch**: Linear search, inline caches
- **GC**: Mark & Sweep with generations
- **Concurrency**: Green threads (Fiber) + OS threads (Thread)
- **FFI**: Native C extensions

### Unsupported / Limited Features

- **No static compilation**: Always interprets bytecode
- **Limited JIT**: Some optimizations, not full JIT
- **GC tuning**: Limited control over GC behavior

---

## JRuby Backend Specification

**Target**: JVM platforms

### Architecture

```
Ruby Source
    │
    ▼
Parser (Java)
    │
    ▼
Ruby AST
    │
    ▼
JVM bytecode
    │
    ▼
HotSpot JVM
    │
    ├── Java objects
    ├── Method dispatch
    ├── JIT compilation
    ├── Java interop
    └── JVM GC
```

### Key Properties

- **Objects**: Java classes wrapping Ruby values
- **Method dispatch**: Java reflection + inline caches
- **GC**: Delegated to JVM (concurrent mark-sweep)
- **Concurrency**: OS threads (Java threads)
- **FFI**: Java method calls, Ruby-Java bridge

### Unique Features

- **Java interop**: Can call Java classes/methods directly
- **JIT compilation**: HotSpot compiles hot code
- **Garbage collection**: Transparent JVM GC

### Limitations

- **Startup time**: JVM startup overhead
- **Memory footprint**: JVM base memory
- **Reflection overhead**: Some operations slower than CRuby

---

## Rubinius Backend Specification

**Target**: Desktop/server, experimental

### Architecture

```
Ruby Source
    │
    ▼
Parser (Ruby)
    │
    ▼
Rubinius Bytecode
    │
    ▼
Rubinius VM (C++)
    │
    ├── Object space
    ├── Inline caches
    ├── Method dispatch
    └── GC
```

### Key Properties

- **Objects**: Rubinius object model
- **Method dispatch**: Inline caches with first-class functions
- **GC**: Generational garbage collection
- **Runtime**: Largely written in Ruby (bootstrapped)
- **Flexibility**: Easier to modify and extend

### Unique Features

- **Introspective**: Runtime is inspectable/modifiable
- **Bytecode compiler**: Can inspect/modify bytecode
- **Flexible GC**: Can tune GC parameters

---

## mruby Backend Specification

**Target**: Embedded systems, IoT, constrained environments

### Architecture

```
Ruby Source
    │
    ▼
Parser (C)
    │
    ▼
mruby Bytecode
    │
    ▼
mruby VM (C)
    │
    ├── Fixed object heap
    ├── Simple dispatch
    ├── No GC (or minimal GC)
    └── Host integration
```

### Key Constraints

- **Memory**: Fixed heap size (typically < 1 MB)
- **Code size**: Small runtime library
- **Dependencies**: Minimal external dependencies
- **Startup**: Deterministic, fast startup
- **Garbage collection**: Optional or disabled

### Unique Features

- **Embeddable**: Can be linked into C/C++ projects
- **Host FFI**: Direct C function binding
- **Lightweight**: No runtime overhead

### Limitations

- **Features**: Subset of Ruby (no Fibers, limited reflection)
- **Performance**: No JIT, no advanced optimizations
- **Concurrency**: No threads (by default)

---

## TruffleRuby Backend Specification

**Target**: GraalVM polyglot platform

### Architecture

```
Ruby Source
    │
    ▼
Parser (Java)
    │
    ▼
Truffle AST
    │
    ▼
Partial evaluation / specialization
    │
    ▼
Graal Compiler
    │
    ▼
Native code
```

### Key Properties

- **JIT**: Graal compiler specializes code based on types
- **Polyglot**: Can interop with JavaScript, Python, etc. via Polyglot API
- **Performance**: Often faster than CRuby for CPU-bound code
- **GC**: GraalVM managed (similar to JVM)

### Unique Features

- **Polymorphic dispatch**: Inline caches specialize on receiver type
- **Partial evaluation**: Specializes code to call sites
- **Polyglot interop**: Seamless calls across languages
- **Low latency**: No pause-the-world GC

---

## Crystal Backend Specification

**Target**: Native compilation (LLVM), static typing

### Architecture

```
Crystal Source
    │
    ▼
Parser (Crystal)
    │
    ▼
Type-checked AST
    │
    ▼
LLVM IR
    │
    ▼
Native machine code
    │
    ▼
Statically linked binary
```

### Key Differences from Ruby

- **Static typing**: Types inferred or declared
- **No dynamic dispatch**: Virtual methods resolved at compile time
- **Compiled**: AOT compiled to native code
- **GC**: Deterministic or no GC
- **Runtime**: Minimal runtime library
- **Performance**: Similar to C/C++

### Compatibility Notes

- Crystal is **not** 100% Ruby compatible
- Some Ruby features cannot be expressed in Crystal (e.g., `eval`, `define_method` at runtime)
- Crystal code reads like Ruby but compiles differently

---

## Opal Backend Specification

**Target**: Browser execution via JavaScript

### Architecture

```
Ruby Source
    │
    ▼
Parser (Ruby/JavaScript)
    │
    ▼
JavaScript AST
    │
    ▼
JavaScript code
    │
    ▼
Browser execution
```

### Key Properties

- **Target platform**: Web browser + Node.js
- **Object model**: Ruby objects implemented as JavaScript objects
- **Method dispatch**: JavaScript method calls
- **GC**: Delegated to JavaScript engine
- **Interop**: Can call JavaScript functions

### Ruby-to-JavaScript Mapping

```
Ruby Array       → JavaScript Array
Ruby Hash        → JavaScript Object / Map
Ruby String      → JavaScript String
Ruby Proc        → JavaScript Function
Ruby method_call → JavaScript function call
Ruby Symbol      → JavaScript Symbol (or interned string)
```

### Limitations

- **File I/O**: Cannot write to filesystem
- **Threads**: Cannot be implemented (JavaScript is single-threaded)
- **C extensions**: Cannot load native code
- **Reflection**: Some reflection operations slower due to JS overhead

---

## Mirah Backend Specification

**Target**: JVM, statically typed

### Architecture

```
Mirah Source
    │
    ▼
Type-checked Parser
    │
    ▼
Typed AST
    │
    ▼
JVM bytecode
    │
    ▼
JVM execution
```

### Key Properties

- **Static typing**: Explicit type annotations
- **JVM target**: Compiles to JVM bytecode
- **Ruby-like syntax**: Familiar to Ruby developers
- **Java interop**: Direct Java class/method access
- **No runtime overhead**: Static dispatch

### Differences from Ruby

- Types must be declared or strongly inferred
- No `eval` or late binding
- Method dispatch is static (no `method_missing`)
- No blocks (functions used instead)

---

## Runtime Comparison Matrix

| Feature | CRuby | JRuby | Rubinius | mruby | TruffleRuby | Crystal | Opal | Mirah |
|---------|-------|-------|----------|-------|-------------|---------|------|-------|
| **Execution** | Interpreted | JVM | Interpreted | Interpreted | JIT | AOT compiled | JS | JVM compiled |
| **Performance** | Baseline | Good | Good | Poor | Excellent | Excellent | Variable | Excellent |
| **Startup** | Fast | Slow | Fast | Very Fast | Slow | Very Fast | Fast | Fast |
| **Memory** | Moderate | High | Moderate | Very Low | High | Low | Low | Moderate |
| **JIT** | Basic | HotSpot | None | None | Graal | N/A | Engine | N/A |
| **GC** | Generational | Concurrent | Generational | None | Concurrent | Manual | JS engine | GC |
| **Threads** | Green + OS | OS | Green + OS | None | OS | None | None | OS |
| **Concurrency** | Good | Excellent | Good | None | Excellent | Limited | None | Good |
| **Static typing** | No | No | No | No | No | Yes | No | Yes |
| **Java interop** | FFI | Native | No | FFI | Polyglot | No | No | Native |
| **C extensions** | Yes | Yes | Yes | Yes | Limited | No | No | No |
| **Embedded** | No | No | No | **Yes** | No | Possible | Yes | No |
| **Web target** | No | No | No | No | No | No | **Yes** | No |

---

## Fallback & Compatibility

When a runtime doesn't support a feature:

```
Option 1: Reject at parse/compile time with clear error
Option 2: Fall back to slower implementation (documented)
Option 3: Provide limited approximation (marked in spec)
```

Never silently approximate.

---

## Next Steps

Each runtime will have a detailed backend specification:

- `runtimes/cruby/SPECIFICATION.md`
- `runtimes/jruby/SPECIFICATION.md`
- `runtimes/rubinius/SPECIFICATION.md`
- `runtimes/mruby/SPECIFICATION.md`
- `runtimes/truffleruby/SPECIFICATION.md`
- `languages/crystal/SPECIFICATION.md`
- `languages/opal/SPECIFICATION.md`
- `languages/mirah/SPECIFICATION.md`
