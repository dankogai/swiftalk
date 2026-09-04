# struct

User-defined value types (§4): **COW values**, memberwise-constructed,
with methods as closure properties. Declaration grammar:

```swift
struct Point {
    var x: Int = 0                     // stored: annotation and/or default
    let tag = "pt"                     // let: immutable after init
    var norm2 { .x * .x }              // computed (round 57), read-only
    var doubled {                      // computed with get/set
        get { .x * 2 }
        set { .x = newValue / 2 }
    }
    var y = 0 { didSet { .y = .y < 0 ? 0 : .y } }   // observers (round 58b)
    let shift = { d in .x = .x + d }   // a method: let + closure literal
    init { v in self.x = v             // inits multi-dispatch (round 48)
        self.y = v }
}
```

| Form | Meaning |
|---|---|
| `Point(x: 3, y: 4)`, `Point(3, 4)` | memberwise init: labels optional & reorderable, positionals in declaration order, defaults fill the rest — the LAST dispatch candidate |
| `Point(7)` | a declared `init { }` matching arity/labels — first match wins |
| `p.x` | property read; `p.x = v` write (needs a `var` root; `let` properties refuse) |
| `p.m(args)` | method call: `self` bound; leading-dot members (`.x`) mean `self.x` |
| `p.m` | the method, bound over a *copy* of self |
| `p.computed`, `p.computed = v` | runs the getter / setter; the setter's mutations write back COW-style |
| `p == q` | structural equality; `p.Type == Point`; `Point.name` |
| `p.String()` | `"Point(x: 3, y: 4)"` — round-trips wherever Point is declared |
| `extension Point { let m = { } ; var c { } }` | adds methods and computed properties |

**No `mutating` keyword** (round 50a): a method may mutate whatever
the properties' `var`/`let` allows; if it does, the change writes
back through the receiver, so a `let` receiver or a temporary errors
only when actually mutated. Observers (`willSet`/`didSet`) fire on
stored-property writes, stay silent during init, and a `didSet` may
reassign its own property without recursing. Properties are locked to
their annotation or their initial type (§3). Computed properties on
enums, and property observers outside types, are OPEN.
