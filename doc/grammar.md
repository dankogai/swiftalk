# swiftalk — grammar

The language as the parser accepts it (round 76; derived from
`Sources/Swiftalk/Parser.swift` and `Lexer.swift`). EBNF-ish: `{ }`
repeats, `[ ]` is optional, `|` alternates, quoted text is literal.
Shelved forms (`actor`, `class`, `super`) are not grammar today.

## Lexical structure

* **Comments**: `// ...` to end of line; `/* ... */`, nesting.
* **Separators**: a newline or `;` ends a statement. Newlines are
  *suppressed* inside `[ ]` and `( )` (literals and calls span lines),
  and after a trailing binary operator — `+ - * / % =`, a comparison,
  `&& || ??` — which continues the expression on the next line
  (round 95); not after postfix `!`/`?`, and not after `...`, since
  `0...` at a line's end is the unbounded range. A *leading* operator
  continues the previous line too (round 96, Swift's rule): an
  operator at a line's start *with whitespace after it* is infix, so
  the newline before it goes — `+ 2`, `&& c`, `?? d`, `= v`, and the
  spaced ternary's `? a` / `: b`; with none it is a prefix and starts
  a statement (`-x`, `!flag`). Never a leading `.` — `.x = 1` at a
  line's start is implicit self (round 49) — and never `...`. Inside
  `{ }` newlines matter — a body is a statement list. The REPL
  evaluates a statement as soon as its line completes, so `else` and
  a second trailing closure must share the line there.
* **Identifiers**: a Unicode-alphabetic character or `_`, then
  alphanumerics/`_`. `$` and `$0`, `$1`, … are identifiers of their own.
* **Keywords** (never identifiers): `let var true false nil in if
  else while repeat for break continue return yield async await enum
  case switch default struct extension import export`. Contextual
  (identifiers elsewhere): `init self get set willSet didSet newValue
  oldValue where from`. (`Regex` and `SION` are type names, not
  keywords.)
  Not keywords, deliberately: `guard`, `func`, `mutating`, `class`,
  `actor`, `super` (§9 and round 62).
* **Literals**
  * Int: `42`, `1_000`, `0xff`, `0o377`, `0b101` — 64-bit, `_` allowed.
  * Double: `1.0`, `1e3`, `1.5e-3`, hex floats `0x1.fep7` / `0x1p-2`
    (a hex fraction *requires* the `p` exponent, so `0xff.description`
    stays member access). A `.` needs a digit on both sides.
  * String: `"..."` with `\" \\ \n \r \t \0 \u{...}` and `\(expr)`
    interpolation (nesting freely).
  * Multi-line String (round 94, Swift's rules): `"""` then a newline,
    the content, and `"""` on its own line; the closing delimiter's
    indentation is stripped from every line (less is an error, blank
    lines excepted); `"` needs no escape; `\` at a line's end joins
    lines; escapes and interpolation as above.
  * Raw String (round 94): `#"..."#`, `#"""..."""#`, any number of `#`
    — `\` and `"` are literal unless followed by as many `#`s, so
    `\#(expr)` interpolates and `\#n` is a newline; `##"a "# b"##`.
  * Regex (round 86): `/pattern/flags` — `\/` is a `/` in the
    pattern, every other backslash is kept for the engine; flags are
    letters from `imsx`. A `/` starts a regex where an operand cannot
    end (statement start, after `( [ { , : = ?`, an operator, or a
    keyword) and is division after a value, a name, or a closing
    bracket — JavaScript's rule. `//` is a comment, never an empty
    regex.
* **Operators & punctuation**: `+ - * / %`, `+= -= *= /= %= ??= &&= ||= ^^=`, `== != < <= > >=`, `&& ^^ ||`,
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
             | while | repeat | for                   (* if and switch are expressions *)
             | "break" | "continue"
             | "return" [ expression ] | "yield" [ expression ]
             | enumDecl | structDecl | extensionDecl
             | import | export ;                       (* a file's top level only *)

import       = "import" ( IDENT | "(" IDENT { "," IDENT } ")" ) "from" STRING ;   (* round 100 *)
export       = "export" ( declaration | destructure | structDecl | enumDecl )
             | "export" "(" IDENT { "," IDENT } ")" ;

declaration  = ( "let" | "var" ) IDENT [ ":" type ] "=" expression ;
destructure  = ( "let" | "var" ) pattern { "," pattern } "=" expression ;
                                                       (* let (a, b) = t, or let a, b = t (round 99) *)
assignment   = lvalue ( "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "??=" | "&&=" | "||=" | "^^=" ) expression ;
                                                       (* op= reads, combines, writes; the target's
                                                          subscripts are evaluated once (round 102) *)
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
if           = "if" conditions block [ "else" ( if | block ) ] ;   (* an expression (round 80):
                                                          the taken branch's last value, else nil *)
conditions   = condition { "," condition } ;
condition    = expression                              (* must be a Bool *)
             | IDENT                                   (* a bare variable: a Bool is tested, else
                                                          "not nil" — if o { o + 1 } (round 80) *)
             | ( "let" | "var" ) IDENT                 (* shorthand: if let x { } *)
             | [ "let" | "var" ] pattern "=" expression ;  (* nil fails; a misfit errors;
                                                          let optional since round 78 *)

while        = "while" conditions block ;              (* while let: fresh bindings per pass *)
repeat       = "repeat" block "while" expression ;
for          = "for" pattern { "," pattern } "in" expression [ "where" disjunction ] block ;
                                                       (* for k, v in d — parens optional;
                                                          where: s.filter({ }) with the loop's names (round 82) *)
switch       = "switch" expression "{"                (* an expression (round 79): its value is the *)
                 { "case" caseAlt { "," caseAlt } ":" { statement } }   (* chosen branch's *)
                 [ "default" ":" { statement } ]       (* last statement's value *)
               "}" ;                                   (* no match, no default: runtime error *)
caseAlt      = casePattern [ "where" disjunction ] ;  (* the guard belongs to the pattern it follows;
                                                          it sees the pattern's bindings (round 81) *)
casePattern  = "_"
             | "." IDENT                               (* the subject's case, any payload *)
             | [ "let" | "var" ] pattern { "," pattern } "=" ( "." IDENT | comparison )
                                                       (* the comma list needs the let: a bare comma
                                                          separates alternatives (round 99) *)
                                                       (* case let r = .circle: the accessor; nil fails;
                                                          case let (_, a) = /re/: the whole match (round 86) *)
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
disjunction  = xor { "||" xor } ;                                   (* short-circuit *)
xor          = conjunction { "^^" conjunction } ;                   (* both sides evaluated (round 106) *)
conjunction  = comparison { "&&" comparison } ;
comparison   = coalescing [ ( "==" | "!=" | "<" | "<=" | ">" | ">=" ) coalescing ] ;   (* not chained *)
coalescing   = range [ "??" coalescing ] ;                          (* right-assoc, lazy right *)
range        = additive [ "..." [ additive ] | "..<" additive ] ;   (* a... unbounded (round 88): the bound is
                                                                   absent when ) ] } , : ; { or a newline follows *)
additive     = multiplicative { ( "+" | "-" ) multiplicative } ;
multiplicative = unary { ( "*" | "/" | "%" ) unary } ;      (* % is Int only (round 93) *)
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

primary      = INT | DOUBLE | STRING | REGEX | "true" | "false" | "nil"   (* STRING: "...", """...""", #"..."# *)
             | IDENT | "$" | "$" INT
             | "." IDENT                               (* implicit self member, or a format tag *)
             | "(" expression ")"                      (* grouping *)
             | tuple | array | dictionary
             | closure | "async" closure               (* async { } is Task { } *)
             | switch | if ;                           (* let x = switch ..., let y = if c { } else { } *)

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
