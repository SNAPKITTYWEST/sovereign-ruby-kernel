# Ruby Language Specification

## 1. Object Model

### Core Concepts

```
BasicObject (root)
    └── Object
        ├── Class
        ├── Module
        ├── String
        ├── Array
        ├── Hash
        ├── Symbol
        ├── Numeric
        │   ├── Integer
        │   └── Float
        ├── Proc
        ├── Method
        ├── Exception
        └── ... (user-defined classes)
```

### Object Identity

Every object has:

- **Identity**: Unique within runtime, comparable via `equal?` / `object_id`
- **Class**: Determines method lookup and behavior
- **State**: Instance variables (`@var`)
- **Singleton class**: Unique class for singleton methods

**Invariant I1**: `object.class.is_a?(Class)` → true

### Class Hierarchy

```prolog
class(C) :-
    is_a(C, Class),
    (C = BasicObject ; ancestor(C, BasicObject)).

ancestor(C, A) :-
    parent(C, A) ;
    (parent(C, P), ancestor(P, A)).

method_lookup(Object, Selector, Method) :-
    class(C, Object),
    lookup_in_class(C, Selector, Method).

lookup_in_class(C, Selector, Method) :-
    defines_method(C, Selector, Method) ;
    (included_module(C, M), defines_method(M, Selector, Method)) ;
    (parent(C, P), lookup_in_class(P, Selector, Method)).
```

### Singleton Classes

Every object may have methods defined on its singleton class:

```ruby
obj = Object.new
def obj.foo; "unique to this object"; end

obj.singleton_class  # → #<Class:#<Object:0x...>>
obj.singleton_methods  # → [:foo]
```

**Invariant I2**: Singleton methods shadow class methods in lookup order.

### Modules

```ruby
module M
  def foo; "from module"; end
end

class C
  include M  # M's methods become instance methods
end

C.ancestors  # → [C, M, Object, BasicObject]
```

Modules provide:
- Method inclusion (instance methods)
- Extension (singleton methods via `extend`)
- Namespacing
- Mixins

**Invariant I3**: Included modules appear in ancestor chain before parent class.

---

## 2. Method Dispatch

### Method Call Semantics

```
CALL: receiver.method(args, &block)
  │
  ├─ Resolve receiver
  ├─ Resolve selector (method name / symbol)
  ├─ Collect arguments
  ├─ Look up method in class hierarchy
  ├─ Bind block (if present)
  ├─ Execute with self=receiver
  └─ Return result or raise exception
```

### Lookup Order

```
1. Singleton methods on receiver
2. Singleton class hierarchy
3. Class of receiver
4. Included modules (in reverse inclusion order)
5. Parent class (recursively)
6. method_missing (if defined)
7. NoMethodError
```

**Invariant I4**: Method lookup terminates in BasicObject or raises NoMethodError.

### Visibility

```ruby
class C
  def public_method; end
  private
  def private_method; end
  protected
  def protected_method; end
end
```

- **public**: Callable from anywhere
- **private**: Callable without explicit receiver (only via implicit `self`)
- **protected**: Callable within defining class or subclasses

**Invariant I5**: Private methods reject explicit receivers other than `self`.

---

## 3. Blocks, Procs, and Closures

### Block Semantics

A block is an anonymous code body with captured bindings:

```ruby
def iterate(arr)
  arr.each { |item| yield item }
end

iterate([1, 2, 3]) { |x| puts x }
```

Blocks:
- Capture lexical environment (closure)
- Accept parameters
- Yield to via `yield` or `block_given?`
- Convert to Proc via `&block`

### Proc vs Lambda

```ruby
p = Proc.new { |x| return x * 2 }
l = lambda { |x| return x * 2 }
```

Differences:

| Feature | Proc | Lambda |
|---------|------|--------|
| `return` | Returns from enclosing method | Returns from proc |
| Arity | Flexible | Strict |
| `[]` vs `call` | Both work | Both work |

**Invariant I6**: `lambda.arity` must match argument count; `Proc.new` is flexible.

### Closures

A closure captures its defining environment:

```ruby
x = 10
f = lambda { x }
f.call  # → 10
x = 20
f.call  # → 20 (x is shared by reference)
```

**Invariant I7**: Closure variables are bound by reference, not value.

---

## 4. Strings and Symbols

### String Semantics

```ruby
s = "hello"
s.class  # → String
s[0]     # → "h"
s + " world"  # → "hello world"
"#{x}"   # Interpolation: evaluates x, calls to_s, inserts result
```

Strings are mutable, distinct objects:

```ruby
"a" == "a"    # → true
"a".equal?("a")  # → false (different objects)
```

**Invariant I8**: String identity and equality follow object identity semantics.

### Symbol Semantics

```ruby
:symbol.class  # → Symbol
:a == :a       # → true
:a.equal?(:a)  # → true (same symbol, always)
:a.to_s        # → "a"
"a".to_sym     # → :a
```

Symbols are interned globally—all `:a` refer to the same object.

**Invariant I9**: Symbol identity is global and immutable.

---

## 5. Collections

### Array

```ruby
a = [1, 2, 3]
a[0]   # → 1
a << 4  # → [1, 2, 3, 4]
a.each { |x| puts x }
```

Arrays are ordered, mutable, heterogeneous.

### Hash

```ruby
h = { a: 1, b: 2 }
h[:a]  # → 1
h[:c] = 3
```

Hashes are unordered (or insertion-ordered in modern Ruby), mutable, key-value stores.

### Range

```ruby
(1..10)   # Inclusive: 1 to 10
(1...10)  # Exclusive: 1 to 9
('a'..'z')  # String range
```

---

## 6. Exceptions

### Exception Hierarchy

```
Exception
 ├── StandardError
 │   ├── ArgumentError
 │   ├── RuntimeError
 │   ├── TypeError
 │   ├── NameError
 │   ├── NoMethodError
 │   └── ...
 └── SystemStackError, SignalException, ...
```

### Exception Handling

```ruby
begin
  # code that may raise
rescue SpecificError => e
  # handle
ensure
  # always run
end
```

**Invariant I10**: Exception handler type matching follows class hierarchy.

---

## 7. Reflection & Metaprogramming

### Object Introspection

```ruby
obj.class              # Class of object
obj.methods            # Instance methods accessible
obj.instance_variables # @vars defined on obj
obj.respond_to?(:foo)  # Can obj handle message :foo?
```

### Class Introspection

```ruby
String.instance_methods
String.ancestors
String.instance_method(:upcase)
```

### Dynamic Definition

```ruby
define_method(:foo) { "dynamic" }
attr_accessor :x
alias_method :new_name, :old_name
send(:method_name, args)
```

---

## 8. Numeric Semantics

### Integer vs Float

```ruby
1 + 2      # → 3 (Integer)
1 + 2.0    # → 3.0 (Float)
1 / 2      # → 0 (Integer division)
1.0 / 2    # → 0.5 (Float division)
```

**Invariant I11**: Integer division truncates; Float division is exact (within IEEE 754).

### Numeric Coercion

```ruby
1 <=> 2    # → -1
1.0 <=> 2.0  # → -1
1 <=> 2.0  # Numeric coercion occurs
```

---

## 9. Variable Scoping

### Local Variables

```ruby
x = 1      # Local to method/block scope
```

### Instance Variables

```ruby
@x = 1     # Instance variable on self
```

### Class Variables

```ruby
@@x = 1    # Shared across class and subclasses (warning: inheritance issues)
```

### Global Variables

```ruby
$x = 1     # Global scope (use sparingly)
```

### Constants

```ruby
CONST = 1  # Constant (can be reassigned with warning)
```

**Invariant I12**: Variable scoping follows lexical rules except for class variables (which follow inheritance).

---

## 10. Control Flow

### Conditionals

```ruby
if condition
  # ...
elsif condition2
  # ...
else
  # ...
end

case x
when 1, 2
  # ...
when 3..5
  # ...
else
  # ...
end
```

### Loops

```ruby
while condition
  # ...
end

until condition
  # ...
end

loop { # ... }

for x in collection
  # ...
end
```

### Iterators

```ruby
[1, 2, 3].each { |x| puts x }
[1, 2, 3].map { |x| x * 2 }
[1, 2, 3].select { |x| x > 1 }
```

---

## 11. Formal Invariants Summary

| ID | Invariant | Scope |
|----|-----------|-------|
| I1 | Every object has a class that is an instance of Class | All |
| I2 | Singleton methods shadow class methods in lookup | All |
| I3 | Included modules appear before parent in ancestor chain | All |
| I4 | Method lookup terminates in BasicObject or NoMethodError | All |
| I5 | Private methods reject explicit receivers except self | All |
| I6 | Lambda arity is strict; Proc arity is flexible | All |
| I7 | Closure variables are bound by reference | All |
| I8 | String identity and equality follow object semantics | All |
| I9 | Symbol identity is global and immutable | All |
| I10 | Exception handler type matching follows class hierarchy | All |
| I11 | Integer division truncates; Float division is precise | Numeric |
| I12 | Variable scoping is lexical (except class variables) | Scope |

---

## Non-Normative Notes

This specification defines *what* Ruby semantics are, not *how* any particular runtime implements them. Each backend (CRuby, JRuby, etc.) may optimize, but must preserve these invariants.
