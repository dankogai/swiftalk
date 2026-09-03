# Bool

`true` and `false`. Nothing is truthy: `if`, `while`, `? :`, and
`filter` demand a Bool and reject everything else (§3b).

| Member / constructor | Result |
|---|---|
| `Bool()` | `false` |
| `Bool(b)` | `b` |
| `Bool("true")`, `Bool("false")` | the value; any other String → `nil` (failable) |
| `Bool(x)` for other types | type error |
| `b == c`, `b != c` | equality |
| `c ? a : b` | ternary (the `?` must be spaced; unspaced `?` is postfix propagate) |

```swiftalk
1 < 2               // true
Bool("yes")         // nil
true ? "y" : "n"    // "y"
```

There is no `&&`, `||`, or prefix `!` yet (OPEN) — `a ? b : false`,
`a ? true : b`, and `a ? false : true` spell them.
