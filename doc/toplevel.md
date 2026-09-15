# The top level

What a program sees before it declares anything (round 157): four
functions, the types and protocols as values, one built-in enum, and
the names the language binds on its own. Everything here is an
ordinary `let` in the outermost scope (§2.4) — not a keyword — so it
can be passed, aliased, and shadowed by a declaration of your own.

## Functions

| Form | Meaning |
|---|---|
| `print(x, ...)` | writes each value's display text, space-separated, newline-terminated; `nil`. A String is bare, everything else is its `.String()` — a type's own `String` member speaks here (round 152). `print()` writes an empty line |
| `debugPrint(x, ...)` | the same with each value's `debugDescription`: quoted Strings, signed hex numbers (`.String(.sign, .hex)`, round 125), the memberwise form of a struct — a type's `String` member is not asked |
| `sleep(seconds)` | suspends the current context for a non-negative Int or Double of seconds; parked tasks run meanwhile (§12, round 53) — at the top level, "run the loop for a while". `nil`. Not inside a `Sequence { }` coroutine body |
| `eval(source)` | **the language's own `eval`** (round 122; Swift has none): the String is a swiftalk program, its last statement's value comes back. Runs **at the file's top level** — sees what the top level sees, declares into it as a line at the REPL would, and cannot see a caller's locals. Errors are the language's. The round-trip law in the language: `eval(x.String()) == x` |

`eval` is a Function value like the other three — `["1", "[2]"].map(eval)`
— but unlike them it is **not a builtin: each file has its own** (round
123). The program's `eval` runs at the program's top level; a module's
runs at the module's, whoever calls it — `eval` resolves lexically, so
a function a module exports evaluates in the module it came from and
sees that module's unexported names, never the importer's.

```swift
print(1, "two", [3])          // 1 two [3]
debugPrint(1, "two", [3])     // +0x1 "two" [+0x3]
let r = print("x")            // r is nil
sleep(0.5)
eval("1 + 1")                 // 2
```

There is no `readLine`, `exit`, `assert`, or `args` (yet): a script
reads nothing and ends when its last statement does; a runtime error
ends it early with the message on stderr.

## Types and protocols, as values

Every type name is a global `let` bound to the type object (round
39): `Int`, `Bool`, `String`, … are values, `x.Type == Int` compares
identities, and `let I = Int` aliases (round 111). Calling one
converts — `Int("42")` is `"42".Int()`, the round-47 law — or
constructs, `Set(1, 2)`, `Sequence { }`, `Task { }`.

| Names | Kind |
|---|---|
| `Nil` `Bool` `Byte` `Int` `Double` `String` `Array` `Dictionary` `Set` `Range` `Function` `Data` `Date` `Task` `Tuple` `Regex` `SION` | the built-in types — one page each in [README.md](README.md) |
| `Sequence` | a type (a lazy generator or coroutine) and the protocol every iterable conforms to — [Sequence.md](Sequence.md) |
| `Equatable` `Hashable` `Comparable` | protocols: `T.conforms(to: Comparable)`; every value is Equatable and Hashable, Comparable is Int/Double/String/Date/Byte and any struct or enum with `infix(<)` (round 146) |
| `Result` | the built-in enum, `.success(v)` / `.failure(e)` — [Result.md](Result.md) |
| `Primitives` `Any` | annotation-only names (round 59): not values, a type error as one |

A `struct`, `enum`, or `import` adds to this table for the rest of the
file; `extension Int { }` changes what `Int` dispatches for the whole
program (round 147).

## Names the language binds

| Name | Where | Meaning |
|---|---|---|
| `$`, `$0`, `$1`, … | inside a function | the argument Array and its elements (rounds 14, 32); `$(...)` recurses |
| `self`, `.x` | inside a method, init, computed property | the receiver; a leading dot is `self.` |
| `Self` | inside a `struct`/`enum` body and its extensions | the type itself (round 143) |
| `newValue`, `oldValue` | inside `set`, `willSet`, `didSet` | the incoming / previous value |
| `_` | as a pattern or an assignment/declaration target | **discard** (round 158): `_ = f()`, `let _ = f()`, `(_, n) = pair`, `for _ in 0..<3`, `case _:`, `{ _ in }` — evaluated, never bound, never type-locked; reading `_` is undefined, `_ += 1` an error |

`self`, `init`, `get`, `set`, `willSet`, `didSet`, `newValue`,
`oldValue`, `where`, `from`, `static`, `infix`, `prefix`, `postfix`
are contextual — identifiers elsewhere. The keywords proper are
listed in [grammar.md](grammar.md).

## The REPL's extras

At the `swiftalk>` prompt (not in a script), a line starting with `:`
is a command (round 131): `:h` help, `:r let x = ...` redefine a
top-level binding (also `:r struct P { }`, `:r extension T { }`),
`:d x` undefine one. A non-nil value echoes in its source form,
Strings quoted, a type's own `String` member honored (round 152).
