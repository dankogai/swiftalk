# Array

An ordered collection — a **COW value** (§4): assignment and passing
copy logically, mutation never leaks through an alias. A homogeneous
literal infers its element type and the binding **enforces** it
(round 59): `var a = [1, 2]` rejects `a.append("x")`. Mixed literals
bind only under `[Primitives]`, `SION`, or `Any`; `[]` is untyped.
Arrays are dense — a sparse array is a Dictionary.

| Member / constructor | Result |
|---|---|
| `Array()` | `[]` |
| `Array(seq)` | materializes any Sequence conformer |
| `a[i]` | element; Int index, bounds-checked (error out of range) |
| `a[i] = v` | write, through any path (`m[1][0] = 30`); needs a `var` root |
| `a.count` | length |
| `a.append(v, ...)` | appends in place; needs a `var` root |
| `a + b` | concatenation |
| `a == b` | element-wise equality |
| `a.map { }` | an Array of results |
| `a.filter { }` | an Array of the kept |
| `a.reduce(init) { acc, x in }` | fold |
| `a.prefix(n)`, `a.suffix(n)` | the first / last n; n clamps to the count |
| `a.dropFirst(n)`, `a.dropLast(n)` | all but the first / last n; `n` defaults to 1 (round 89) |
| `a.split(x)`, `a.split { }`, `a.split(separator:)`, `a.split(whereSeparator:)` | pieces between separators, as Arrays; empty pieces omitted, as Swift's (round 89) |
| `a.sorted()`, `a.sorted { a, b in }`, `a.sorted(by:)` | a new Array; bare needs Comparable elements (Int, Double, String, Date) — mixed is `<`'s type error (round 83) |
| `a.contains(x)`, `a.contains { }`, `a.contains(where:)` | equality (everything is Equatable) / predicate (round 83) |
| `a.reversed()` | a new Array (round 84) |
| `a.takeWhile { }`, `a.dropWhile { }` | the leading elements while the predicate holds / from its first miss on (round 88) |
| `a.joined()`, `a.joined(", ")`, `a.joined(separator:)` | Strings concatenate into a String; Arrays flatten into an Array (`[[1], [2]].joined([0])`); a mix is a type error (round 84) |
| `a.enumerated()` | an Array of `(index, element)` tuples (round 73) |
| `a.Array()` | `a` |
| `for x in a` | iteration |
| `for x in a where c` | iteration over `a.filter({ })`, the loop's names in `c` (round 82) |
| `a.Sequence()` | see [Sequence.md](Sequence.md) — an Array is *not* a lazy Sequence, but conforms |

```swiftalk
var primes = [2, 3, 5]
let snapshot = primes
primes.append(7)
primes[0] = 1
snapshot                              // [2, 3, 5] — a copy is a copy
(1...10).map { $0 * $0 }.filter { $0 / 2 * 2 == $0 }.reduce(0) { $0 + $1 }   // 220
[1, 2] + [3]                          // [1, 2, 3]
```

Not yet builtin (OPEN): `sort`, `contains`, `reverse`, `join`,
`insert`, `removeLast` — [eg/array.swt](../eg/array.swt) writes each
in a line or a loop.
