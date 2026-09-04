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
| `Bool(i)` for an Int | `false` for 0, `true` otherwise (round 105) — a conversion, not truthiness: `if 3 { }` is still an error |
| `Bool(x)` for other types | type error |
| `b == c`, `b != c` | equality |
| `b &&= c`, `b ||= c` | `b = b && c` / `b = b || c`, short-circuit: `c` is evaluated only when `b` does not decide (round 104) |
| `b ^^ c`, `b ^^= c` | logical xor (round 106): true when exactly one is; both sides evaluated; sits between `&&` and `||` |
| `b.not()`, `b.and(c)`, `b.or(c)`, `b.xor(c)` | `!`, `&&`, `||`, `^^` as methods (round 106) — eager: a method evaluates its argument, `&&`/`||` do not always. The same names on an Int are bitwise |
| `c ? a : b` | ternary (the `?` must be spaced; unspaced `?` is postfix propagate) |
| `a && b` | logical and — short-circuit, Bool operands only (round 69) |
| `a \|\| b` | logical or — short-circuit, Bool operands only |
| `!a` | logical not (prefix; postfix `!` is force-unwrap) |

```swift
1 < 2               // true
Bool("yes")         // nil
true ? "y" : "n"    // "y"
```

Precedence is Swift's: `!` tightest, then comparison, `&&`, `||`, the
ternary loosest; `??` binds tighter than comparison. `1 && true` is a
type error. A lone `&` or `|` is a syntax error — bitwise operators
are undecided.

```swift
false && probe()          // probe never runs
d["k"] != nil && d["k"]! > 0
!true == false            // true — (!true) == false
```
