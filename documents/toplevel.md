# The top level

What a program sees before it declares anything (round 157): four
functions, the types and protocols as values, one built-in enum, and
the names the language binds on its own. Everything here is an
ordinary `let` in the outermost scope (§2.4) — not a keyword — so it
can be passed, aliased, and shadowed by a declaration of your own.

## Functions

| Form | Meaning |
|---|---|
| `eval(source)` | **the language's own `eval`** (round 122; Swift has none): the String is a swiftalk program, and a **`Result`** comes back (round 159) — `.success(v)` with its last statement's value, or `.failure(message)` for any error the program raises (a syntax error, an undefined name, a trap), never thrown: `eval(s)?` propagates, `eval(s) ?? d` defaults, `eval(s)!` unwraps or traps. Runs **at the file's top level** — sees what the top level sees, declares into it as a line at the REPL would, and cannot see a caller's locals. The round-trip law in the language: `eval(x.String())! == x`. Calling it with anything but one String is the caller's type error, as with any builtin |

`eval` is the top level's one function since round 185 — `print`,
`debugPrint`, `readLine`, and the `IO` type (round 191), `fetch` and
`Response`, are the **`IO`** and **`Net`** modules' ([IO.md](IO.md),
[Net.md](Net.md)), which the CLI **preimports
as its prelude**, so a script and the REPL have them as before; an
embedder calls `Interpreter.preimport()` for the same, or imports them
(`import from "IO"`) or not. `zip` is `Sequence.zip` and `sleep` is
`Task.sleep`, statics of the core types ([Sequence.md](Sequence.md),
[Task.md](Task.md)). `eval` is a Function value — `["1", "[2]"].map(eval)`
— that is **not a builtin: each file has its own** (round 123). The program's `eval` runs at the program's top level; a module's
runs at the module's, whoever calls it — `eval` resolves lexically, so
a function a module exports evaluates in the module it came from and
sees that module's unexported names, never the importer's.

```swift
print(1, "two", [3])          // 1 two [3]
debugPrint(1, "two", [3])     // +0x1 "two" [+0x3]
let r = print("x")            // r is nil
sleep(0.5)
eval("1 + 1")                 // Result.success(2); eval("1 + 1")! is 2
eval("1 +") ?? 0              // 0 — .failure("syntax error: unexpected token end of input")
```

### `Response`

What a successful `fetch` carries — a struct **declared in swiftalk**
at startup (the first prelude), so it is an ordinary type: `Response(
status: 200, body: "hi".Data(.utf8))` constructs one, `r.Type ==
Response`, and it prints memberwise.

| Member | Meaning |
|---|---|
| `r.status` | the HTTP status, an Int |
| `r.ok` | `200 <= status < 300` |
| `r.headers` | `[String: String]`, names lowercased: `r.headers["content-type"]` |
| `r.body` | the bytes, a Data |
| `r.text()` | `body.String(.utf8)` — a String, or nil when the bytes are not UTF-8 |
| `r.json()` | `SION(json: text)` — the parsed document; a JSON error is the parser's |

```swift
let r = await fetch("https://example.com")          // a Result
r.then { $0.status }                                 // Result.success(200)
r.then { $0.text()!.contains("Example Domain") }     // Result.success(true)
(await fetch("https://api.example/items", (method: "POST", headers: ["Content-Type": "application/json"], body: "{\"a\":1}")))
    .then { $0.json() }
    .catch { err in print("fetch failed:", err); nil }
let a = fetch(u1); let b = fetch(u2)                 // both in flight at once
[(await a)?.status, (await b)?.status]
```

Mind the precedence: `await fetch(u).then { }` is `await (fetch(u).then { })`,
a `then` on a Task — parenthesize, `(await fetch(u)).then { }`, as in JS.

There is no `readLine`, `exit`, `assert`, or `args` (yet): a script
reads nothing and ends when its last statement does; a runtime error
ends it early with the message on stderr.

## Types and protocols, as values

Every type name is a global `let` bound to the type object (round
39): `Int`, `Bool`, `String`, … are values, `x.Type == Int` compares
identities, and `let I = Int` aliases (round 111). Calling one
converts — `Int("42")` is `"42".Int()`, the round-47 law — or
constructs, `Set(1, 2)`, `Sequence { }`, `Task { }`.

The container types carry their parameters (round 165): `[Int]` and
`[Int: String]` are expressions — an Array literal of exactly one
type, a Dictionary literal of one type-to-type pair — and so are
Swift's generic and optional spellings (round 167): `Set<Int>`,
`Dictionary<Int, String>`, `Optional<Int>` and its shorthand `Int?`,
nested as you like (`Set<Set<Int>>`, `[Int?]`, `[Int]?`). `[0].Type`
is `[Int]`, `Set([1]).Type` is `Set<Int>`, `[nil, 1].Type` is
`[Int?]`. Calling one builds a container that remembers:
`[Int]()` is empty and still an Array of Int, so `var a = [Int]()`
then `a.append("x")` is a type error; `[Int](1...3)` checks its
elements. Types compare by name, and the erased `Array` equals any
`[T]`: `[0].Type == Array` and `[0].Type == [Int]` are both true,
`[Int] == [String]` false; `filter` and the slices keep the element
type, `map` infers one from its results, `Array(x)`, `Set(x)`, and `Dictionary(pairs)` keep or infer, `zip` and `enumerated()` are `[Tuple]`, `reversed()` and `sorted()` carry the element type, `split()` and `joined()` move it a level, `keys` and `values` split it (rounds 168–180); an empty literal bound without an annotation is data — `[]` is `[SION]`, `[:]` is `[SION: SION]`, `Set()` is `Set<SION>` — and refuses a Function (round 181); an optional is its own type, `Int? != Int`,
and `Int?("x")` constructs through `Int` with nil as a possible
answer. `Function` carries nothing: `{ $0 }.Type`
is `Function`, whatever its arguments and result. A parameterized
type gives its parameters back under Swift's names (round 166):
`[Int].Element`, `[Int: String].Key` and `.Value`, `Set([1]).Type
.Element` are the types `Int`, `Int`, `String`, `Int`; called, they
construct — `[Int].Element("42")` is `42`. The erased `Array` has no
`Element` to give (a type error), and a parameter that is not a value
(`Int?`, `Any`) is one too.

| Names | Kind |
|---|---|
| `Nil` `Bool` `Byte` `Int` `Double` `String` `Array` `Dictionary` `Set` `Range` `Function` `Data` `Date` `Task` `Tuple` `SION` | the built-in types — one page each in [README.md](README.md) |
| `Sequence` | a type (a lazy generator or coroutine) and the protocol every iterable conforms to — [Sequence.md](Sequence.md) |
| `Equatable` `Hashable` `Comparable` | protocols: `T.conforms(to: Comparable)`; every value is Equatable and Hashable, Comparable is Int/Double/String/Date/Byte and any struct or enum with `infix(<)` (round 146) |
| `Result` | the built-in enum, `.success(v)` / `.failure(e)` — [Result.md](Result.md) |
| `Response` | `fetch`'s answer, a struct declared in swiftalk — the `Net` module's, preimported by the CLI (rounds 163, 185) — [Net.md](Net.md) |
| `Regex` | the Regex **module's** type (round 186), preimported by the CLI — the literal `/re/` is grammar and calls it, an error when it is not in scope — [Regex.md](Regex.md) |
| `Optional` | `Optional<Int>` is the type `Int?` (round 167) — the bare name is the identity constructor, `Optional(x)` is `x`, and no annotation |
| `Any` | an annotation-only name (round 59): not a value, a type error as one. (`Primitives` was retired in round 181 — `SION` covers it) |

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

**Tab completes** (round 164). A name: everything in scope — your
bindings, the types, `print`/`fetch`/…, the keywords — and `:h`/`:r`/
`:d` at a line's start. A member, after a dot: the receiver is read
(a chain of names, `p.origin.`, or a literal — `[1, 2].`, `"s".` —
never a call or a subscript, which are not run for completion) and
its value says what it has — a struct's properties, computed
properties, and methods; an enum's cases and methods; a type's
statics (`Double.sq` → `sqrt sqrt2 sqrtHalf`); a builtin value's
members and any `extension` members; a bare dot offers the format
words and `.success`/`.failure`. One candidate is inserted; several
insert what they share, and a second Tab lists them. The engine is
`Interpreter.complete(text)` — the text up to the cursor in, the
word's start and the candidates out — for an embedder's editor.
