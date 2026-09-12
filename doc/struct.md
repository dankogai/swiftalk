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
| `Point(7)`, `Complex(abs: 2.0, arg: 1.0)` | a declared `init { }` matching arity/labels — first match wins, so **declaration order disambiguates** (round 150): declare the primary init first and a same-arity labeled alternative after it — `init { real, imag in }` then `init { abs, arg in }` makes `Complex(1.0, 2.0)` rectangular and `Complex(abs: 2.0, arg: 1.0)` polar |
| `p.x` | property read; `p.x = v` write (needs a `var` root; `let` properties refuse) |
| `p.m(args)` | method call: `self` bound; leading-dot members (`.x`) mean `self.x` |
| `p.m` | the method, bound over a *copy* of self |
| `p.computed`, `p.computed = v` | runs the getter / setter; the setter's mutations write back COW-style |
| `p == q` | structural equality; `p.Type == Point`; `Point.name` |
| `p.String()` | `"Point(x: 3, y: 4)"` — round-trips wherever Point is declared |
| `p.String(.pretty)` | the same, one property per line, two spaces a level (round 118) |
| `let String = { "(\(.x), \(.y))" }`, `let Double = { … }` | **conversion members** (rounds 47, 151–152): `p.Double()` and `Double(p)` both run the member, format arguments as `$` (`$.contains(.hex)`); a `String` member owns `p`'s text **wherever it prints** — `p.String()`, `String(p)`, `print(p)`, `"\(p)"`, the REPL, `[p]`, `[p: 1]`, plain or `.pretty` — as Swift's `description` does; it must return a String |
| `p.description`, `p.debugDescription` | the **builtin** memberwise text, `"Point(x: 3, y: 4)"`, never the member's — so a `String` member may return `.description` for the forms it leaves alone (`String(self)` would recurse); `.String(.sion)`/`.json` on a container are data formats and stay builtin too |
| `static let origin = Self(x: 0, y: 0)`, `static let plus = { a, b in ... }` | **static members** (round 143), read off the type: `Point.origin`, `Point.plus(a, b)`; a `static let` holding a Function is a static method, uncalled it is the Function. Their own namespace beside the instance's; a stored `static var` does not exist (a type is a value, not storage) |
| `static var unit { Self(x: 1, y: 1) }` | a static computed property: a getter run on each read, no setter |
| *laziness* | a `static let` is evaluated on its first read, in the type's scope, and then kept — Swift's rule (round 149) — so statics may refer to one another in any order (`static let a = Self.b + 1` above `static let b`) and an init may use a static declared below it. A static that reaches for itself is an error, not a recursion; an initializer that fails is retried on the next read |
| `Self` | inside the body and its extensions, the type itself: `Self(x: 1)`, `Self.origin` |
| `infix(+) = { lhs, rhs in ... }`, `prefix(-) = { x in ... }`, `postfix(!) = { x in ... }` | **operators** (round 146): existing operators only, at their existing precedence, always the type's (no `static`, no `func`). Either operand's type answers an infix — `2 * z` and `z * 2` both reach it. Every spelling arrives: `a + b`, `a += b`, `(+)(a, b)`, `reduce(z, +)`. Implementable: infix `+ - * / % ** == != < <= > >= \| & ^`, prefix `- + !`, postfix `! ?`; not `&&`/`\|\|`/`^^` (short-circuit), `??`/`!!` (a value is never absent), `===`/`!==` (identity) |
| `infix(<)`, `infix(==)` | a comparison must return a Bool; `!=` is derived from `==`, and `>`, `<=`, `>=` from `<`, as Swift derives them — so one `<` makes the type Comparable: `sorted()`, `min()`, `max()`, `.conforms(to: Comparable)` follow |
| `extension Point { let m = { } ; var c { } ; static let s = ... }` | adds methods, computed properties, and statics |

**No `mutating` keyword** (round 50a): a method may mutate whatever
the properties' `var`/`let` allows; if it does, the change writes
back through the receiver, so a `let` receiver or a temporary errors
only when actually mutated. Observers (`willSet`/`didSet`) fire on
stored-property writes, stay silent during init, and a `didSet` may
reassign its own property without recursing. Properties are locked to
their annotation or their initial type (§3). Computed properties on
enums, and property observers outside types, are OPEN.
