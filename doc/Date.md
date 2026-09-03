# Date

A point in time: seconds since the Unix epoch, stored as a Double —
SION's own representation, printed in SION's own spelling
`.Date(epoch)` (round 50). The leading-dot form `.Date(x)` is a
type call: it re-enters.

| Member / constructor | Result |
|---|---|
| `Date()` | now (wall clock) |
| `Date(t)` | `t` |
| `Date(d)` for a Double, `Date(i)` for an Int | that epoch |
| `Date(x)` otherwise | type error |
| `t.Double()` | the epoch seconds |
| `t < u` etc., `==` | Comparable — `Date` is not comparable to a bare Double |
| `t.String()` | `".Date(1234567890.5)"` |
| `t.debugDescription` | hex-float epoch, as SION writes it — re-enters since round 59 |

```swiftalk
Date(0.0) < Date()          // true
Date(255.5).String()        // ".Date(255.5)"
.Date(42.0) == Date(42)     // true
```

OPEN: calendar output and arithmetic.
