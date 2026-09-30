# Date

**Core** — built into the interpreter, there in every embedding.

A point in time: seconds since the Unix epoch, stored as a Double —
SION's own representation, printed in SION's own spelling
`.Date(epoch)` (round 50). The leading-dot form `.Date(x)` is a
type call: it re-enters.

| Member / constructor | Result |
|---|---|
| `Date()` | now (wall clock) |
| `Date(t)` | `t` |
| `Date(d)` for a Double, `Date(i)` for an Int | that epoch |
| `Date(s)`, `s.Date()` | **the parse** (round 209): ISO 8601 in UTC as property lists spell it, `"2009-02-13T23:31:30Z"` (a fraction allowed); `nil` for anything else. `.Date()` is a String's alone: `1.5.Date()` is no member, `Date(1.5)` converts |
| `Date(x)` otherwise | type error |
| `t.String(.iso8601)` | that text — `Date(t.String(.iso8601)) == t` (round 209) |
| `Double(t)` | the epoch seconds (`t.Double()` is no member since round 206) |
| `t < u` etc., `==` | Comparable — `Date` is not comparable to a bare Double |
| `t.String()` | `".Date(1234567890.5)"` |
| `t.debugDescription` | hex-float epoch, as SION writes it — re-enters since round 59 |

```swift
Date(0.0) < Date()          // true
Date(255.5).String()        // ".Date(255.5)"
.Date(42.0) == Date(42)     // true
Date("2009-02-13T23:31:30Z").String(.iso8601)   // "2009-02-13T23:31:30Z"
```

OPEN: calendar arithmetic; ISO 8601 is the one calendar form (round 209).
