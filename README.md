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

**Mutating methods, implicit `self`, and extensions** are in —
mutation permission is the properties' `var`/`let` (no `mutating` keyword), and
leading-dot members mean `self.`:

```text
swiftalk> struct Stack {
........ var value: Array = []
........ let push = { item in .value.append(item) }
........ let top = { .value.count == 0 ? nil : .value[.value.count - 1] }
........ }
Stack
swiftalk> var s = Stack()
swiftalk> s.push(1)
swiftalk> s.push(2)
swiftalk> s.top()
2
swiftalk> extension Int { let doubled = { self * 2 } }
swiftalk> 21.doubled()
42
```

**`Data` and `Date`** are in — the SION roster is complete:

```text
swiftalk> "café".Data()
Data([99, 97, 102, 195, 169])
swiftalk> Data([255, 254]).String(.utf8) == nil    // failable decode
true
swiftalk> Date()
.Date(1788085109.733562)                           // SION's own spelling
swiftalk> Date(0.0) < Date()
true
```

**`Result` and the `?`/`!` family** are in — Result-first errors
(§8), no exceptions; one rule for absence and failure:

```text
swiftalk> let halve = { n in n / 2 * 2 == n ? Result.success(n / 2) : Result.failure("odd: \(n)") }
swiftalk> let quarter = { n in Result.success(halve(halve(n)?)?) }
swiftalk> quarter(8)
Result.success(2)
swiftalk> quarter(6)                 // the failure propagated through ?
Result.failure("odd: 3")
swiftalk> quarter(6) ?? -1
-1
swiftalk> ["k": [1, 2]]["k"]?.count
2
swiftalk> nil!
type error: force-unwrapped nil
```

**Coroutines and `yield`** are in — any function may `yield` (no
`function*`, the Lua model), and `Sequence(f)` wraps it into an
ordinary lazy Sequence — round 24's §2.4 example, verbatim but for
tuples:

```text
swiftalk> let fib = {
........ var a = 0
........ var b = 1
........ while true {
........ yield a
........ let t = a + b
........ a = b
........ b = t
........ }
........ }
{ ... }
swiftalk> Sequence(fib).prefix(8)
[0, 1, 1, 2, 3, 5, 8, 13]
swiftalk> fib.Sequence().filter { $0 / 2 * 2 == $0 }.prefix(3)
[0, 2, 8]
swiftalk> Sequence { yield "one"; yield "two" }.Array()
["one", "two"]
swiftalk> yield 1                    // Lua's rule
type error: 'yield' outside a coroutine — wrap the function: Sequence(f)
```

`yield` is dynamic, the Lua way: a helper function called from the
body yields on its behalf.

**`async`/`await`** are in — and swiftalk is **colorless**: no
function is marked `async` (the keyword survives only as spawn-site
sugar for `Task { ... }`, the way `mutating` and `func` fell before
it), any function may `await`, and top-level `await` just works:

```text
swiftalk> var log = []
[]
swiftalk> let t1 = async { log.append(1); sleep(0.03); log.append(3) }
Task { ... }
swiftalk> let t2 = async { log.append(2); sleep(0.01); log.append(4) }
Task { ... }
swiftalk> sleep(0.05)          // tasks interleave only at suspension points
swiftalk> log
[1, 2, 4, 3]
swiftalk> await async { 40 } + await async { 2 }
42
swiftalk> let f = { t in await t + 1 }    // colorless: any function may await
{ t in ... }
swiftalk> f(Task { 41 })
42
swiftalk> async { 1 }.Type == Task
true
```

Tasks are cooperative green threads on round 52's coroutine
substrate — deterministic, no preemption, and an `await` that can
never complete throws a deadlock error instead of hanging.

**Actors** are in — **swiftalk's first reference type** (`let b = a`
aliases; equality is identity), with colorless serialized calls,
isolation (reads open, writes only from the actor's own methods), and
each call **held to the end** — no mid-method interleaving, declining
Swift's reentrancy gotcha:

```text
swiftalk> actor Counter {
........ var count = 0
........ let bump = { let c = .count; sleep(0.01); .count = c + 1 }
........ }
Counter
swiftalk> let a = Counter()
Counter { count: 0 }
swiftalk> let t1 = async { a.bump() }
Task { ... }
swiftalk> let t2 = async { a.bump() }
Task { ... }
swiftalk> await t2
2
swiftalk> a.count                 // held to the end: no lost update
2
swiftalk> a.count = 99
type error: an actor's state is mutated only by its own methods — Counter.count is isolated
swiftalk> var g = 0               // the same dance on a bare var...
0
swiftalk> let racy = { let c = g; sleep(0.01); g = c + 1 }
{ ... }
swiftalk> let u1 = async { racy() }
Task { ... }
swiftalk> let u2 = async { racy() }
Task { ... }
swiftalk> await u2
1
swiftalk> g                       // ...loses an update — why actors exist
1
```

**`class`** is in — the open reference (an actor minus serialization
and isolation), with **single inheritance** and dynamic dispatch. Its
reason to exist: object graphs values can't express —

```text
swiftalk> class Node {
........ var value = 0
........ var next: Node? = nil
........ }
Node
swiftalk> let a = Node(value: 1)
Node { value: 1, next: nil }
swiftalk> let b = Node(value: 2)
Node { value: 2, next: nil }
swiftalk> a.next = b
Node { value: 2, next: nil }
swiftalk> b.next = a              // a cycle — impossible with COW values
Node { value: 1, next: Node { value: 2, next: Node { ... } } }
swiftalk> a.next.next == a
true
swiftalk> class Animal {
........ var name = "?"
........ let speak = { "..." }
........ let intro = { "\(.name) says \(.speak())" }
........ }
Animal
swiftalk> class Dog: Animal { let speak = { "woof" } }
Dog
swiftalk> Dog(name: "Rex").intro()    // dynamic dispatch, for real
"Rex says woof"
swiftalk> let pet: Animal = Dog(name: "Rex")
Dog { name: "Rex" }
```

When to use which: unshared state → `struct`; shared across tasks →
`actor`; identity without concurrency semantics (cycles, shared
nodes, hierarchies) → `class`. The test suite shows the round-54 lost
update returning the moment shared state is a class — classes give
identity, actors give safety.

**`super`** is in — class-only *by construction* (super goes where
override goes; override exists only where inheritance does; only
classes inherit). It resolves from the **declaring** class, so chains
never loop — while `self` stays dynamic inside, as in Swift:

```text
swiftalk> class A { let who = { "A" } }
A
swiftalk> class B: A { let who = { "B>" + super.who() } }
B
swiftalk> class C: B { let who = { "C>" + super.who() } }
C
swiftalk> C().who()
"C>B>A"
swiftalk> class P {
........ var x: Int = 0
........ init { v in self.x = v }
........ }
P
swiftalk> class Q: P {
........ var y: Int = 0
........ init { v in super.init(v)
........ self.y = v * 2
........ }
........ }
Q
swiftalk> Q(21)
Q { x: 21, y: 42 }
```

**Computed properties** are in — paren-less reads and code-running
assignment, for structs, classes, actors, and extensions (builtins
read-only):

```text
swiftalk> struct Temp {
........ var celsius = 0.0
........ var fahrenheit {
........ get { .celsius * 1.8 + 32.0 }
........ set { .celsius = (newValue - 32.0) / 1.8 }
........ }
........ }
Temp
swiftalk> var t = Temp()
Temp(celsius: 0.0)
swiftalk> t.fahrenheit
32.0
swiftalk> t.fahrenheit = 212.0
212.0
swiftalk> t.celsius
100.0
swiftalk> extension Int { var squared { self * self } }
swiftalk> 12.squared
144
```

On an actor, a computed setter is the actor's own code — callable
from outside and serialized like any method, while direct storage
writes stay isolated.

```sh
swift test
```
