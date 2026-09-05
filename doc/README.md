# swiftalk — type reference

One page per type, listing every member the interpreter actually
dispatches (round 68; derived from the evaluator, verified in the
REPL). Sections in [Design.md](../Design.md) are cited as §n.

| Type | Kind | Page |
|---|---|---|
| `Nil` | the type of `nil` | [Nil.md](Nil.md) |
| `Bool` | `true` / `false` | [Bool.md](Bool.md) |
| `Int` | 64-bit, trapping | [Int.md](Int.md) |
| `Double` | IEEE 754 | [Double.md](Double.md) |
| `String` | Unicode, grapheme-counted | [String.md](String.md) |
| `Array` | COW, element-typed | [Array.md](Array.md) |
| `Dictionary` | COW, `[Key: Value]`, any Hashable key | [Dictionary.md](Dictionary.md) |
| `Range` | lazy `a...b` / `a..<b`, Int only | [Range.md](Range.md) |
| `Function` | the one function type | [Function.md](Function.md) |
| `Sequence` | lazy generators & coroutines (also a protocol) | [Sequence.md](Sequence.md) |
| `Data` | bytes, `[UInt8]` | [Data.md](Data.md) |
| `Date` | epoch seconds as Double | [Date.md](Date.md) |
| `Task` | a spawned computation | [Task.md](Task.md) |
| `Tuple` | a grab bag `(v0, v1, ...)`, one loose type | [Tuple.md](Tuple.md) |
| `Regex` | `/pattern/flags`, Swift's engine | [Regex.md](Regex.md) |
| `SION` | the data format, built in: SION, JSON, property lists | [SION.md](SION.md) |
| modules | `import` / `export`, `.swt` files by path or URL | [module.md](module.md) |
| `Result` | built-in enum: `.success` / `.failure` | [Result.md](Result.md) |
| `struct` | user value types | [struct.md](struct.md) |
| `enum` | user sum types | [enum.md](enum.md) |

See [grammar.md](grammar.md) for the syntax as parsed.

## Members every value has

| Member | Meaning |
|---|---|
| `x.Type` | the constructor Function (`42.Type == Int`); `x.Type.name` is its name |
| `x.description` | print's form: Strings bare, everything else source form |
| `x.debugDescription` | debugPrint's form: quoted strings, hex numbers |
| `x.String()` | description; `x.String(.quoted)` is source form (§3d) |
| `x == y`, `x != y` | equality — same type required (except against `nil`); reference-ish types compare by identity |

## The conversion law (round 47)

`x.TypeName(tag: ...)` **is** `TypeName(x, tag: ...)` — one operation,
two spellings; the method form chains. `Type()` with no argument is
the type's default. Conversions are **failable where the value may
not convert** (they return `nil`) and **type errors where the type
never converts**.

## Extending any type (§10)

```swift
extension Int { let doubled = { self * 2 } }      // a method
extension Int { var squared { self * self } }      // a read-only computed property
21.doubled()   // 42
12.squared     // 144
```

## Annotation-only names (round 59)

`Primitives` (nil, Bool, Int, Double, String, and Arrays/Dictionaries
of them), `SION` (Primitives plus Data and Date), and `Any` are
accepted in type annotations — `let xs: [Primitives] = [1, "one"]`,
`var a: Any = 1`. `Primitives` and `Any` are not values; `SION` is
also a type since round 97 — `SION(text)` reads a document, see
[SION.md](SION.md).

## Aliasing a type: `let I = Int` (round 111)

There is no `typealias` (round 110 added one; round 111 retracted
it): a type is a Function value, so a binding is the alias. `let I =
Int` gives a name that constructs (`I("7")`), compares (`3.Type ==
I`), annotates (`let n: I = 42`, a struct property `var r: R`, an
enum payload `case some(N)`, nested `[N]`), and converts by the
round-47 law: with `let S = String`, `42.S()` is `42.String()`; a
conversion the type does not have fails as it would by its real
name. What a binding cannot alias: a parameterized or optional
annotation (`[String]`, `Int?`) — spell those out, or annotate `Any`.

## Operators, by type

| Operator | Int | Double | String | Array | Date | Bool | any |
|---|---|---|---|---|---|---|---|
| `+ - * /` | ✓ (traps on overflow, `/0`) | ✓ | `+` only | `+` only | | | |
| `%` | ✓ remainder, the dividend's sign; `% 0` traps (round 93) | type error, as in Swift | | | | | |
| `+= -= *= /= %=` | ✓ (round 102) — `x op= y` is `x = x op y`, the target evaluated once | ✓ | `+=` | `+=` | | | |
| `??=` | `x ??= y` writes `y` only when `x` is nil (or a Result failure); `y` unevaluated otherwise (round 103) — any type | | | | | | |
| `&&= ||=` | Bool targets and Bools only; short-circuit like the operators (round 104) — the `op=` family is now every binary operator that can spell one | | | | | | |
| `^^`, `^^=` | logical xor, Bools only, both sides evaluated; between `&&` and `||` (round 106) | | | | | | |
| `.not()`, `.and()`, `.or()`, `.xor()` | logical, on a Bool, eager (round 106) | | | | | | |
| `.bitNot()`, `.bitAnd()`, `.bitOr()`, `.bitXor()`, `.shifted(by:)` | bitwise, on an Int (rounds 105/107) | ✓ | | | | | |
| `< <= > >=` | ✓ | ✓ | ✓ | | ✓ | | |
| `== !=` | | | | | | | ✓ same type, or vs nil |
| `&& \|\| !` | | | | | | ✓ short-circuit | |
| `? :` | | | | | | condition | |
| `??` `x?` `x!` `x?.m` | | | | | | | ✓ (nil / Result) |

Mixed arithmetic (`1 + 1.5`) is a type error — convert explicitly.
Precedence, high to low: prefix `! -` · `* / %` · `+ -` · `... ..<` ·
`??` · comparison · `&&` · `^^` · `||` · `? :`. A lone `&` or `|` is a
syntax error — bitwise operators are undecided.
