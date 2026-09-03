# Dictionary

`[Key: Value]` — the spelling that started the language. A **COW
value** (§4). Any Hashable value is a key (`1`, `"1"`, and `1.0` are
three keys), as SION allows. A homogeneous literal infers `[K: V]`
(round 59); `[:]` is untyped. **`nil` is a storable value** (round
35): `d[k] = nil` stores nil, presence is a separate question.

| Member / constructor | Result |
|---|---|
| `Dictionary()` | `[:]` |
| `d[k]` | the value, or `nil` when absent |
| `d[k] = v` | insert or replace (`v` may be `nil`); needs a `var` root |
| `d.has(k)` | presence — true for a key holding nil, false for a missing key |
| `d.remove(k)` | deletes the entry; returns the removed value or `nil`; needs a `var` root |
| `d.count` | entries (nil-valued ones included) |
| `d == e` | equality |
| `for pair in d`, `for k, v in d` | `(key:, value:)` tuples — order unspecified; `pair.key`/`pair.value`, `.0`/`.1`, or destructure |
| `d.map { k, v in }`, `d.map { "\($0)=\($1)" }` | an **Array** of results — the `(key, value)` pair is the argument list: `k`/`v`, or `$0`/`$1` (`$` is `[k, v]`) |
| `d.filter { }` | a **Dictionary** of the kept pairs (Swift-compatible) |
| `d.reduce(init) { }` | fold over pairs |
| `d.sorted { $0.key < $1.key }` | an Array of `(key:, value:)` pairs; bare `sorted()` is a type error — tuples are not Comparable (round 83) |
| `d.contains((k, v))`, `d.contains { k, v in }` | a pair by equality / a predicate (round 83) |
| `d.String()` | source form with keys sorted — deterministic |

```swiftalk
var years = ["swift": 2014]
years["swiftalk"] = 2026
years["perl6"]                 // nil
years["perl6"] ?? 2015         // 2015
years["unknown"] = nil
years.has("unknown")           // true — stored nil
years.has("perl6")             // false — absent
years.filter { k, v in v > 2020 }   // ["swiftalk": 2026]
var sparse = [0: "zero", 1000000: "million"]   // a sparse array (round 59)
```
