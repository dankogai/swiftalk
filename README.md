# swiftalk

an attempt to design a scripting language inspired by Swift —
the way JavaScript was "inspired" by Java.

The language is being designed through dialogue; every decision is
recorded in [Design.md](Design.md).

## Status

**Milestone 0 — `eval()`** is underway: primitives, collection
literals (`[element]`, `[Key: Value]`), same-type arithmetic with
trapping overflow, `let`/`var` bindings with type locks, and the
round-trip law `eval(x.String()) == x`.

The embedding API lives in the `Swiftalk` namespace — importing the
library claims exactly one top-level name:

```swift
import Swiftalk

try Swiftalk.eval("(0.1 + 0.2).String()")   // .string("0.30000000000000004")
try Swiftalk.eval(#"[1, "one", 2.0]"#)      // heterogeneous — [Primitives], not [Any]
try Swiftalk.eval("0xff")                   // .int(255)
try Swiftalk.eval("1 + 1.5")                // throws Swiftalk.Error: Int ≠ Double
try Swiftalk.eval("9223372036854775807 + 1")// throws: overflow traps
try Swiftalk.eval("var x = 1\nx = \"1\"")   // throws: x is type-locked to Int
try Swiftalk.eval("var x: Int? = nil")      // flat optional: Int-or-nil, no box

let interp = Swiftalk.Interpreter()          // persistent environment
try interp.eval("var count = 1")
try interp.eval("count = count + 1")         // .int(2)
```

**Milestone 1 — REPL** is in:

```sh
swift run swiftalk
```

```text
swiftalk> x = 40          // REPL is relaxed: bare assignment declares a var
40
swiftalk> x = x + 2
42
swiftalk> x = "oops"      // ...but the type lock still holds
type error: cannot assign String to 'x' of type Int
swiftalk> [1, "one",      // open brackets continue onto the next line
........ 2.0]
[1, "one", 2.0]
```

Echoes are `.String()` source form — everything the REPL prints
re-enters as what it was.

**`{}` functions with `$`** are in — there is no `func`; a function
is a closure literal, `$` is the arguments, and `$()` recurses:

```text
swiftalk> let fac = { n in n < 2 ? 1 : n * $(n - 1) }
{ n in ... }
swiftalk> fac(20)
2432902008176640000
swiftalk> fac(21)
overflow: 21 * 2432902008176640000
swiftalk> let add = { x, y in x + y }
{ x, y in ... }
swiftalk> add(y: 2, x: 40)    // labels are optional and reorderable
42
swiftalk> { $.count }(1, 2, 3)
3
```

**Subscripts** are in — `d[k]` is flat-optional, `d[k] = nil`
deletes, collections are COW values, and `$0` is literally `$[0]`:

```text
swiftalk> var d = ["swift": 2014]
["swift": 2014]
swiftalk> d["swiftalk"] = 2026
2026
swiftalk> d["smalltalk"] == nil
true
swiftalk> var m = [[1, 2], [3, 4]]
[[1, 2], [3, 4]]
swiftalk> m[1][0] = 30
30
swiftalk> m
[[1, 2], [30, 4]]
```

**`if`/`else` and loops** are in, Swift-style — with ranges:

```text
swiftalk> let fib = { n in
........ var a = 0
........ var b = 1
........ for _ in 1...n {
........ let t = a + b
........ a = b
........ b = t
........ }
........ a
........ }
{ n in ... }
swiftalk> fib(90)
2880067194370816120
swiftalk> fib(93)
overflow: 4660046610375530309 + 7540113804746346429
```

**String interpolation** is in, Swift-style:

```text
swiftalk> let greet = { name in "hello, \(name)!" }
{ name in ... }
swiftalk> greet("swiftalk")
"hello, swiftalk!"
swiftalk> "0.1 + 0.2 = \(0.1 + 0.2), exactly"
"0.1 + 0.2 = 0.30000000000000004, exactly"
```

**`print()` and `debugPrint()`** are in — the first built-in
`Function` values (`print` shows Strings raw; `debugPrint` shows
source form) — which means FizzBuzz, at last:

```text
swiftalk> for i in 1...15 {
........ if i / 15 * 15 == i { print("FizzBuzz") }
........ else if i / 3 * 3 == i { print("Fizz") }
........ else if i / 5 * 5 == i { print("Buzz") }
........ else { print(i) }
........ }
1
2
Fizz
4
Buzz
...
```

**Trailing closures and `map`/`filter`/`reduce`** are in — the
design document's very first example now runs verbatim:

```text
swiftalk> let fact20 = (1...20).reduce(1) { $0 * $1 }
2432902008176640000
swiftalk> (1...10).filter { $0 / 2 * 2 == $0 }.map { $0 * $0 }.reduce(0) { $0 + $1 }
220
swiftalk> debugPrint(255, 255.0)   // debugDescription is hex, for the programmer
0xff 0x1.fep7
```

**`Range` and `Sequence`** are in — `Range` is first-class and lazy
(`Int` bounds only; `BigInt` someday, `Double` never), and `Array`,
`String`, `Dictionary`, `Range` uniformly drive `for`-`in`,
`map`/`filter`/`reduce`, `.count`, and `.Array()`:

```text
swiftalk> (1...1000000000000).count      // lazy — O(1), no array behind it
1000000000000
swiftalk> let r = 5..<10
5..<10
swiftalk> r.Array()
[5, 6, 7, 8, 9]
```

```sh
swift test
```
