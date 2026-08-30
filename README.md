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

**Subscripts** are in — `d[k]` is flat-optional (`d[k] = nil` stores
nil; `d.has(k)` asks presence; `d.remove(k)` deletes), collections
are COW values, and `$0` is literally `$[0]`:

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

**Types are constructor `Function`s** — `.Type` returns the
constructor itself (à la JS `.constructor`), constructors carry
`.name`, `Type()` constructs, and `.conforms(to:)` asks the
protocol table:

```text
swiftalk> 42.Type
Int
swiftalk> 42.Type == Int
true
swiftalk> 42.Type.name
"Int"
swiftalk> Int("0xff")
255
swiftalk> Double("0x1.fep7")
255.0
swiftalk> Array.conforms(to: Sequence)
true
swiftalk> let make = { T, s in T(s) }
{ T, s in ... }
swiftalk> make(Double, "3.14")
3.14
```

**Lazy Sequences** are in — lazy *by default*, unlike Swift's opt-in
`.lazy`: `Sequence(state) { next }` generates, `map`/`filter` defer,
`.prefix(n)` materializes:

```text
swiftalk> let fib = Sequence([0, 1]) { $ = [$1, $0 + $1]; return $1 }.map { "\($0)" }
Sequence { ... }
swiftalk> fib.prefix(8)
["1", "1", "2", "3", "5", "8", "13", "21"]
```

**`.String()` formats** — argless is description (`"foo".String()`
is `"foo"`); quoting is explicit; `.hex`/`.oct`/`.bin` are
literal-ready while `radix:` is bare:

```text
swiftalk> "foo".String(.quoted)
"\"foo\""
swiftalk> 255.String(.hex)
"0xff"
swiftalk> 255.String(radix: 16)
"ff"
swiftalk> Int(255.String(.hex)) == 255
true
```

**`.todo`** is in — deferred initialization for named (and mutual)
recursion; a `let` holding `.todo` accepts exactly one assignment:

```text
swiftalk> let fact: Function = .todo
.todo
swiftalk> fact = { n in n < 2 ? n : n * fact(n - 1) }
{ n in ... }
swiftalk> fact(20)
2432902008176640000
swiftalk> fact = { 0 }
type error: cannot assign to let constant 'fact'
```

**Enums** are in — associated values, `switch` with `case let`
destructuring, `if case`, and runtime-enforced exhaustiveness:

```text
swiftalk> enum Shape {
........ case circle(r: Double)
........ case rect(w: Double, h: Double)
........ }
Shape
swiftalk> let area = { s in
........ switch s {
........ case .circle(let r): return 3.14159265358979 * r * r
........ case .rect(let w, let h): return w * h
........ }
........ }
swiftalk> area(Shape.rect(w: 3.0, h: 4.0))
12.0
swiftalk> Shape.circle(r: 2.5)
Shape.circle(r: 2.5)
swiftalk> Shape.circle(r: 2.5).Type == Shape
true
```

**Case accessors** — `.casename` gives the associated value or `nil`
(the piece Swift itself is missing) — and **structs** — COW values
with memberwise init:

```text
swiftalk> Shape.circle(r: 3.0).circle
3.0
swiftalk> Shape.circle(r: 3.0).rect == nil
true
swiftalk> struct Point {
........ var x: Int = 0
........ var y: Int = 0
........ }
Point
swiftalk> var p = Point(x: 3, y: 4)
Point(x: 3, y: 4)
swiftalk> let q = p
swiftalk> p.x = 30
swiftalk> q                      // a copy is a copy (§4)
Point(x: 3, y: 4)
```

**Methods and `init`** are in — methods are `let name = { ... }`
closure properties (`self` bound at invocation), and initializers
**multi-dispatch**:

```text
swiftalk> struct P {
........ var x: Int = 0
........ var y: Int = 0
........ let norm2 = { self.x * self.x + self.y * self.y }
........ init { v in self.x = v
........ self.y = v
........ }
........ }
P
swiftalk> P(3, 4).norm2()        // memberwise — the last dispatch candidate
25
swiftalk> P(7).norm2()           // the declared init
98
```

```sh
swift test
```
