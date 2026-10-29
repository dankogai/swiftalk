# swiftalk

an attempt to design a scripting language inspired by Swift —
the way JavaScript was "inspired" by Java.

The language is being designed through dialogue; every decision is
recorded in [Design.md](Design.md).

## swiftalk by example

A tour — [examples/tour.swt](examples/tour.swt), verbatim: a program the
test suite runs and checks line for line, so it cannot drift from the
language. Every feature's own entry, round by round, is in
[Status.md](Status.md).

```swift
// swiftalk by example — the README's tour, as a program: this file runs
// (`swift run swiftalk examples/tour.swt`) and the test suite checks its
// output line for line, so what you read here is what the language does.

// bindings are type-locked at first assignment (§3); Int is 64-bit and traps (§3b)
let fact20 = (1...20).reduce(1) { $0 * $1 }   // 2432902008176640000: still fits
var n = 42
// n = "42"                                   // runtime error: n is Int
let big = 2n ** 100n                          // 1267650600228229401496703205376n — BigInt, JS's `n` suffix (round 201)
print(fact20, big)

// collections are [T] and [K: V] (§2.1), copy-on-write values (§4)
var langs = ["swift": 2014, "smalltalk": 1972]
let snapshot = langs                          // a logical copy
langs["swiftalk"] = 2026                      // snapshot unaffected
langs["perl6"] !!= 2015                       // override only what exists: no such key, nothing happens (round 211)
langs["perl6"] ??= 2015                       // fill in: created
print(snapshot.count, langs.count)            // 2 4

// optionals on the flat model (§3a): a value or nil, no box
if let year = langs["smalltalk"] { print("smalltalk: \(year)") }
let y = langs["perl5"] ?? 1987
var maybe: Int? = langs["ruby"]               // Int-or-nil
print(y, maybe, maybe.Type)                   // 1987 nil Nil

// functions are closure literals (§2.4); labels are optional and reorderable (§2.3)
let move = { x, y in x + y }
print(move(x: 1, y: 2) == move(y: 2, x: 1), move(1, 2))   // true 3
let total = { $.reduce(0) { $0 + $1 } }       // $ is the argument list
let fac = { n in n < 2 ? 1 : n * $(n - 1) }   // $() recurses
let six = [1, 2, 3].reduce(0, +)              // an operator is a Function (round 144)
print(total(1, 2, 3, 4), fac(20), 2 ** 10, six)   // 10 2432902008176640000 1024 6

// enums with associated values; switch is an expression (§7, round 79)
enum Shape {
    case circle(r: Double)
    case rect(w: Double, h: Double)
}
let area = { s in
    switch s {
    case let r = .circle:    3.14159265358979 * r * r
    case let (w, h) = .rect: w * h
    }
}
print(area(Shape.rect(w: 3.0, h: 4.0)))       // 12.0

// structs with operators of their own (round 146), printed as source (§3d)
struct Complex {
    var real: Double = 0.0
    var imag: Double = 0.0
    infix(*) = { a, b in Self(a.real * b.real - a.imag * b.imag, a.real * b.imag + a.imag * b.real) }
    prefix(-) = { z in Self(-z.real, -z.imag) }
}
let i = Complex(0.0, 1.0)
print(i * i == Complex(-1.0, 0.0), -i)        // true Complex(real: -0.0, imag: -1.0)

// Result-first errors (§8): ?? defaults, ! traps, postfix ? propagates a failure to the caller
let parsed = eval("1 +") ?? 0                 // eval is the language's own, a Result (rounds 122, 159)
let answer = "42".Int() ?? 0                  // the parses are a String's; Int(3.9) converts (rounds 205–210)
print(parsed, answer, "x".Int(), Int(3.9))    // 0 42 nil 3

// runtime types (§3); .String() is every value's source form (§3d), and it re-enters
let mixed: [SION] = [1, "one", 2.0]
for x in mixed { print("\(x.String()): \(x.Type)") }
let bytes = "café".Data(.utf8)
print(255.String(.hex), bytes, eval(bytes.String())! == bytes)   // 0xff .Data("Y2Fmw6k=") true

// SION is built in (round 97): the same values, three formats
let doc: SION = SION("[\"n\": 42, \"when\": .Date(0x0p+0)]")
print(doc.String(.json))                      // {"n":42,"when":0.0}
print(SION(propertyList: doc.String(.propertyList)) == doc)   // true; Data(doc, .propertyList) is bplist00

// lazy Sequences: generators and coroutines (§10)
let fib = Sequence { var (a, b) = (0, 1); while true { yield a; (a, b) = (b, a + b) } }
print(fib.filter { $0 % 2 == 0 }.prefix(5))   // [0, 2, 8, 34, 144]

// Regex has a literal (round 86); a match with captures is a tuple
let when = "2026-09-03".firstMatch(/(?<y>\d+)-(?<m>\d+)-(?<d>\d+)/)
print(when.y, "a, b,,c".split(/,\s*/))        // 2026 ["a", "b", "c"]

// math is Double's (round 108); tasks are JS's (round 53)
print(Double.hypot(3, 4), [1.0, 4.0, 9.0].map(Double.sqrt))   // 5.0 [1.0, 2.0, 3.0]
let t = async { Task.sleep(0.01); "done" }
print(await t)

// modules are files (round 100): evaluated once, only exports cross
import G from "./geometry.swt"                // every export, as G.name; `import (area) from` for the named ones
print(G.area(3.0, 4.0), G.Point(x: 1.0, y: 2.0).scaled(2.0))   // 12.0 Point(x: 2.0, y: 4.0)
```

---

* **[documents/](documents/README.md)** — the type reference: every member of
  every type, one page per type.
* **[examples/](examples/README.md)** — runnable examples: quines, lambda
  calculus up to Z, SKI (`swift run swiftalk examples/lambda.swt`).
* **[Status.md](Status.md)** — what is implemented, with verified
  REPL transcripts, milestone by milestone.
* **[Design.md](Design.md)** — the design document: every decision,
  sectioned.
* **[Dialogue.md](Dialogue.md)** — the append-only dialogue log the
  language is being designed through.

```sh
swift run swiftalk   # the REPL — :h for its commands (:r redefines a binding, a type, or an extension's members; :d undefines)
swift run swiftalk -- --no-prelude   # bare: no IO, Net, Regex, Sequence, Task, BigInt, BigRat until a script imports them (rounds 187, 192, 201, 203); --help for the options
swift test           # the suite
```

**swiftalk in JavaScript** (rounds 197–200) lives in [js/](js/README.md):
the core runtime ported line for line, with the prelude as JS modules,
and checked against the Swift tests' own expectations — `cd js && npm
test` extracts every fixture from the Swift tests and runs it to the
Swift core's answer, all but six (Swift's Character-level Regex, listed
in the test so the list cannot rot). `node js/repl.mjs` is a
REPL over it, and `npm run build` makes `dist/notebook.html`, a
notebook of swiftalk cells that opens from a file.

The library is `Core/` — a dynamic library product in a package of
its own since round 182, so the CLI, the tests, and the native modules
(`modules/IO`, `Net`, `Regex`, `Sequence`, `Task`, `BigInt`, `BigRat`,
`POSIX`, built as `libIO.dylib` and so on — `BigInt` and `BigRat` sharing
`modules/BigNum`, the vendored engine, the same way) all share one copy
of it.
