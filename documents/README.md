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
| `Set` | COW, unordered, unique; `Set(a, b, ...)`, `Set<T>` (rounds 132–134) | [Set.md](Set.md) |
| `Range` | lazy `a...b` / `a..<b`, Int only | [Range.md](Range.md) |
| `Function` | the one function type | [Function.md](Function.md) |
| `Sequence` | lazy generators & coroutines (also a protocol) | [Sequence.md](Sequence.md) |
| `Data` | bytes, `[UInt8]` | [Data.md](Data.md) |
| `Byte` | Data's element — an Int that fits a byte | [Byte.md](Byte.md) |
| `Date` | epoch seconds as Double | [Date.md](Date.md) |
| `Task` | a spawned computation | [Task.md](Task.md) |
| `Tuple` | a grab bag `(v0, v1, ...)`, one loose type | [Tuple.md](Tuple.md) |
| `Regex` | `/pattern/flags` — the literal is grammar, the type the Regex module's (round 186) | [Regex.md](Regex.md) |
| `SION` | the data format, built in: SION, JSON, property lists | [SION.md](SION.md) |
| modules | `import` / `export`, `.swt` files by path or URL | [module.md](module.md) |
| `Result` | built-in enum: `.success` / `.failure` | [Result.md](Result.md) |
| `IO` | the module of `print` and `debugPrint` — preimported by the CLI (round 185) | [IO.md](IO.md) |
| `Net` | the module of `fetch` and `Response` — preimported by the CLI (rounds 163, 185) | [Net.md](Net.md) |
| `POSIX` | the environment and file I/O — a module to import (round 188) | [POSIX.md](POSIX.md) |
| `struct` | user value types | [struct.md](struct.md) |
| `enum` | user sum types | [enum.md](enum.md) |

The pages above are the types. The rest of the language has its own
pages, in lowercase (round 157): [grammar.md](grammar.md) for the
syntax as parsed, [flowcontrol.md](flowcontrol.md) for `if`/`switch`/
the loops/early exit, [toplevel.md](toplevel.md) for the top level — `eval`, the prelude
(`IO` and `Net`, round 185), the types as values, and the names the
language binds —, [module.md](module.md) for
`import`/`export`. [Bool.md](Bool.md) has the logical operators — the
symbols and, since round 155, the words `not and or xor`.

## Members every value has

| Member | Meaning |
|---|---|
| `x.Type` | the constructor Function (`42.Type == Int`); `x.Type.name` is its name |
| `x.description` | print's form: Strings bare, everything else source form |
| `x.debugDescription` | debugPrint's form: quoted strings, signed hex numbers (`.String(.sign, .hex)`, round 125) |
| `x.String()` | description; `x.String(.quoted)` is source form (§3d) |
| `x == y`, `x != y` | equality — same type required (except against `nil`); reference-ish types compare by identity |
| `x === y`, `x !== y` | the same type and the same value, bit for bit — JS's `Object.is`: `Double.nan === Double.nan`, `+0.0 !== -0.0`, `1 !== 1.0`, and Strings scalar for scalar where `==` is canonical equivalence (round 140); recursive through containers; never a type error (round 121) |

## The conversion law (round 47)

`x.TypeName(tag: ...)` **is** `TypeName(x, tag: ...)` — one operation,
two spellings; the method form chains. `Type()` with no argument is
the type's default. Conversions are **failable where the value may
not convert** (they return `nil`) and **type errors where the type
never converts**. The law reaches user types (round 151): a struct or
enum declaring `let Double = { ... }` answers `Double(x)` as it
answers `x.Double()`, format arguments passed to the member; a `let
String` member owns the type's text wherever a value of it prints
(round 152) — `.String(...)`, `String(x)`, `print`, `"\(x)"`, the
REPL, inside a container. `.description` is the builtin memberwise
text (what a member returns for the form it does not change), and
the data formats `.sion`/`.json`/`.propertyList` on a container never
ask the member.

## Extending any type (§10)

```swift
extension Int { let doubled = { self * 2 } }      // a method
extension Int { var squared { self * self } }      // a read-only computed property
extension Int { static let answer = 42 }           // a static (round 143), beside Int.max
// an extension of a builtin is program-wide (round 147): declared in a module, it reaches the importer
21.doubled()   // 42
12.squared     // 144
Int.answer     // 42
```

## `SION` and `Any` (round 59)

`SION` (nil, Bool, Int, Double, String, Data, Date, and
Arrays/Dictionaries of them) and `Any` are accepted in type
annotations — `let xs: [SION] = [1, "one"]`, `var a: Any = 1`. `Any`
is not a value; `SION` is also a type since round 97 — `SION(text)`
reads a document, see [SION.md](SION.md) — and the default element
type of an empty literal since round 181: `var a = []` is a `[SION]`,
`[:]` a `[SION: SION]`. (`Primitives`, SION minus Data and Date, was
retired in round 181.)

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

## The global functions

`print`, `debugPrint`, `sleep`, and `eval` — see
[toplevel.md](toplevel.md), which also lists the types and protocols
as values and the names the language binds (`$`, `self`, `Self`, …).

## Operators, by type

| Operator | Int | Double | String | Array | Date | Bool | any |
|---|---|---|---|---|---|---|---|
| `+ - * /` | ✓ (traps on overflow, `/0`) | ✓ | `+` only | `+` only; on Sets `-` is subtraction (round 133; union is `\|`, `+` removed in 136) | | | |
| `**`, `**=` | ✓ Int, trapping; a negative exponent is an error (round 142) | ✓ `pow` | | | | | |
| `\| & ^`, `\|= &= ^=` | | | | Sets only (round 135): union, intersection, symmetric difference — `s.union(t) == s \| t` | | | |
| `%` | ✓ remainder, the dividend's sign; `% 0` traps (round 93) | type error, as in Swift | | | | | |
| `+= -= *= /= %=` | ✓ (round 102) — `x op= y` is `x = x op y`, the target evaluated once | ✓ | `+=` | `+=` | | | |
| `??=` | `x ??= y` writes `y` only when `x` is nil (or a Result failure); `y` unevaluated otherwise (round 103) — any type; on a Dictionary, per key (round 130) | | | | | | |
| `!!`, `!!=` | `a !! b` is `b ?? a` — the right side's value when it has one (round 130); `x !!= y` is `x = y ?? x`; on Dictionaries per key, so `d0 !! d1` overrides with `d1` and `d0 ?? d1` fills from it. Infix only after an operand with a space before it: `x!!` is two unwraps, `!!b` two nots | | | | | | |
| `&&= ||=` | Bool targets and Bools only; short-circuit like the operators (round 104) — the `op=` family is now every binary operator that can spell one | | | | | | |
| `^^`, `^^=` | logical xor, Bools only, both sides evaluated; between `&&` and `||` (round 106) | | | | | | |
| `.not()`, `.and()`, `.or()`, `.xor()` | logical, on a Bool, eager (round 106) | | | | | | |
| `.bitNot()`, `.bitAnd()`, `.bitOr()`, `.bitXor()`, `.shifted(by:)` | bitwise, on an Int (rounds 105/107) | ✓ | | | | | |
| `< <= > >=` | ✓ | ✓ | ✓ | | ✓ | | |
| `== !=` | | | | | | | ✓ same type, or vs nil |
| `=== !==` | | | | | | | ✓ same type and bits; any pair, never an error (round 121) |
| `&& \|\| !` | | | | | | ✓ short-circuit | |
| `? :` | | | | | | condition | |
| `??` `x?` `x!` `x?.m` | | | | | | | ✓ (nil / Result); `??` on two Dictionaries is per key (round 130) |

Mixed arithmetic (`1 + 1.5`) is a type error — convert explicitly.
Precedence, high to low: `**` (right-assoc) · prefix `! -` · `* / %` · `+ -` · `... ..<` ·
`??` · comparison · `&&` · `^^` · `||` · `? :`. **An operator in
parentheses is a Function** (round 144): `(+)(2, 4)`, `xs.reduce(0,
(+))` — see [Function.md](Function.md). A lone `&`, `|`, or `^`
is a Set operator (round 135) — `&` at `*`'s level, `|` and `^` at
`+`'s — and a type error on anything else; bitwise operations are
methods on Int.
