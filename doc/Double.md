# Double

IEEE 754 binary64. `1.0`, `1e3`, and hex floats `0x1.fep7` are all
explicitly Double (round 59); `1` is explicitly Int, and the two never
mix in arithmetic without a conversion.

| Member / constructor | Result |
|---|---|
| `Double()` | `0.0` |
| `Double(d)` | `d` |
| `Double(i)` for an Int | `Double(i)` |
| `Double(s)` for a String | Swift's parser: decimal, `1e3`, hex floats; `nil` if malformed |
| `Double(t)` for a Date | the epoch seconds |
| `Double(x)` otherwise | type error |
| `d + e`, `d - e`, `d * e`, `d / e` | IEEE arithmetic (`/ 0.0` gives inf, no trap) |
| `d % e` | type error — as in Swift, no floating remainder operator (round 93) |
| `d < e` etc., `==` | Comparable, Equatable |
| `d.String()` | the shortest round-tripping decimal: `0.30000000000000004` |
| `d.String(.hex)` | hex float, `"0x1.fep7"` — re-enters as a literal |
| `d.Int()` | truncation toward zero; `nil` if unrepresentable |
| `d.debugDescription` | hex float |

```swiftalk
(0.1 + 0.2).String()     // "0.30000000000000004"
Double("0x1.fep7")       // 255.0
0x1.999999999999ap-4 == 0.1   // true — debugPrint output round-trips
3.9.Int()                // 3
```

`radix:` is an Int format; `.oct`/`.bin` too. Double has `.hex` only.
