# Range

`a...b` (closed) and `a..<b` (half-open): first-class, **lazy**, and
Int-only — `BigInt` someday, `Double` never (round 38). A Range never
materializes unless asked; `(1...1000000000000).count` is O(1).
`a > b` traps.

| Member / constructor | Result |
|---|---|
| `Range(r)` | `r`; there is no other constructor — use the literal |
| `r.count` | element count, overflow-checked |
| `r[i]` | the i-th element (offset), bounds-checked; no writes |
| `for i in r` | iteration, element by element |
| `r.map` / `.filter` / `.reduce` | eager, yielding Arrays / a value |
| `r.prefix(n)` | the first n as an Array |
| `r.sorted { $0 > $1 }`, `r.contains(7)` | an Array / membership (round 83) |
| `r.Array()` | all elements as an Array |
| `r == s` | equality of bounds and kind |
| `case a...b:` | in a `switch`, a Range pattern matches an Int by containment |

```swiftalk
(1...5).Array()          // [1, 2, 3, 4, 5]
(5..<10)[0]              // 5
(1...20).reduce(1) { $0 * $1 }   // 2432902008176640000
```
