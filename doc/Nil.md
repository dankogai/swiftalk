# Nil

The type of `nil` — one value, its own type. `nil` is swiftalk's
`undefined`: absence, not a null object, and never `typeof null ===
"object"` (§3b). Optionals are flat (§3a): `Int?` is Int-or-nil, no
box, so `nil` in an `Int?` slot **is** `nil`.

```swiftalk
nil.Type            // Nil
nil == nil          // true
nil == 1            // false — the one cross-type equality allowed
var x: Int? = nil   // annotate: nil alone infers nothing
```

| Member | Result |
|---|---|
| `Nil()` | `nil` |
| `Nil(x)` | `nil` if `x` is nil; type error otherwise |
| `nil ?? d` | `d` |
| `nil?` | early-returns nil from the enclosing function (§3a/§8) |
| `nil!` | type error: force-unwrapped nil |
| `nil?.m` | `nil`, without evaluating the member or its arguments |

Dictionary lookups read `nil` for absent keys — and `nil` is also a
storable value; `.has(k)` tells them apart (round 35).
