# Parser Architecture

## Design

```
SOURCE CODE
    │
    ▼
LEXER (lexical analysis)
    │ (tokens)
    ▼
PARSER (syntactic analysis)
    │ (parse tree)
    ▼
AST BUILDER (semantic cleanup)
    │ (normalized AST)
    ▼
NORMALIZED AST
    │
    ▼
IR GENERATOR (backend-independent)
    │
    ▼
INTERMEDIATE REPRESENTATION
```

## Phase 1: Lexer

Tokenizes Ruby source into a stream.

### Token Types

```
KEYWORD: def, class, module, if, unless, elsif, else, case, when,
         while, until, for, in, do, end, return, yield, break,
         next, redo, retry, begin, rescue, ensure, raise, and,
         or, not, true, false, nil, self, super, lambda, proc

IDENTIFIER: alphanumeric_*, $global, @instance, @@class, CONST

OPERATOR: +, -, *, /, %, **, ==, !=, <, >, <=, >=, <=>, =~, !~,
          &, |, ^, ~, <<, >>, &&, ||, !, ?, :, =, +=, -=, *=, /=,
          %=, **=, &=, |=, ^=, <<=, >>=, &&=, ||=, ::, ., .., ...

LITERAL: NUMBER (integer, float), STRING (quoted, interpolated),
         SYMBOL, REGEX

DELIMITER: (, ), [, ], {, }, ,, ;, \n, ->

COMMENT: # ... \n
```

### Lexer Requirements

1. Preserve line and column information
2. Handle string interpolation (`"#{expr}"`)
3. Track indentation and dedentation (for alternative syntax)
4. Recognize heredocs
5. Handle symbol literals and ranges
6. Distinguish operators from method names

### Example

```ruby
def foo(x)
  x * 2
end
```

Tokens:
```
KEYWORD:def  IDENTIFIER:foo  (  IDENTIFIER:x  )  NEWLINE
  IDENTIFIER:x  OPERATOR:*  NUMBER:2  NEWLINE
KEYWORD:end  NEWLINE  EOF
```

---

## Phase 2: Recursive Descent Parser

Parses token stream into an Abstract Syntax Tree.

### Grammar (Simplified BNF)

```
program        := statement*

statement      := expr_stmt
                | class_def
                | module_def
                | def_stmt
                | if_stmt
                | case_stmt
                | while_stmt
                | begin_stmt

class_def      := "class" CONST ("<" CONST)? ";" stmt* "end"

def_stmt       := "def" IDENTIFIER "(" params? ")" ";" stmt* "end"

if_stmt        := "if" expr ";" stmt* elsif_part* else_part? "end"

method_call    := expr ("." | "::") IDENTIFIER ("(" args? ")")?

args           := expr ("," expr)*

expr           := term (binop term)*

term           := atom
                | "(" expr ")"
                | "{" expr "}"
                | "[" expr_list "]"
                | atom "." IDENTIFIER

atom           := IDENTIFIER
                | NUMBER
                | STRING
                | SYMBOL
                | "true" | "false" | "nil"
```

### Parser Implementation Pattern

```ruby
class Parser
  def program
    stmts = []
    while !@tokens.empty? && @tokens.peek != :EOF
      stmts << statement
      skip_newlines
    end
    Program.new(stmts)
  end

  def statement
    case @tokens.peek
    when :class
      class_def
    when :def
      def_stmt
    when :if
      if_stmt
    else
      expr_stmt
    end
  end

  def method_call
    left = atom
    while @tokens.peek == :. || @tokens.peek == :::
      op = consume
      method = consume(:IDENTIFIER)
      if @tokens.peek == :'('
        consume
        args = argument_list
        consume(:')')
        left = MethodCall.new(left, method, args)
      else
        left = MethodCall.new(left, method, [])
      end
    end
    left
  end

  private

  def consume(expected = nil)
    token = @tokens.pop
    if expected && token.type != expected
      raise "Expected #{expected}, got #{token.type}"
    end
    token
  end
end
```

---

## Phase 3: AST Nodes

### Core AST Node Types

```
Program
 ├── body: Statement[]

Block
 ├── params: Identifier[]
 ├── body: Statement[]

MethodDef
 ├── name: Identifier
 ├── params: Parameter[]
 ├── body: Statement[]
 └── visibility: :public | :private | :protected

ClassDef
 ├── name: Constant
 ├── parent: Constant?
 ├── body: Statement[]
 └── singleton_class?: Boolean

ModuleDef
 ├── name: Constant
 ├── body: Statement[]

MethodCall
 ├── receiver: Expr
 ├── selector: Identifier
 ├── args: Expr[]
 ├── block: Block?

If
 ├── condition: Expr
 ├── then_body: Statement[]
 ├── elsif_parts: (condition: Expr, body: Statement[])[]
 └── else_body: Statement[]

Case
 ├── expr: Expr?
 ├── whens: (patterns: Expr[], body: Statement[])[]
 └── else_body: Statement[]

While
 ├── condition: Expr
 ├── body: Statement[]

For
 ├── var: Identifier
 ├── collection: Expr
 └── body: Statement[]

Identifier
 └── name: String

Literal
 ├── value: Any
 └── type: :integer | :float | :string | :symbol

StringInterpolation
 ├── parts: (String | Expr)[]

ArrayLiteral
 └── elements: Expr[]

HashLiteral
 └── pairs: (key: Expr, value: Expr)[]

BinaryOp
 ├── left: Expr
 ├── op: Symbol
 └── right: Expr

UnaryOp
 ├── op: Symbol
 └── operand: Expr
```

---

## Phase 4: Normalization

Simplify and canonicalize the AST:

1. **Operator precedence**: Restructure binary operations
2. **Method shorthand**: Expand `a.b` to `MethodCall(a, :b, [])`
3. **Block syntax**: Normalize `do...end` and `{...}` to Block nodes
4. **String interpolation**: Parse interpolated expressions
5. **Implicit receivers**: Expand implicit `self` calls
6. **Return values**: Make implicit returns explicit
7. **Multiple assignment**: Expand `a, b = [1, 2]` to discrete assignments

---

## Phase 5: Symbol Resolution

Map identifiers to their semantic role:

```prolog
identifier(Name, local_var) :-
    defined_locally(Name).

identifier(Name, instance_var) :-
    atom_concat('@', Name, _).

identifier(Name, class_var) :-
    atom_concat('@@', Name, _).

identifier(Name, global_var) :-
    atom_concat('$', Name, _).

identifier(Name, constant) :-
    upcase(Name, Name).

identifier(Name, method_call) :-
    method_defined(Name).
```

---

## Phase 6: Error Recovery

The parser must not fail on syntax errors; instead:

1. Report error with line/column
2. Insert error node
3. Skip to recovery point (end of statement)
4. Continue parsing

---

## Backend Integration

After normalization, AST is passed to IR generator:

```
NORMALIZED AST
    │
    ├─→ CRuby IR
    ├─→ JRuby IR
    ├─→ Rubinius IR
    ├─→ mruby IR
    ├─→ TruffleRuby IR
    ├─→ Crystal IR
    ├─→ Opal IR
    └─→ Mirah IR
```

Each backend implements its own IR generator from the normalized AST.

---

## Implementation Notes

- **Single-pass parsing**: No lookahead beyond 1 token (or minimal)
- **No external dependencies**: Parser should be standalone
- **Streaming**: Can process large files without full in-memory AST
- **Extensibility**: Easy to add new statement types
- **Testability**: Each parser function independently testable

---

## Test Coverage

```
Lexer:
  ✓ All token types
  ✓ String interpolation
  ✓ Heredocs
  ✓ Comments
  ✓ Numbers (integers, floats, scientific notation)
  ✓ Symbols and ranges
  ✓ Operators and precedence

Parser:
  ✓ Method definitions
  ✓ Class definitions
  ✓ Module definitions
  ✓ Control flow (if, case, while, for)
  ✓ Method calls
  ✓ Blocks and lambdas
  ✓ Array and Hash literals
  ✓ Operator expressions
  ✓ Exception handling

Normalization:
  ✓ Implicit returns
  ✓ Method receiver insertion
  ✓ String interpolation parsing
  ✓ Operator precedence restructuring
```
