# enum

User-defined sum types (§7) with associated values, `switch` with
`case let` destructuring, `if case`, and **runtime-enforced
exhaustiveness**. Cases are *boxing* enums — unlike the flat built-in
unions `T?` and `Primitives`.

```swiftalk
enum Shape {
    case circle(r: Double)
    case rect(w: Double, h: Double)
    case point
    let describe = {                   // methods: let + closure
        switch self {
        case .circle(let r): return "circle \(r)"
        case .rect(let w, let h): return "rect \(w)x\(h)"
        case .point: return "point"
        }
    }
}
```

| Form | Meaning |
|---|---|
| `Shape.circle(r: 2.5)`, `Shape.point` | construction; labels reorderable; declared payload types checked |
| `let s: Shape = .rect(w: 1.0, h: 2.0)` | leading-dot construction under an annotation |
| `s.circle` | **case accessor** (round 46): the payload when `s` IS that case, else `nil` — one payload bare, several as an Array, none → the value itself |
| `switch s { case .circle(let r): ... }` | destructuring; a case with no match and no `default` is a runtime error |
| `if case .circle(let r) = s { }` | single-pattern match |
| `case 1...5:` | a Range pattern matches an Int by containment |
| `s.m(args)` | methods, `self` bound; `switch self` inside |
| `s == t` | equality of case and payloads; `s.Type == Shape` |
| `s.String()` | `"Shape.circle(r: 2.5)"` — round-trips wherever Shape is declared |
| `extension Shape { let m = { } }` | adds methods |

```swiftalk
Shape.circle(r: 3.0).circle     // 3.0
Shape.circle(r: 3.0).rect       // nil
Shape.circle(r: 3.0).rect == nil   // true — "is it a rect?"
```

`Result` is a built-in enum riding all of this — see
[Result.md](Result.md). Computed properties on enums are OPEN.
