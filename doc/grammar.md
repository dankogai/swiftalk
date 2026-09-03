# swiftalk — grammar

The language as the parser accepts it (round 76; derived from
`Sources/Swiftalk/Parser.swift` and `Lexer.swift`). EBNF-ish: `{ }`
repeats, `[ ]` is optional, `|` alternates, quoted text is literal.
Shelved forms (`actor`, `class`, `super`) are not grammar today.

## Lexical structure

* **Comments**: `// ...` to end of line; `/* ... */`, nesting.
* **Separators**: a newline or `;` ends a statement. Newlines are
  *suppressed* inside `[ ]` and `( )` (literals and calls span lines);
  inside `{ }` they matter — a body is a statement list. The REPL
  evaluates a statement as soon as its line completes, so `else` and
  a second trailing closure must share the line there.
* **Identifiers**: a Unicode-alphabetic character or `_`, then
  alphanumerics/`_`. `$` and `$0`, `$1`, … are identifiers of their own.
* **Keywords** (never identifiers): `let var true false nil in if
  else while repeat for break continue return yield async await enum
  case switch default struct extension`. Contextual (identifiers
  elsewhere): `init self get set willSet didSet newValue oldValue`.
  Not keywords, deliberately: `guard`, `func`, `mutating`, `class`,
  `actor`, `super` (§9 and round 62).
* **Literals**
  * Int: `42`, `1_000`, `0xff`, `0o377`, `0b101` — 64-bit, `_` allowed.
  * Double: `1.0`, `1e3`, `1.5e-3`, hex floats `0x1.fep7` / `0x1p-2`
    (a hex fraction *requires* the `p` exponent, so `0xff.description`
    stays member access). A `.` needs a digit on both sides.
  * String: `"..."` with `\" \\ \n \r \t \0 \u{...}` and `\(expr)`
    interpolation (nesting freely).
* **Operators & punctuation**: `+ - * /`, `== != < <= > >=`, `&& ||`,
  prefix `! -`, `...` `..<`, `??`, `= : , . ; ( ) [ ] { }`. Three
  spacing-sensitive rules:
  * `?` — `??` coalesces; *unspaced* `?.` chains, *unspaced* postfix
    `?` propagates; *spaced* `?` is the ternary.
  * `!` — `!=` compares; `!` before an operand is logical not; `!`
    after one is force-unwrap.
  * `.` — digits directly after `.` are a tuple index (`t.0.1`), never
    a Double.
  * A lone `&` or `|` is a syntax error.

## Program and statements

```
program      = { statement separator } ;
separator    = NEWLINE | ";" ;

statement    = declaration | destructure | assignment | expression
             | if | while | repeat | for | switch
             | "break" | "continue"
             | "return" [ expression ] | "yield" [ expression ]
             | enumDecl | structDecl | extensionDecl ;

declaration  = ( "let" | "var" ) IDENT [ ":" type ] "=" expression ;
destructure  = ( "let" | "var" ) pattern "=" expression ;
assignment   = lvalue "=" expression ;
lvalue       = IDENT
             | lvalue "[" expression "]"
             | lvalue "." ( IDENT | INT )
             | "." IDENT                              (* implicit self *)
             | "(" [ IDENT ":" ] lvalue { "," [ IDENT ":" ] lvalue } ")" ;

type         = IDENT [ "?" ]
             | "[" type "]" [ "?" ]
             | "[" type ":" type "]" [ "?" ] ;

pattern      = IDENT | "_"
             | "(" element { "," element } [ "," ] ")" ;
element      = [ IDENT ":" ] pattern ;                 (* labeled binds by label *)
```

### Control flow

```
if           = "if" conditions block [ "else" ( if | block ) ] ;
conditions   = condition { "," condition } ;
condition    = expression                              (* must be a Bool *)
             | ( "let" | "var" ) IDENT                 (* shorthand: if let x { } *)
             | [ "let" | "var" ] pattern "=" expression ;  (* nil fails; a misfit errors;
                                                          let optional since round 78 *)

while        = "while" conditions block ;              (* while let: fresh bindings per pass *)
repeat       = "repeat" block "while" expression ;
for          = "for" pattern { "," pattern } "in" expression block ;
                                                       (* for k, v in d — parens optional *)
switch       = "switch" expression "{"
                 { "case" casePattern { "," casePattern } ":" { statement } }
                 [ "default" ":" { statement } ]
               "}" ;                                   (* no match, no default: runtime error *)
casePattern  = "_"
             | "." IDENT                               (* the subject's case, any payload *)
             | [ "let" | "var" ] pattern "=" "." IDENT (* case let r = .circle: the accessor; nil fails *)
             | expression ;                            (* equality; a Range matches an Int by containment *)
block        = "{" { statement } "}" ;
```

A condition or case that starts with a pattern followed by `=` is a
binding; anything else is an expression (`if x == y`, `case (a, b):`).
Assignment is a statement, so the `=` is unambiguous. Swift's `if
case` and `.name(let x)` are syntax errors that name the replacement
(round 78).

Trailing closures are disabled inside `if`/`while`/`for`/`switch`
headers (`if c { }` must read `{` as the block) — parenthesize a
trailing-closure call there.

### Declarations of types

```
enumDecl     = "enum" IDENT "{" { enumCase | method } "}" ;
enumCase     = "case" IDENT [ "(" [ IDENT ":" ] IDENT { "," [ IDENT ":" ] IDENT } ")" ]
               { "," IDENT [ ... ] } ;

structDecl   = "struct" IDENT "{" { property | computed | method | init } "}" ;
property     = ( "var" | "let" ) IDENT [ ":" type ] [ "=" expression ] [ observers ] ;
computed     = "var" IDENT [ ":" type ] "{" ( { statement }
             | "get" block [ "set" [ "(" IDENT ")" ] block ] ) "}" ;
observers    = "{" { ( "willSet" | "didSet" ) [ "(" IDENT ")" ] block } "}" ;
method       = "let" IDENT "=" closure ;               (* let + closure literal = method *)
init         = "init" closure ;                        (* several: multi-dispatch *)

extensionDecl = "extension" IDENT "{" { method | computed } "}" ;
```

A brace whose first word is `willSet`/`didSet` is an observer block,
never a trailing closure or a computed body.

## Expressions

Precedence, loosest to tightest; each line is one grammar level.

```
expression   = ternary ;
ternary      = disjunction [ "?" expression ":" expression ] ;      (* spaced ?, right-assoc *)
disjunction  = conjunction { "||" conjunction } ;                   (* short-circuit *)
conjunction  = comparison { "&&" comparison } ;
comparison   = coalescing [ ( "==" | "!=" | "<" | "<=" | ">" | ">=" ) coalescing ] ;   (* not chained *)
coalescing   = range [ "??" coalescing ] ;                          (* right-assoc, lazy right *)
range        = additive [ ( "..." | "..<" ) additive ] ;
additive     = multiplicative { ( "+" | "-" ) multiplicative } ;
multiplicative = unary { ( "*" | "/" ) unary } ;
unary        = "-" unary | "!" unary | "await" unary | postfix ;
postfix      = primary { suffix } ;
suffix       = "." IDENT [ args ]                      (* member, method *)
             | "." INT                                 (* tuple element *)
             | "(" args ")"                            (* call; $(...) recurses *)
             | "[" expression "]"                      (* subscript *)
             | closure                                 (* trailing closure: the pinned last argument *)
             | "?"                                     (* unspaced: propagate nil/.failure *)
             | "!"                                     (* force-unwrap *)
             | "?." IDENT [ args ] ;                   (* optional chaining *)

primary      = INT | DOUBLE | STRING | "true" | "false" | "nil"
             | IDENT | "$" | "$" INT
             | "." IDENT                               (* implicit self member, or a format tag *)
             | "(" expression ")"                      (* grouping *)
             | tuple | array | dictionary
             | closure | "async" closure ;             (* async { } is Task { } *)

tuple        = "(" ")"
             | "(" tupleElement "," ")"                (* the 1-tuple: (x,) *)
             | "(" tupleElement { "," tupleElement } [ "," ] ")" ;
tupleElement = [ IDENT ":" ] expression ;              (* (x: 1) is a 1-tuple: a group has no label *)
array        = "[" [ expression { "," expression } [ "," ] ] "]" ;
dictionary   = "[" ":" "]"
             | "[" expression ":" expression { "," expression ":" expression } [ "," ] "]" ;
closure      = "{" [ paramList "in" ] { statement } "}" ;
paramList    = ( IDENT | "_" ) { "," ( IDENT | "_" ) } ;   (* _ = positional-only *)
args         = "(" [ arg { "," arg } [ "," ] ] ")" ;
arg          = [ IDENT ":" ] expression ;              (* labels optional, reorderable; `_:` refused *)
```

Notes: `{ }` always makes a Function (never grouping, never a
dictionary). A sole Tuple argument is the argument list (`$` holds
its elements). A closure with no `in` is variadic. Comparison is not
chained (`a < b < c` is a syntax error). Empty parameter lists cannot
be written — `{ }` is already variadic.
