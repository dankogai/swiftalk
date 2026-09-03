# enum

User-defined sum types (§7) with associated values, **case accessors**
(`s.circle` is the payload or `nil`), `switch` binding cases with
`case let r = .circle:`, and **runtime-enforced exhaustiveness**. Cases are *boxing* enums — unlike the flat built-in
unions `T?` and `Primitives`.

```swiftalk
enum Shape {
    case circle(r: Double)
    case rect(w: Double, h: Double)
    case point
    let describe = {                   // methods: let + closure
        switch self {
        case let r = .circle:    return "circle \(r)"
        case let (w, h) = .rect: return "rect \(w)x\(h)"
        case .point:             return "point"
        }
    }
}
```

| Form | Meaning |
|---|---|
| `Shape.circle(r: 2.5)`, `Shape.point` | construction; labels reorderable; declared payload types checked |
| `let s: Shape = .rect(w: 1.0, h: 2.0)` | leading-dot construction under an annotation |
| `s.circle` | **case accessor** (round 46): the payload when `s` IS that case, else `nil` — one payload bare, several as a **tuple labeled as the case declares** (round 77), none → the value itself |
| `if let r = s.circle { }`, `if let (w, h) = s.rect { }` | **the way to test-and-bind a case** — an ordinary `if let` on the accessor; labels work too: `if let (h: h, w: w) = s.rect`; `.circle` inside a method is `self.circle`; `let` is optional (round 78): `if r = s.circle { }` |
| `switch s { case let r = .circle: ... case let (w, h) = .rect: ... }` | the same accessor on the subject (round 78) — nil is the only "no", a misfit pattern is an error; `let` optional, `var` binds mutably; labels: `case (h: h, w: w) = .rect:`; bare `case .circle:` matches any payload; no match and no `default` is a runtime error |
| `if case .circle(let r) = s`, `case .circle(let r):` | **gone** (round 78) — syntax errors with a hint at the forms above |
| `let a = switch s { case let r = .circle: r * r default: 0.0 }` | **`switch` is an expression** (round 79): the chosen branch's last statement's value; so `{ s in switch s { ... } }` returns it |
| `case 1...5:` | a Range pattern matches an Int by containment |
| `s.m(args)` | methods, `self` bound; `switch self` inside |
| `s == t` | equality of case and payloads; `s.Type == Shape` |
| `s.String()` | `"Shape.circle(r: 2.5)"` — round-trips wherever Shape is declared |
| `extension Shape { let m = { } }` | adds methods |

```swiftalk
Shape.circle(r: 3.0).circle     // 3.0
Shape.circle(r: 3.0).rect       // nil
Shape.rect(w: 3.0, h: 4.0).rect // (w: 3.0, h: 4.0)
if let (w, h) = s.rect { print(w * h) }
```

`Result` is a built-in enum riding all of this — see
[Result.md](Result.md). Computed properties on enums are OPEN.
