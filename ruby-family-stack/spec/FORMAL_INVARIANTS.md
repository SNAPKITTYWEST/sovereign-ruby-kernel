# Formal Invariants

These invariants define correctness across all Ruby implementations. Every backend must preserve them.

---

## Object Model Invariants

### I1: Object Identity
```
Every object has a unique identity in its runtime.

∀ runtime R, ∀ obj1, obj2 ∈ Object(R):
  obj1.object_id ≠ obj2.object_id  ∨  obj1 ≡ obj2

Proof: object_id is the primitive identity predicate; distinct objects
have distinct IDs by definition.
```

### I2: Class Relationship
```
Every object is an instance of exactly one class.

∀ obj ∈ Object:
  ∃! C ∈ Class: obj.class = C

Additionally, obj must be an instance of all ancestors of C:
  ∀ A ∈ ancestors(obj.class): obj.is_a?(A)
```

### I3: Singleton Class Uniqueness
```
Each object has exactly one singleton class, which is unique to that object.

∀ obj1, obj2 ∈ Object, obj1 ≠ obj2:
  obj1.singleton_class ≠ obj2.singleton_class
```

### I4: Method Lookup Determinism
```
Method lookup is deterministic: given receiver and selector,
method resolution always returns the same method.

∀ receiver, selector:
  lookup(receiver, selector) = m1
  ∧ lookup(receiver, selector) = m2
  → m1 ≡ m2
```

### I5: Ancestor Chain Consistency
```
The ancestor chain of a class is a total order (list) with no cycles.

∀ C ∈ Class:
  ancestors(C) = [C, M1, M2, ..., BasicObject]
  ∧ ¬∃ cycle in included_modules(C)
```

### I6: Visibility Enforcement
```
Private methods cannot be called with an explicit receiver.

∀ receiver, obj:
  visibility(method) = private
  ∧ receiver ≠ obj
  → method_call(receiver, method) raises NoMethodError
```

---

## Method Dispatch Invariants

### I7: Dynamic Dispatch
```
Method selection at runtime is based on the receiver's class at call time,
not the compile-time type.

def foo(x)
  x.message  # Which message? Determined at runtime.
end

foo("string")  # String#message
foo(exception)  # Exception#message
```

### I8: Block Binding
```
Blocks capture their lexical environment and are available to the called method.

def iterate(&block)
  yield 1, 2, 3
end

x = 10
iterate { |a, b| a + b + x }  # Block captures x=10

Captured bindings are by reference, not copy:

x = 10
f = lambda { x }
x = 20
f.call  # => 20 (x changed after capture)
```

### I9: Method Resolution Order (MRO)
```
Method resolution follows the ancestor chain in order.

For class C with ancestors [C, M1, M2, Parent, Object, BasicObject]:
  1. Check singleton methods on receiver
  2. Check C's instance methods
  3. Check M1's methods
  4. Check M2's methods
  5. Check Parent's methods (recursively)
  6. Check Object/BasicObject
  7. Call method_missing if defined

This order is consistent across runtimes.
```

### I10: method_missing Fallback
```
If no method is found and method_missing is defined, method_missing is called.

lookup(obj, selector) = not_found
∧ method_missing_defined?(obj.class)
→ method_missing(obj, selector, *args, &block) is invoked
```

---

## Closure and Binding Invariants

### I11: Closure Variable Capture
```
Variables in a closure are captured by reference, not value.

x = 1
f = lambda { x }
x = 2
f.call  # => 2 (not 1)

Proof: The lambda's environment holds a reference to the binding,
not a copy of the value.
```

### I12: Proc vs Lambda Semantics
```
Proc and lambda differ in arity checking and return semantics:

proc arity: Flexible (missing args default to nil, extra args ignored)
lambda arity: Strict (must match parameter count exactly)

proc return: Returns from enclosing method
lambda return: Returns from lambda only

∀ p ∈ Proc, λ ∈ Lambda:
  λ.arity must match parameter count
  p.arity is flexible
```

### I13: Block Scope
```
Block parameters shadow outer scope variables.

x = 1
[10, 20].each { |x| puts x }  # Prints 10, 20
puts x  # => 1 (outer x unchanged)

Block params shadow outer bindings in the block's scope.
```

---

## Exception Handling Invariants

### I14: Exception Type Matching
```
Exception handlers match by class hierarchy.

begin
  raise SpecificError.new
rescue ParentError => e
  # Caught if SpecificError <= ParentError
end
```

### I15: Ensure Block Execution
```
Ensure blocks always execute, even when control exits via return or exception.

def foo
  begin
    return 1
  ensure
    puts "ensure runs"  # Always printed
  end
end
```

### I16: Exception Propagation
```
Unhandled exceptions propagate up the call stack.

def inner
  raise "error"
end

def outer
  inner  # Exception propagates out
end

outer  # Unhandled exception terminates execution
```

---

## Variable Scoping Invariants

### I17: Local Variable Scope
```
Local variables are lexically scoped. Once defined, they cannot be undefined.

x = 1        # x is now in scope
x = 2        # Rebind
# No way to "undefine" x

Local variables are shadowed by block parameters:

x = 1
lambda { |x| x = 2 }  # Block param shadows
x  # Still 1
```

### I18: Instance Variable Binding
```
Instance variables are bound to self (the object).

class C
  def set_x(val)
    @x = val
  end
end

obj = C.new
obj.set_x(42)
obj.instance_variable_get(:@x)  # => 42
```

### I19: Global and Class Variables
```
Global variables are global scope.
Class variables are shared across a class and its subclasses.

$global = 1  # Accessible anywhere
@@class_var  # Shared in class hierarchy
```

---

## Numeric Invariants

### I20: Integer vs Float Division
```
Integer division truncates toward negative infinity.
Float division returns exact IEEE 754 result.

1 / 2  # => 0 (Integer division)
1.0 / 2  # => 0.5 (Float division)
-1 / 2  # => -1 (truncates toward -∞)
```

### I21: Numeric Coercion
```
Binary operations coerce operands as needed.

1 + 2  # => 3 (Integer)
1 + 2.0  # => 3.0 (Float, coerced)
Integer + Float → Float
Float + Rational → Rational (if available)
```

---

## String and Symbol Invariants

### I22: String Mutable, Symbol Immutable
```
Strings are mutable, distinct objects:

"a" == "a"  # true (equal)
"a".equal?("a")  # false (different objects)

Symbols are immutable and interned globally:

:a == :a  # true
:a.equal?(:a)  # true (same object)
```

### I23: String Interpolation Evaluation
```
String interpolation evaluates expressions at runtime.

x = 10
"x = #{x}"  # => "x = 10"

Changing x after interpolation does not change the string:

x = 10
s = "x = #{x}"
x = 20
s  # Still "x = 10"
```

---

## Reflection Invariants

### I24: Reflection Consistency
```
Reflection operations accurately represent runtime state.

C.instance_methods  # Lists methods actually callable
obj.methods  # Lists methods callable on obj
obj.respond_to?(:foo)  # true iff obj can handle :foo
```

### I25: method_missing Interception
```
method_missing can intercept and handle undefined method calls.

class C
  def method_missing(name, *args)
    "called #{name}"
  end
end

C.new.foo(1, 2)  # => "called foo"
```

---

## Type System Invariants (for static backends)

### I26: Static Type Soundness (Crystal, Mirah)
```
Static type checkers guarantee type safety at compile time.

If a value is declared as type T and operations are valid for T,
then runtime type errors cannot occur.

∀ program P, ∀ T ∈ Type(P):
  type_check(P, T) = ✓
  → No TypeError at runtime from operations on T
```

---

## Concurrency Invariants

### I27: Thread Safety of Builtins
```
Built-in classes are thread-safe for immutable operations.

Multiple threads can read the same String/Array/Hash concurrently,
but concurrent writes must be synchronized by the user.

∀ obj ∈ {String, Symbol, Integer, ...} (immutable):
  concurrent_read(obj) is safe
```

### I28: Fiber vs Thread Semantics
```
Fibers (CRuby) and OS threads (other runtimes) have different scheduling.

Fibers: Cooperative multitasking, controlled yields
OS threads: Preemptive, may be interrupted at any point

Semantics differ but must not expose data races in synchronized code.
```

---

## Invariant Verification

Each backend must pass conformance tests verifying:

```
Test suite organized by invariant:

test/invariant_i1_object_identity.rb
test/invariant_i2_class_relationship.rb
test/invariant_i3_singleton_class.rb
... (one per invariant)

Pass criteria:
  ✓ All runs produce same result
  ✓ All runtimes agree on output
  ✓ No exceptions unless specified
```

---

## Invariant Violations

If a backend cannot satisfy an invariant:

1. **Document explicitly** in backend specification
2. **Provide evidence** (e.g., Crystal doesn't support I8 block binding → no blocks)
3. **Suggest workaround** if possible
4. **Reject incompatible code** at compile/parse time (don't silently approximate)

**Example**: Crystal cannot satisfy I11 (closure capture by reference) due to static typing. This is documented and rejected at compile time if attempted.

---

## Summary

| ID | Invariant | Scope |
|----|-----------|-------|
| I1 | Object Identity | All |
| I2 | Class Relationship | All |
| I3 | Singleton Class Uniqueness | All |
| I4 | Method Lookup Determinism | All |
| I5 | Ancestor Chain Consistency | All |
| I6 | Visibility Enforcement | All |
| I7 | Dynamic Dispatch | All |
| I8 | Block Binding | Dynamic runtimes |
| I9 | MRO | All |
| I10 | method_missing Fallback | All |
| I11 | Closure Capture by Reference | Dynamic runtimes |
| I12 | Proc vs Lambda | All |
| I13 | Block Scope Shadowing | All |
| I14 | Exception Type Matching | All |
| I15 | Ensure Execution | All |
| I16 | Exception Propagation | All |
| I17 | Local Variable Scope | All |
| I18 | Instance Variable Binding | All |
| I19 | Global/Class Variable Scope | All |
| I20 | Integer vs Float Division | All |
| I21 | Numeric Coercion | All |
| I22 | String/Symbol Mutability | All |
| I23 | String Interpolation Evaluation | All |
| I24 | Reflection Consistency | All |
| I25 | method_missing Interception | All |
| I26 | Static Type Soundness | Static runtimes |
| I27 | Thread-safe Builtins | All |
| I28 | Fiber vs Thread Semantics | CRuby + others |
