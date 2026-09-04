# swiftalk — Status

What is implemented, feature by feature, with REPL transcripts
(every transcript is verified against the real REPL before it
lands). Moved out of [README.md](README.md) in round 65.


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

**`if let r = s.circle`** is the way (round 77) — the case accessor is
an ordinary `if let`; several payloads come back as a tuple labeled as
the case declares (`if case` is gone since round 78):

```text
swiftalk> enum Shape {
      case circle(r: Double)
      case rect(w: Double, h: Double)
  }
Shape
swiftalk> let s = Shape.rect(w: 3.0, h: 4.0)
Shape.rect(w: 3.0, h: 4.0)
swiftalk> s.rect
(w: 3.0, h: 4.0)
swiftalk> if let r = s.circle { print("circle", r) } else { print("not a circle") }
not a circle
swiftalk> if let (w, h) = s.rect { print(w * h) }
12.0
swiftalk> if let (h: h, w: w) = s.rect { print(w, h) }
3.0 4.0
```

**`case let r = .circle:`** (round 78) — a `switch` binds a case the
way `if let` does: the case accessor on the subject, nil the only
"no". And **`let` is optional** in every binding condition — an `=`
in a condition can only mean "bind", since assignment is a statement.
Swift's `if case` and `.circle(let r)` are gone, with hints:

```text
swiftalk> enum Shape {
      case circle(r: Double)
      case rect(w: Double, h: Double)
  }
Shape
swiftalk> let area = { s in
      switch s {
      case let r = .circle:    return 3.14159265358979 * r * r
      case let (w, h) = .rect: return w * h
      }
  }
{ s in ... }
swiftalk> area(Shape.rect(w: 3.0, h: 4.0))
12.0
swiftalk> let s = Shape.circle(r: 2.0)
Shape.circle(r: 2.0)
swiftalk> if r = s.circle { print("circle", r) }
circle 2.0
swiftalk> if (w, h) = s.rect { print(w * h) } else { print("not a rect") }
not a rect
swiftalk> switch s { case r = .circle: print("r =", r) case .rect: print("rect") }
r = 2.0
swiftalk> let d = [0: "a", 1: "b"]
[0: "a", 1: "b"]
swiftalk> var i = 0
0
swiftalk> while c = d[i] { print(c); i = i + 1 }
a
b
swiftalk> switch s { case .circle(let r): print(r) }
syntax error: case .circle(let x) is not swiftalk — write case let x = .circle (or case x = .circle)
swiftalk> if case .circle(let r) = s { }
syntax error: 'if case' is not swiftalk — write if let r = s.circle (or if r = s.circle)
```

**`switch` is an expression** (round 79, Swift 5.9's) — its value is
the chosen branch's last statement's value, the rule a closure body
already follows, so §14's `area` runs verbatim, without `return`:

```text
swiftalk> enum Shape {
      case circle(r: Double)
      case rect(w: Double, h: Double)
  }
Shape
swiftalk> let area = { s in
      switch s {
      case let r = .circle:    3.14159265358979 * r * r
      case let (w, h) = .rect: w * h
      }
  }
{ s in ... }
swiftalk> area(Shape.rect(w: 3.0, h: 4.0))
12.0
swiftalk> let name = switch 2 { case 1: "one" case 2: "two" default: "many" }
"two"
swiftalk> let sign = { n in return switch n { case 0: 0 case 1...100: 1 default: -1 } }
{ n in ... }
swiftalk> [sign(0), sign(7), sign(-7)]
[0, 1, -1]
swiftalk> 1 + switch true { case true: 1 case false: 2 }
2
swiftalk> switch 1 { case 1: let x = 10; x * 2 }
20
swiftalk> [1, 2, 3].map { switch $0 { case 2: "two" default: "other" } }
["other", "two", "other"]
swiftalk> switch 9 { case 1: 1 }
type error: switch is not exhaustive — nothing matches 9
```

**Regex** is a core type with a literal (round 86) — `/pattern/flags`,
Swift's engine, Swift's names on String; a match with captures is a
labeled tuple, so destructuring and `switch` bindings just work:

```text
swiftalk> /\d+/
/\d+/
swiftalk> /\d+/.Type
Regex
swiftalk> "hello 42 world 7".matches(/\d+/)
["42", "7"]
swiftalk> "2026-09-03".firstMatch(/(?<year>\d+)-(?<month>\d+)-(\d+)/)
("2026-09-03", year: "2026", month: "09", "03")
swiftalk> if let (_, y, m, d) = "2026-09-03".firstMatch(/(\d+)-(\d+)-(\d+)/) { print(y, m, d) }
2026 09 03
swiftalk> "ab".firstMatch(/a(x)?b/)
("ab", nil)
swiftalk> "a1b22c".replacing(/\d+/) { m in "<" + m + ">" }
"a<1>b<22>c"
swiftalk> "a, b,,c".split(/,\s*/)
["a", "b", "c"]
swiftalk> "Hello".contains(/hello/i)
true
swiftalk> let classify = { s in switch s { case /\d+/: "number" case /[a-z]+/i: "word" case let (_, u, v) = /(\w+)@(\w+)/: "mail \(u) at \(v)" default: "other" } }
{ s in ... }
swiftalk> [classify("42"), classify("Hi"), classify("dan@example"), classify("?!")]
["number", "word", "mail dan at example", "other"]
swiftalk> let x = 10
10
swiftalk> x / 2 / 5
1
swiftalk> /(/
syntax error: invalid regex /(/: expected ')'
```

**Data's Range subscript** (round 92) — reading and writing, plus byte
writes; a Data on the right of a Range write:

```text
swiftalk> var d = "hello".Data()
Data([104, 101, 108, 108, 111])
swiftalk> d[1..<3]
Data([101, 108])
swiftalk> d[1..<3].String(.utf8)
"el"
swiftalk> d[5...]
Data([])
swiftalk> d[2...9]
type error: range 2...9 is out of range (count 5)
swiftalk> d[0] = 72
72
swiftalk> d[1...] = "i!".Data()
Data([105, 33])
swiftalk> d.String(.utf8)
"Hi!"
swiftalk> d[d.count...] = Data([33])
Data([33])
swiftalk> d
Data([72, 105, 33, 33])
swiftalk> d[0..<1] = [9]
type error: assigning through a Range of a Data takes a Data, not a Array
swiftalk> d[0] = 256
type error: a Data byte is an Int in 0...255, not 256
```

**`a[0..<1] = [9]`** — assignment through a Range subscript (round 91):
Swift's `replaceSubrange`; the right side must be an Array of the
variable's element type:

```text
swiftalk> var a = [10, 20, 30, 40, 50]
[10, 20, 30, 40, 50]
swiftalk> a[0..<1] = [9]
[9]
swiftalk> a
[9, 20, 30, 40, 50]
swiftalk> a[1...2] = [1, 2, 3, 4]
[1, 2, 3, 4]
swiftalk> a[1...4] = []
[]
swiftalk> a[a.count...] = [7, 8]
[7, 8]
swiftalk> a[0..<1] = ["x"]
type error: cannot assign String to 'a'[0] of type Int
swiftalk> a[0..<1] = 5
type error: assigning through a Range takes an Array, not a Int
swiftalk> a[3...] = [1]
type error: range 3... is out of range (count 1)
```

**`a[1..<3]`** — Range subscripts on Arrays (round 90): a new Array of
those positions, Swift's bounds rule:

```text
swiftalk> let a = [10, 20, 30, 40, 50]
[10, 20, 30, 40, 50]
swiftalk> a[1..<3]
[20, 30]
swiftalk> a[1...2]
[20, 30]
swiftalk> a[3...]
[40, 50]
swiftalk> a[5...]
[]
swiftalk> a[1...][0]
20
swiftalk> a[1...5]
type error: range 1...5 is out of range (count 5)
swiftalk> var b = a[1...2]
[20, 30]
swiftalk> b.append(0)
swiftalk> a
[10, 20, 30, 40, 50]
swiftalk> a[0..<1] = [9]
type error: Array index must be an Int, not Range
```

**The slicing family** (round 89) — `suffix`, `dropFirst`, `dropLast`,
`split` on every Sequence conformer, shaped like the receiver
(`prefix` now too):

```text
swiftalk> [1, 2, 3, 4, 5].suffix(2)
[4, 5]
swiftalk> [1, 2, 3, 4, 5].dropFirst()
[2, 3, 4, 5]
swiftalk> [1, 2, 3, 4, 5].dropLast(2)
[1, 2, 3]
swiftalk> "héllo".prefix(2)
"hé"
swiftalk> "héllo".dropFirst()
"éllo"
swiftalk> (0...).dropFirst(3).prefix(2)
[3, 4]
swiftalk> [1, 0, 2, 0, 0, 3].split(0)
[[1], [2], [3]]
swiftalk> [1, 2, 3, 4, 5].split { $0 / 2 * 2 == $0 }
[[1], [3], [5]]
swiftalk> "a b  c".split { $0 == " " }
["a", "b", "c"]
swiftalk> (0...).suffix(2)
type error: an unbounded Range is infinite — .prefix(n) or .takeWhile it before .suffix
```

**`0...` and `takeWhile`/`dropWhile`** (round 88) — the unbounded range
is an infinite lazy Sequence conformer; the two new members are lazy
on it and on Sequence values, eager elsewhere:

```text
swiftalk> (0...).prefix(5)
[0, 1, 2, 3, 4]
swiftalk> for i in 10... { if i > 12 { break }; print(i) }
10
11
12
swiftalk> (0...).map { $0 * $0 }.prefix(4)
[0, 1, 4, 9]
swiftalk> (0...).takeWhile { $0 < 4 }.Array()
[0, 1, 2, 3]
swiftalk> (0...).dropWhile { $0 < 4 }.prefix(3)
[4, 5, 6]
swiftalk> (0...).count
type error: an unbounded Range is infinite — .prefix(n) or .takeWhile it deliberately
swiftalk> [1, 2, 3, 4, 1].takeWhile { $0 < 3 }
[1, 2]
swiftalk> "hello world".takeWhile { $0 != " " }
"hello"
swiftalk> let fib = Sequence { var a = 0; var b = 1; while true { yield a; (a, b) = (b, a + b) } }
Sequence { ... }
swiftalk> fib.takeWhile { $0 < 50 }.Array()
[0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
swiftalk> switch 42 { case 40...: "big" default: "small" }
"big"
```

**A Regex character is a grapheme** (round 87) — `.`, `\X`, and class
ranges work on the same clusters `count` counts; property classes
handle text with combining marks:

```text
swiftalk> let s = "e\u{301}🇯🇵a"
"é🇯🇵a"
swiftalk> s.count
3
swiftalk> s.matches(/./)
["é", "🇯🇵", "a"]
swiftalk> "か\u{309A}き".matches(/[\u{3040}-\u{309F}]/)
["き"]
swiftalk> "か\u{309A}き".matches(/\p{Hiragana}+/)
["か゚き"]
swiftalk> "🇯🇵🇺🇸".matches(/\p{RegionalIndicator}/)
["🇯🇵", "🇺🇸"]
swiftalk> /(?u)./
syntax error: invalid regex /(?u)./: unicode scalar semantic mode is not currently supported
```

**MySION — a SION parser in swiftalk** (round 85, `eg/sion.swt`,
write-up in [eg/sion.md](eg/sion.md)): swift-sion's README sample,
every literal form, and the round-trip law through it — no RegExp,
no String subscripts. Verified by `EgTests`, output line for line:

```sh
swift run swiftalk eg/sion.swt
```

```text
-42 42.195 true nil true
漢字、カタカナ、ひらがなの入ったstring😇
[nil, true, 1, 1.0, "one", [1], ["one": 1.0]]
["array": [], "bool": false, "dictionary": [:], "double": 0.0, "int": 0, "nil": nil, "string": ""]
.Date(0.0) Date
42 Data
Unlike JSON and Property Lists, / Yes, SION / does accept / non-String keys. / like / Map of ECMAScript.
...
true .Date(1234567890.5)
true Data([99, 97, 102, 195, 169])
expected ',' or ']' at 5
...
```

**`reversed` and `joined`** (round 84) — `reversed()` is always an
Array; `joined()` concatenates Strings or flattens Arrays, separator
optional:

```text
swiftalk> [1, 2, 3].reversed()
[3, 2, 1]
swiftalk> "héllo".reversed()
["o", "l", "l", "é", "h"]
swiftalk> "héllo".reversed().joined()
"olléh"
swiftalk> ["a", "b", "c"].joined(", ")
"a, b, c"
swiftalk> ["a", "b", "c"].joined(separator: "-")
"a-b-c"
swiftalk> [[1, 2], [3], []].joined()
[1, 2, 3]
swiftalk> [[1, 2], [3]].joined([0])
[1, 2, 0, 3]
swiftalk> (1...3).map { "\($0)" }.joined("+")
"1+2+3"
swiftalk> ["a", 1].joined()
type error: .joined of Strings met a Int — map it to a String first
```

**`sorted` and `contains`** on every Sequence conformer (round 83) —
Swift's spellings, with Swift's `by:`/`where:` labels accepted:

```text
swiftalk> [3, 1, 2].sorted()
[1, 2, 3]
swiftalk> [3, 1, 2].sorted { $0 > $1 }
[3, 2, 1]
swiftalk> "hello".sorted()
["e", "h", "l", "l", "o"]
swiftalk> let d = ["b": 2, "a": 1]
["a": 1, "b": 2]
swiftalk> d.sorted { $0.key < $1.key }
[(key: "a", value: 1), (key: "b", value: 2)]
swiftalk> d.sorted()
type error: '<' is not defined between Tuple and Tuple
swiftalk> [3, 1, 2].contains(2)
true
swiftalk> [3, 1, 2].contains(where: { $0 > 5 })
false
swiftalk> "hello".contains("ell")
true
swiftalk> d.contains(("a", 1))
true
swiftalk> let naturals = Sequence { var n = 0; while true { n = n + 1; yield n } }
Sequence { ... }
swiftalk> naturals.contains { $0 * $0 > 50 }
true
```

**`for x in s where cond`** (round 82) — `s.filter({ })` with the
loop's own names, decided element by element, so a lazy Sequence
stays lazy and `break`/`continue` work as ever:

```text
swiftalk> var evens = []
[]
swiftalk> for x in 1...10 where x / 2 * 2 == x { evens.append(x) }
swiftalk> evens
[2, 4, 6, 8, 10]
swiftalk> let d = ["a": 1, "b": 2, "c": 3]
["a": 1, "b": 2, "c": 3]
swiftalk> for k, v in d where v > 1 { print(k, v) }
b 2
c 3
swiftalk> for c in "hello" where c != "l" { print(c) }
h
e
o
swiftalk> let naturals = Sequence { var n = 0; while true { n = n + 1; yield n } }
Sequence { ... }
swiftalk> for n in naturals where n / 3 * 3 == n { if n > 10 { break }; print(n) }
3
6
9
swiftalk> for x in [1, 2, 3] where x { }
type error: a 'where' clause must be a Bool — nothing is truthy (§3b)
```

**`where` guards** on `switch` cases (round 81) — a Bool after the
pattern, seeing its bindings; false moves on to the next alternative.
`where` is contextual, and a guard belongs to the pattern it follows:

```text
swiftalk> enum Shape {
      case circle(r: Double)
      case rect(w: Double, h: Double)
  }
Shape
swiftalk> let describe = { s in
      switch s {
      case let r = .circle where r > 1.0: "big circle"
      case .circle:                      "small circle"
      case let (w, h) = .rect where w == h: "square \(w)"
      case let (w, h) = .rect:           "rect \(w)x\(h)"
      }
  }
{ s in ... }
swiftalk> [describe(Shape.circle(r: 2.0)), describe(Shape.circle(r: 0.5)), describe(Shape.rect(w: 2.0, h: 2.0)), describe(Shape.rect(w: 1.0, h: 2.0))]
["big circle", "small circle", "square 2.0", "rect 1.0x2.0"]
swiftalk> let classify = { n in switch n { case _ where n < 0: "negative" case 0: "zero" case 1...9 where n / 2 * 2 == n: "small even" case 1...9: "small odd" default: "large" } }
{ n in ... }
swiftalk> [classify(-3), classify(0), classify(4), classify(7), classify(50)]
["negative", "zero", "small even", "small odd", "large"]
swiftalk> let flag = false
false
swiftalk> switch 2 { case 1, 2 where flag: "guarded" default: "not" }
"not"
swiftalk> switch 2 { case 2 where 1: "x" }
type error: a 'where' guard must be a Bool — nothing is truthy (§3b)
swiftalk> let where = 3
3
```

**`if` is an expression** too (round 80), `if let` and `else if`
included — the taken branch's last value, nil when none runs. And
**`if o { }`** on a bare optional variable asks non-nil; inside, `o`
is simply itself (flat optionals leave nothing to strip, and no shadow
is made, so a drain loop writes through). Anything that is not a bare
variable still needs a Bool — or a capture, `if x = Int(s) { }`:

```text
swiftalk> let o: Int? = 7
7
swiftalk> if o { o + 1 }
8
swiftalk> let none: Int? = nil
swiftalk> if none { none } else { "nil" }
"nil"
swiftalk> let x = if o { o * 2 } else { 0 }
14
swiftalk> let sign = { n in if n > 0 { 1 } else if n < 0 { -1 } else { 0 } }
{ n in ... }
swiftalk> [sign(5), sign(-5), sign(0)]
[1, -1, 0]
swiftalk> struct Node { var value: Int; var next: Node? = nil }
Node
swiftalk> var node: Node? = Node(value: 1, next: Node(value: 2, next: nil))
Node(value: 1, next: Node(value: 2, next: nil))
swiftalk> var seen = []
[]
swiftalk> while node { seen.append(node.value); node = node.next }
swiftalk> seen
[1, 2]
swiftalk> if Int("x") { 1 }
type error: the 'if' condition must be a Bool — nothing is truthy (§3b)
swiftalk> if x = Int("x") { x } else { -1 }
-1
```

**`while let`** is in (round 76) — `if let`'s condition list, re-evaluated
with fresh bindings each pass; the grammar is documented in
[doc/grammar.md](doc/grammar.md):

```text
swiftalk> let d = [0: "a", 1: "b", 2: "c"]
[0: "a", 1: "b", 2: "c"]
swiftalk> var i = 0
0
swiftalk> var out = ""
""
swiftalk> while let x = d[i] { out = out + x; i = i + 1 }
swiftalk> out
"abc"
swiftalk> i = 0
0
swiftalk> var sum = 0
0
swiftalk> while let x = d[i], x != "c" { sum = sum + 1; i = i + 1 }
swiftalk> sum
2
```

**Labeled destructuring** is in (round 75) — a labeled pattern element
binds by label, so patterns reorder freely; everywhere patterns live:

```text
swiftalk> let t = (x: 1, y: 2)
(x: 1, y: 2)
swiftalk> let (y: b, x: a) = t           // by label, any order
(x: 1, y: 2)
swiftalk> [a, b]
[1, 2]
swiftalk> for (value: v, key: k) in ["a": 40] { print(k, v) }
a 40
swiftalk> var p = 0
0
swiftalk> var q = 0
0
swiftalk> (y: q, x: p) = t               // assignment by label
(x: 1, y: 2)
swiftalk> [p, q]
[1, 2]
swiftalk> let (x: c, z: d) = t
type error: the tuple has no element labeled 'z'
```

**Labeled tuples** are in (round 74) — labels name positions and are
otherwise cosmetic; Dictionary pairs are `(key:, value:)`, `enumerated()`
gives `(offset:, element:)`:

```text
swiftalk> let p = (x: 1, y: 2)
(x: 1, y: 2)
swiftalk> p.x
1
swiftalk> p.1                             // positions still work
2
swiftalk> p == (1, 2)                     // labels are cosmetic
true
swiftalk> var q = p
(x: 1, y: 2)
swiftalk> q.y = 20
20
swiftalk> q
(x: 1, y: 20)
swiftalk> for pair in ["a": 1] { print(pair.key, pair.value) }
a 1
swiftalk> ["x", "y"].enumerated()
[(offset: 0, element: "x"), (offset: 1, element: "y")]
swiftalk> p.z
unknown member: Tuple.z
```

**A tuple is a rigid Array of arguments, and `.enumerated()`** are in
(round 73, correcting 72): a sole tuple argument IS the argument list
— `$` holds its elements:

```text
swiftalk> let d = ["k": 7]
["k": 7]
swiftalk> d.map { "\($0)=\($1)" }        // $0 is k, $1 is v
["k=7"]
swiftalk> d.map { $ }                     // $ is the rigid Array
[["k", 7]]
swiftalk> ["a", "b"].enumerated()       // (offset:, element:) since round 74
[(offset: 0, element: "a"), (offset: 1, element: "b")]
swiftalk> for i, x in ["a", "b"].enumerated() { print(i, x) }
0 a
1 b
swiftalk> let naturals = Sequence { var n = 10; while true { yield n; n = n + 1 } }
Sequence { ... }
swiftalk> naturals.enumerated().prefix(2)  // lazy — infinite is fine
[(offset: 0, element: 10), (offset: 1, element: 11)]
swiftalk> let g = { t in t.count }
{ t in ... }
swiftalk> g((1, 2))                       // a 2-tuple is two arguments
type error: expected 1 argument(s), got 2
swiftalk> g(((1, 2),))                    // a 1-tuple passes it whole
2
```

**`if let` destructuring, `for k, v in`, and tuple splat** are in
(round 72) — a single N-tuple argument spreads into N parameters, so
Dictionary closures read naturally:

```text
swiftalk> for k, v in ["x": 9] { print(k, v) }
x 9
swiftalk> ["a": 1].map { k, v in "\(k)=\(v)" }
["a=1"]
swiftalk> ["a": 1, "b": 2].filter { k, v in v > 1 }
["b": 2]
swiftalk> let pairs = ["p": (1, 2)]
["p": (1, 2)]
swiftalk> if let (a, b) = pairs["p"] { print(a + b) } else { print("none") }
3
swiftalk> if let (a, b) = pairs["q"] { print(a + b) } else { print("none") }
none
swiftalk> let f = { x, y in x + y }
{ x, y in ... }
swiftalk> f((40, 2))                  // the splat: one 2-tuple, two parameters
42
```

**Tuple destructuring** is in (round 71) — `let (a, b) = t`, `var`,
`_`, nesting; destructuring assignment (the swap works: the right side
evaluates whole first); `for (k, v) in dict`:

```text
swiftalk> var (x, y) = (0, 1)
(0, 1)
swiftalk> (x, y) = (y, x + y)
(1, 1)
swiftalk> let fib = { n in
      var (a, b) = (0, 1)
      for _ in 1...n { (a, b) = (b, a + b) }
      return a
  }
{ n in ... }
swiftalk> fib(90)                     // §2.4's example, verbatim at last
2880067194370816120
swiftalk> var p = 1
1
swiftalk> var q = 2
2
swiftalk> (p, q) = (q, p)             // the swap
(2, 1)
swiftalk> let (a, b) = (1, 2, 3)
type error: cannot destructure a 3-tuple into 2 names
```

**Tuples** are in (round 70) — a grab bag: one `Tuple` type, `.0`/`.1`,
`.count`, values through and through; Dictionaries yield `(key, value)`:

```text
swiftalk> let t = (1, "one", 2.0)
(1, "one", 2.0)
swiftalk> t.1
"one"
swiftalk> t.Type
Tuple
swiftalk> ((1, 2), (3, 4)).1.0      // nests — 0.1 is not a Double here
3
swiftalk> var u = (1, 2)
(1, 2)
swiftalk> u.0 = 9
9
swiftalk> u
(9, 2)
swiftalk> (7,)                      // the 1-tuple; (42) merely groups
(7,)
swiftalk> for pair in ["a": 1] { print(pair.0, pair.1) }
a 1
swiftalk> [(0, 0): "origin"][(0, 0)]
"origin"
```

**Logical operators** are in (round 69) — `&&`, `||`, prefix `!`,
exactly Swift's: Bool-only, short-circuit, Swift's precedence:

```text
swiftalk> true && false || true
true
swiftalk> !true == false            // (!true) == false
true
swiftalk> var hit = false
false
swiftalk> let probe = { hit = true; return true }
{ ... }
swiftalk> false && probe()          // short-circuit: probe never runs
false
swiftalk> hit
false
swiftalk> 1 && true                 // nothing is truthy
type error: '&&' takes Bools — nothing is truthy (§3b)
swiftalk> 1 & 2
syntax error: unexpected '&' — did you mean '&&'?
```

**The type reference** is in (round 68): [doc/](doc/README.md), one
page per type, every member, verified against the evaluator.

**Script mode** is in (round 66): `swift run swiftalk file.swt`
evaluates the whole file as one strict program — no echoes, only
`print()` output. Examples live in [eg/](eg/README.md): two quines,
lambda calculus up to the Z combinator, SKI, and the collection
types (Array, Dictionary, Sequence) — each verified by the test
suite.

**Milestone 1 — REPL** is in — with line editing and **history**
(round 64): arrow keys browse (persisted in `~/.swiftalk_history`),
emacs keys edit (`^A ^E ^K ^U ^W ...`), `^C` cancels the pending
statement, multi-line paste works. Pure Swift on termios — no
readline, no libedit, no dependencies:

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
  2.0]
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
  var a = 0
  var b = 1
  for _ in 1...n {
  let t = a + b
  a = b
  b = t
  }
  a
  }
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
  if i / 15 * 15 == i { print("FizzBuzz") }
  else if i / 3 * 3 == i { print("Fizz") }
  else if i / 5 * 5 == i { print("Buzz") }
  else { print(i) }
  }
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

**Enums** are in — associated values, `switch` binding cases with
`case let r = .circle` (round 78), and runtime-enforced exhaustiveness:

```text
swiftalk> enum Shape {
  case circle(r: Double)
  case rect(w: Double, h: Double)
  }
Shape
swiftalk> let area = { s in
  switch s {
  case let r = .circle:    return 3.14159265358979 * r * r
  case let (w, h) = .rect: return w * h
  }
  }
{ s in ... }
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
  var x: Int = 0
  var y: Int = 0
  }
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
  var x: Int = 0
  var y: Int = 0
  let norm2 = { self.x * self.x + self.y * self.y }
  init { v in self.x = v
  self.y = v
  }
  }
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
  var value: Array = []
  let push = { item in .value.append(item) }
  let top = { .value.count == 0 ? nil : .value[.value.count - 1] }
  }
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
  var a = 0
  var b = 1
  while true {
  yield a
  let t = a + b
  a = b
  b = t
  }
  }
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

**Actors, `class`, and `super`** were built (rounds 54–56) and are
now **shelved** (round 62) — the reference types made swiftalk feel
too much like Swift. Their designs stand in [Design.md](Design.md)
§4/§12, the machinery stays in-tree, and their tests sleep under
`.disabled("shelved")`, ready to re-arm. Until then swiftalk is
values + coroutines + tasks — and `class`, like `guard`, is just an
identifier.

**Computed properties** are in — paren-less reads and code-running
assignment, for structs and extensions (builtins read-only):

```text
swiftalk> struct Temp {
  var celsius = 0.0
  var fahrenheit {
  get { .celsius * 1.8 + 32.0 }
  set { .celsius = (newValue - 32.0) / 1.8 }
  }
  }
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

(The actor/class halves of computed properties are shelved with
their types — round 62.)

**The call convention, simplified** (round 61 — "swiftalk is getting
too close to swift"): one function notation, `{ x, y in ... }` (round
58a's `let f(x:y:)` sugar is reverted); the declared names are the
labels — reorderable, positional when omitted; `_` declares a
positional-only slot; undefined labels raise; multi-dispatch belongs
to Type `init`s alone. And **`willSet`/`didSet`** observers, silent
during init, clamp-safe:

```text
swiftalk> let f = { x, y in x * x + y * y }
{ x, y in ... }
swiftalk> f(y: 4, x: 3)
25
swiftalk> f(3, 4)                 // omitted labels are positional
25
swiftalk> let g = { _, x, y in "\($0) \(x) \(y)" }
{ _, x, y in ... }
swiftalk> g(5, x: 4, y: 3)        // _ takes no label, binds no name
"5 4 3"
swiftalk> f(x: 3, z: 4)
type error: unknown argument label 'z'
swiftalk> var log = []
[]
swiftalk> struct Score {
  var points = 0 {
  willSet { log.append("will \(.points) -> \(newValue)") }
  didSet(old) { log.append("did \(old) -> \(.points)")
  if .points > 100 { .points = 100 }
  }
  }
  }
Score
swiftalk> var s = Score()
Score(points: 0)
swiftalk> s.points = 500
500
swiftalk> s.points                // the didSet clamp — no recursion
100
swiftalk> log
["will 0 -> 500", "did 0 -> 500"]
```

**Type inference** is in — homogeneous-or-annotate: collections infer
element types and the locks enforce them; mixed literals bind only
under `[Primitives]`, `SION`, or `Any`; and hex-float literals close
the debug round trip:

```text
swiftalk> let ary = [0, 1, 2, 3]        // [Int]
[0, 1, 2, 3]
swiftalk> let bad = [0.0, 1, 2, 3]
type error: cannot infer one element type for 'bad' (Double vs Int) — annotate it: [Primitives], SION, or Any
swiftalk> let ok: [Primitives] = [0.0, 1, 2, 3]
[0.0, 1, 2, 3]
swiftalk> var a = [1, 2]
[1, 2]
swiftalk> a.append("x")                 // the inferred [Int] lock enforces
type error: cannot assign String to 'a'[2] of type Int
swiftalk> let dict = [0: "zero", 1: "one"]   // [Int: String] — sparse
[0: "zero", 1: "one"]                        // arrays are Dictionaries
swiftalk> dict[9] == nil
true
swiftalk> 0x1.fep7                      // hex floats lex at last:
255.0
swiftalk> debugPrint(0.1)               // ...debug output re-enters
0x1.999999999999ap-4
swiftalk> 0x1.999999999999ap-4 == 0.1
true
```

**`if let`** is in — comma chains, `if var`, the Swift 5.7 shorthand
(and, since round 80, `if x { }` with no `let` at all).
**`guard` is not**, and never will be: "it is only `if not`" — the
keyword graveyard (§9) now holds `func`, `mutating`, `async`-as-color,
and `guard`:

```text
swiftalk> let ages = ["alice": 42]
["alice": 42]
swiftalk> if let age = ages["alice"], age < 100 { print("alice is \(age)") } else { print("unknown") }
alice is 42
swiftalk> let x: Int? = 41
41
swiftalk> if let x { print(x + 1) }     // the 5.7 shorthand
42
swiftalk> let guard = "just an identifier"
"just an identifier"
```

```sh
swift test
```

