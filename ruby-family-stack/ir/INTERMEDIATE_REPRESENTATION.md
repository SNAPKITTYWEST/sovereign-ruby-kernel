# Intermediate Representation (IR)

## Design Principles

1. **Runtime-agnostic**: IR does not assume a specific VM architecture
2. **Explicit semantics**: Method dispatch, control flow, exceptions all explicit
3. **Analyzable**: IR can be inspected, transformed, verified
4. **Compilable**: Each backend can generate native code from IR
5. **Reversible**: Source locations preserved for debugging

---

## Core IR Nodes

### Program

```
Program {
  definitions: Definition[]
  global_statements: Instruction[]
}
```

### Definition

```
MethodDef {
  name: Symbol
  arity: Integer | Range
  parameters: Parameter[]
  body: Block
  receiver_type: Type  # e.g., instance method on class C
  visibility: :public | :private | :protected
}

ClassDef {
  name: Symbol
  parent_class: Symbol | nil
  body: Block
  constants: Binding[]
}

ModuleDef {
  name: Symbol
  body: Block
  constants: Binding[]
}
```

### Instruction

Base class for all IR instructions. Each has:

```
{
  id: Integer          # Unique within function
  line: Integer        # Source line
  column: Integer      # Source column
  next_instruction: Instruction | nil
  exception_edges: Instruction[]  # Exception handler destinations
}
```

### Control Flow Instructions

```
Block {
  instructions: Instruction[]
}

If {
  condition: Value
  then_block: Block
  else_block: Block | nil
}

Case {
  value: Value | nil
  cases: { pattern: Pattern, block: Block }[]
  default_block: Block | nil
}

While {
  condition: Value
  body: Block
}

For {
  variable: Local
  collection: Value
  body: Block
}

Break {
  value: Value | nil
}

Next {
  value: Value | nil
}

Return {
  value: Value | nil
}
```

### Method Call

```
MethodCall {
  receiver: Value
  selector: Symbol
  arguments: Argument[]
  block: Block | nil
}

Argument {
  value: Value
  keyword: Symbol | nil  # For keyword arguments
}
```

### Object Allocation

```
ClassAlloc {
  class_constant: Symbol
  field_initializers: { field: Symbol, value: Value }[]
}

ArrayAlloc {
  elements: Value[]
}

HashAlloc {
  pairs: { key: Value, value: Value }[]
}

StringAlloc {
  value: String | InterpolatedString[]
}

SymbolAlloc {
  value: Symbol
}
```

### Variable Operations

```
Local {
  name: Symbol
}

InstanceVar {
  name: Symbol
}

ClassVar {
  name: Symbol
}

GlobalVar {
  name: Symbol
}

Constant {
  name: Symbol
}

Assign {
  target: Local | InstanceVar | ClassVar | GlobalVar | Constant | Subscript
  value: Value
}
```

### Field Access

```
FieldGet {
  object: Value
  field: Symbol
}

FieldSet {
  object: Value
  field: Symbol
  value: Value
}

Subscript {
  object: Value
  index: Value
}

SubscriptAssign {
  object: Value
  index: Value
  value: Value
}
```

### Reflection

```
Send {
  receiver: Value
  selector: Value  # Dynamic method name
  arguments: Value[]
  block: Block | nil
}

Respond {
  object: Value
  selector: Symbol
}

InstanceVarGet {
  object: Value
  name: Symbol
}

MethodGet {
  object: Value
  name: Symbol
}

ClassGet {
  object: Value
}
```

### Exception Handling

```
BeginRescue {
  body: Block
  rescues: {
    exception_types: Symbol[]
    variable: Local | nil
    handler: Block
  }[]
  else_block: Block | nil
  ensure_block: Block | nil
}

Raise {
  exception: Value | nil
}
```

### Literals

```
IntegerLiteral {
  value: BigInt
}

FloatLiteral {
  value: Float64
}

BooleanLiteral {
  value: Boolean
}

NilLiteral {
}

StringLiteral {
  value: String
}

SymbolLiteral {
  value: Symbol
}

RangeLiteral {
  start: Value
  end: Value
  exclusive: Boolean
}

RegexLiteral {
  pattern: String
  flags: String
}
```

### Binary & Unary Operations

```
BinaryOp {
  operator: Symbol  # :+, :-, :*, :/, :%, :**, :==, :!=, :<, :>, :<=, :>=, :<=>
  left: Value
  right: Value
}

UnaryOp {
  operator: Symbol  # :-, :+, :!, :~, :+@
  operand: Value
}
```

---

## Value Types

All IR values are one of:

```
Value := Literal
       | Local
       | InstanceVar
       | ClassVar
       | GlobalVar
       | Constant
       | MethodCall result
       | BinaryOp result
       | UnaryOp result
       | ObjectAllocation
       | Subscript result
       | FieldGet result
       | Lambda result
```

---

## Control Flow Graph

Every function is a directed graph:

```
Node := Block | If | While | For | Case | Try/Catch

Edge := conditional | unconditional | exception
```

**Property**: CFG is computable from IR for analysis and optimization.

---

## Example: Factorial

```ruby
def factorial(n)
  if n <= 1
    1
  else
    n * factorial(n - 1)
  end
end
```

IR:

```
MethodDef {
  name: :factorial
  arity: 1
  parameters: [Parameter(name: :n)]
  body: Block {
    instructions: [
      If {
        condition: BinaryOp(
          left: Local(:n),
          operator: :<=,
          right: IntegerLiteral(1)
        ),
        then_block: Block {
          instructions: [
            Return(IntegerLiteral(1))
          ]
        },
        else_block: Block {
          instructions: [
            Return(BinaryOp(
              left: Local(:n),
              operator: :*,
              right: MethodCall(
                receiver: Constant(:Kernel),
                selector: :factorial,
                arguments: [
                  BinaryOp(
                    left: Local(:n),
                    operator: :-,
                    right: IntegerLiteral(1)
                  )
                ]
              )
            ))
          ]
        }
      }
    ]
  }
}
```

---

## Type Annotations (Optional)

IR may include type information for backends that use it:

```
TypedValue := Value : Type

Type := :object
      | :integer
      | :float
      | :string
      | :symbol
      | :array
      | :hash
      | :proc
      | :true | :false | :nil
      | Class(name)
      | Union(Type, Type, ...)
      | Function(args: Type[], return: Type)
```

Crystal and Mirah will populate these; CRuby/JRuby/Rubinius treat them as optional annotations.

---

## SSA Form (Optional)

For optimization-heavy backends, IR can be converted to SSA:

```
v0 = IntegerLiteral(5)
v1 = Local(:n)
v2 = BinaryOp(left: v1, operator: :+, right: v0)
Return(v2)
```

Advantage: Easier dataflow analysis.

---

## Backend Lowering

Each backend implements:

```
lower_ir(ir: IR): BackendCode

CRuby: IR → YARV bytecode
JRuby: IR → JVM bytecode
Rubinius: IR → Rubinius bytecode
mruby: IR → mruby bytecode
TruffleRuby: IR → Truffle AST nodes
Crystal: IR → LLVM IR
Opal: IR → JavaScript AST
Mirah: IR → JVM bytecode
```

---

## Invariants

**Invariant IR1**: Every MethodCall has a well-defined receiver.

**Invariant IR2**: All locals must be defined before use (within dominance frontier).

**Invariant IR3**: Return instructions only appear at method boundaries.

**Invariant IR4**: Exception edges form a DAG (no cycles).

**Invariant IR5**: All values have deterministic types (Union types permitted).

---

## Optimization Passes (Optional)

IR can be transformed through:

```
Constant folding → Literal values replace computed operations
Dead code elimination → Unused assignments removed
Inlining → Small methods inlined into callers
Loop unrolling → Loops with fixed counts unrolled
Common subexpression elimination → Repeated ops shared
Escape analysis → Stack allocation vs heap
```

Each pass must preserve semantics per Language Specification.
