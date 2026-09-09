# Set

Swift's `Set` (round 132): an unordered collection of unique, Hashable
elements — and every swiftalk value is Hashable, so a Set holds
anything, Sets included. A **COW value** (§4), like Array and
Dictionary. There is no literal (Swift has none either): `Set([...])`
is the spelling, and the source form — `Set([1, 2, 3])`, elements
sorted by their source form, so two equal Sets print the same and
`eval(s.String()) == s`. A homogeneous Set infers `Set<T>`; the
annotation is Swift's generic spelling, `Set<Int>`, `Set<String>?`,
`Set<Set<Int>>`.

| Member / constructor | Result |
|---|---|
| `Set()` | the empty Set |
| `Set(seq)` | the distinct elements of any finite Sequence — an Array, a Range, a String's graphemes, a Data's bytes, a Dictionary's `(key:, value:)` pairs; `Set(0...)` is an error |
| `xs.Set()` | the same, by the conversion law (§3d) |
| `s.count` | elements |
| `s.contains(x)`, `s.contains { }` | membership / a predicate |
| `s.insert(x)` | adds `x`; `true` when it was new; needs a `var` root |
| `s.remove(x)` | removes `x`; the removed value or `nil`; needs a `var` root |
| `s == t` | equality — order is not a property a Set has |
| `s.union(t)`, `s.intersection(t)`, `s.subtracting(t)`, `s.symmetricDifference(t)` | new Sets; `t` a Set or any finite Sequence, as Swift's take |
| `s.isSubset(of: t)`, `s.isSuperset(of: t)`, `s.isStrictSubset(of: t)`, `s.isStrictSuperset(of: t)`, `s.isDisjoint(with: t)` | Bools; the labels optional, as Swift's labels are elsewhere |
| `for x in s` | iteration, in the Set's own order (unspecified, like a Dictionary's) |
| `s.map { }` | an **Array** (Swift-compatible) |
| `s.filter { }` | a **Set** (Swift-compatible) |
| `s.sorted()`, `s.sorted { }` | an Array — the way to a deterministic order |
| `s.reduce(init) { }`, `s.enumerated()`, `s.prefix(n)`, … | every Sequence member; slices and `enumerated()` are Arrays, an order having been imposed |
| `Array(s)`, `s.Array()` | the elements, in the Set's own order |
| `s.String()`, `s.String(.pretty)` | `Set([1, 2])`, sorted — re-enters |
| `s.String(.json)`, `s.String(.propertyList)` | a sorted **array** — JSON and property lists have no sets (lossy, as Data's base64 is); a Set is not a SION value |
| `d.keys` | a Dictionary's keys are a Set (round 132, revising 127): `d0 == d1` implies `d0.keys == d1.keys`, which no Array could promise |
| `[s: v]` | a Set is Hashable, so it is a Dictionary key |

No subscript: a Set has no positions. What is not here: `first`,
`min`/`max`, `popFirst` — OPEN, along with `Set` in SION.

```swift
var seen = Set<String>()          // or Set()
for word in text.split(" ") where !seen.contains(word) {
    seen.insert(word)
}
let common = Set(a).intersection(b)    // a, b Arrays
let d = ["x": 1, "y": 2]
d.keys == Set(["y", "x"])              // true
```
