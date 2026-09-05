# swiftalk

an attempt to design a scripting language inspired by Swift —
the way JavaScript was "inspired" by Java.

The language is being designed through dialogue; every decision is
recorded in [Design.md](Design.md).

## swiftalk by example

A taste of the language as decided so far (§§1–11):

```swift
// bindings: type-locked at first assignment (§3), Int is 64-bit (§3b)
let fact20 = (1...20).reduce(1) { $0 * $1 }   // 2432902008176640000: still fits
var n = 42
// n = "42"                                   // runtime error: n is Int
// n = 1.5                                    // runtime error: Double ≠ Int

// dictionaries are [Key: Value] (§2.1); collections are COW values (§4)
var langs = ["swift": 2014, "smalltalk": 1972]
let snapshot = langs                          // logical copy
langs["swiftalk"] = 2026                      // snapshot unaffected

// optionals, full suite on the flat model (§3a)
if let year = langs["smalltalk"] {
    print("smalltalk: \(year)")
}
let y = langs["perl6"] ?? 2015
var maybe: Int? = langs["swift"]              // Int-or-nil, no box
maybe.Type                                    // Int (or Nil when nil)

// functions are closure literals (§2.4); labels optional & reorderable (§2.3)
let move = { x, y in x + y }
move(x: 1, y: 2)
move(y: 2, x: 1)                              // same call
move(1, 2)                                    // same call
let sum = { $.reduce(0) { $0 + $1 } }         // $ = the arguments (§2.4)
sum(1, 2, 3, 4)                               // 10; $.count was 4
let fac = { n in n < 2 ? 1 : n * $(n - 1) }   // $() = recurse (§2.4)
fac(20)                                       // 2432902008176640000

// enums with associated values, runtime-exhaustive switch (§7);
// switch is an expression — its branch's value is the closure's (round 79)
enum Shape {
    case circle(r: Double)
    case rect(w: Double, h: Double)
}
let area = { s in
    switch s {
    case let r = .circle:    3.14159265358979 * r * r
    case let (w, h) = .rect: w * h
    }   // a future third case reaching here without a match: runtime error
}

// Result-first errors, postfix ? to propagate (§8)
let readConfig = { path in
    let text = File.read(path)?               // failure returns early
    let json = JSON.parse(text)?              // (see §8 note on error types)
    return .success(Config(json))
}

// runtime type queries (§3) and obj.TypeName conversion (§3d)
let mixed: [Primitives] = [1, "one", 2.0]     // mixed literals annotate (§3c)
for x in mixed {
    print("\(x.String()): \(x.Type)")         // .String() is universal (§3d)
}
let answer = "42".Int() ?? 0                  // failable conversion + default
let hex    = 255.String(.hex)                 // "0xff"; radix: 16 for bare "ff"
let bytes  = "café".Data(.utf8)               // infallible; .Data("base64") is the literal
let text   = bytes.String(.utf8)              // String? — bytes may not be text
let src    = bytes.String()                   // .Data("Y2Fmw6k=") — SION; eval(src) == bytes

// SION is built in (round 97): the same values, three formats
let doc: SION = SION("[\"n\": 42, \"when\": .Date(0x0p+0)]")   // any SION text, comments and all
doc.String(.json)                             // {"n":42,"when":0.0}
SION(propertyList: doc.String(.propertyList)) == doc   // true; .Data(.propertyList) is bplist00

// math is built in (round 108): libm and JS's Math, as Double's static members
Double.hypot(3, 4)                            // 5.0 — Int arguments promote
[1.0, 4.0, 9.0].map(Double.sqrt)              // [1.0, 2.0, 3.0] — a function member is a value

// modules (round 100): a .swt file, evaluated once; only exports cross
import Geometry from "./geometry.swt"         // every export, as Geometry.name
import (area) from "./geometry.swt"           // the named ones, directly — the same instance
Geometry.area(3.0, 4.0) == area(3.0, 4.0)     // true

// Regex is a core type with a literal (round 86); a match with captures is a tuple
let when = "2026-09-03".firstMatch(/(?<y>\d+)-(?<m>\d+)-(?<d>\d+)/)   // (whole, y:, m:, d:)
when.y                                        // "2026"
"a, b,,c".split(/,\s*/)                       // ["a", "b", "c"]
```

---

* **[doc/](doc/README.md)** — the type reference: every member of
  every type, one page per type.
* **[eg/](eg/README.md)** — runnable examples: quines, lambda
  calculus up to Z, SKI (`swift run swiftalk eg/lambda.swt`).
* **[Status.md](Status.md)** — what is implemented, with verified
  REPL transcripts, milestone by milestone.
* **[Design.md](Design.md)** — the design document: every decision,
  sectioned.
* **[Dialogue.md](Dialogue.md)** — the append-only dialogue log the
  language is being designed through.

```sh
swift run swiftalk   # the REPL
swift test           # the suite
```
