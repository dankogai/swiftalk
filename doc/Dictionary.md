# Dictionary

`[Key: Value]` — the spelling that started the language. A **COW
value** (§4). Any Hashable value is a key (`1`, `"1"`, and `1.0` are
three keys), as SION allows. A homogeneous literal infers `[K: V]`
(round 59); `[:]` is untyped, `[Int: String]()` is not (round 165) —
a Dictionary remembers the key and value types it was built or bound
under, and `d.Type` reports them. **`nil` is a storable value** (round
35): `d[k] = nil` stores nil, presence is a separate question.

| Member / constructor | Result |
|---|---|
| `Dictionary()` | `[:]` |
| `Dictionary(pairs)`, `pairs.Dictionary()` | from any Sequence of `(key, value)` tuples (round 173) — `Array(d)`'s `(key:, value:)` pairs round-trip, any `(k, v)` builds, labels ignored; a duplicate key is an error (Swift's `uniqueKeysWithValues`, not JS's last-wins); stamped `[K: V]` by what the pairs infer, erased when they are mixed or none |
| `[Int: String]()` | the same, typed (round 165): an empty Dictionary that still refuses a String key or an Int value |
| `d.Type` | `[Int: String]` — the type with its parameters (round 165); a mixed or untyped-empty Dictionary's is the erased `Dictionary`. `d.Type == Dictionary` holds for every Dictionary |
| `[Int: String].Key`, `.Value`, `d.Type.Key` | the key and value types, `Int` and `String` (round 166); called, they construct. The erased `Dictionary.Key` is a type error |
| `d[k]` | the value, or `nil` when absent |
| `d[k] = v` | insert or replace (`v` may be `nil`); needs a `var` root |
| `d.has(k)` | presence — true for a key holding nil, false for a missing key |
| `d[k] ??= v` | set a default: writes `v` only when `d[k]` is nil (round 103) |
| `d.remove(k)` | deletes the entry; returns the removed value or `nil`; needs a `var` root |
| `d.subtract(keys)` | removes every listed key (round 133, as `delete`; Swift's Set name since 135): a Set or Array of keys, or another Dictionary's keys; returns `nil`; needs a `var` root |
| `d0 ?? d1`, `d0 ??= d1` | **fill in**: `d0`'s values kept, missing ones taken from `d1` — per key, `d0[k] ?? d1[k]`, so a stored `nil` is filled (round 130); `??=` in place on a `var` |
| `d0 !! d1`, `d0 !!= d1` | **override**: `d1`'s values win where it has one — `(d0 !! d1) == (d1 ?? d0)` by definition, so a `nil` in `d1` does not override (round 130); `!!=` in place. `merge` without a function is the lossier cousin: it writes `nil`s too |
| `d.merging(e)`, `d.merging(e) { current, new in }`, `d.merging(e, uniquingKeysWith:)` | a new Dictionary with `e`'s entries added (round 126); a shared key goes to the function, called as (current, new) — without one, **the new value wins** (Swift requires the function) |
| `d.merge(e)`, `d.merge(e) { current, new in }` | the same, in place; returns `nil`; needs a `var` root, and the lock still holds |
| `d.count` | entries (nil-valued ones included) |
| `d.enumerated()` | `d` itself (round 129): its pairs are `(key:, value:)` already, so there is nothing to number — code that enumerates "any collection" gets a Dictionary's own keys |
| `d.keys` | a **Set** of the keys (round 132, revising 127's Array): unordered and unique, so `d0 == d1` implies `d0.keys == d1.keys`; `d.keys.sorted()` for a list. A property, not a call: `d.keys()` is an error that says so |
| `d.values` | an **Array** of the values, in the Dictionary's own order — the order `for k, v in d` walks (round 127) |
| `d == e` | equality |
| `for pair in d`, `for k, v in d` | `(key:, value:)` tuples — order unspecified; `pair.key`/`pair.value`, `.0`/`.1`, or destructure |
| `d.map { k, v in }`, `d.map { "\($0)=\($1)" }` | an **Array** of results — the `(key, value)` pair is the argument list: `k`/`v`, or `$0`/`$1` (`$` is `[k, v]`) |
| `d.forEach { k, v in }` | the same walk for its effects; `nil` (round 156) |
| `d.filter { }` | a **Dictionary** of the kept pairs (Swift-compatible), with `d`'s key and value types (round 168) |
| `d.reduce(init) { }` | fold over pairs |
| `d.sorted { $0.key < $1.key }` | an Array of `(key:, value:)` pairs; bare `sorted()` is a type error — tuples are not Comparable (round 83) |
| `d.contains((k, v))`, `d.contains { k, v in }` | a pair by equality / a predicate (round 83) |
| `d.reversed()` | the `(key:, value:)` pairs as an Array, in the reverse of the Dictionary's own order (round 84); a `[Tuple]` even when empty (round 176) |
| `d.prefix(n)`, `d.suffix(n)`, `d.dropFirst(n)`, `d.dropLast(n)` | Dictionaries, in the Dictionary's own order (round 89); with `d`'s key and value types (rounds 168–169) |
| `d.String()`, `d.String(.pretty)` | source form with keys sorted — deterministic; `.pretty` lays it out one entry per line, two spaces a level (round 117) |

```swift
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
