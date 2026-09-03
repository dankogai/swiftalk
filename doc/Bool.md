# Bool

`true` and `false`. Nothing is truthy: `if`, `while`, `? :`, and
`filter` demand a Bool and reject everything else (§3b). The one
reading that is not a Bool test: a *bare variable* as an `if`/`while`
condition asks "not nil?" when it holds anything but a Bool — `if o {
o + 1 }` (round 80) — and inside, `o` is itself.

| Member / constructor | Result |
|---|---|
| `Bool()` | `false` |
| `Bool(b)` | `b` |
| `Bool("true")`, `Bool("false")` | the value; any other String → `nil` (failable) |
| `Bool(x)` for other types | type error |
| `b == c`, `b != c` | equality |
| `c ? a : b` | ternary (the `?` must be spaced; unspaced `?` is postfix propagate) |
| `a && b` | logical and — short-circuit, Bool operands only (round 69) |
| `a \|\| b` | logical or — short-circuit, Bool operands only |
| `!a` | logical not (prefix; postfix `!` is force-unwrap) |

```swiftalk
1 < 2               // true
Bool("yes")         // nil
true ? "y" : "n"    // "y"
```

Precedence is Swift's: `!` tightest, then comparison, `&&`, `||`, the
ternary loosest; `??` binds tighter than comparison. `1 && true` is a
type error. A lone `&` or `|` is a syntax error — bitwise operators
are undecided.

```swiftalk
false && probe()          // probe never runs
d["k"] != nil && d["k"]! > 0
!true == false            // true — (!true) == false
```
