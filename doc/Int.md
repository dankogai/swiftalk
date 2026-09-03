# Int

64-bit signed, everywhere (§3b) — never device-dependent. Arithmetic
**traps** on overflow and on division by zero; there is no silent
wraparound. Literals: decimal, `0xff`, `0o377`, `0b101`, with `_`
separators.

| Member / constructor | Result |
|---|---|
| `Int()` | `0` |
| `Int(i)` | `i` |
| `Int(d)` for a Double | truncation toward zero; `nil` if unrepresentable |
| `Int(s)` for a String | parses sign, `0x`/`0o`/`0b`, `_`; `nil` if malformed |
| `Int(x)` otherwise | type error |
| `i + j`, `i - j`, `i * j` | traps on overflow |
| `i / j` | integer division; `/ 0` is an error |
| `i < j` etc., `==` | Comparable, Equatable |
| `i.String()` | decimal, e.g. `"255"` |
| `i.String(.hex)` / `.oct` / `.bin` | prefixed, literal-ready: `"0xff"`, `"-0o377"`, `"0b11"` |
| `i.String(radix: n)` | bare digits, n in 2...36: `"ff"` |
| `i.Double()` | `Double(i)` |
| `i.debugDescription` | hex: `0xff` |

```swiftalk
9223372036854775807 + 1   // overflow: traps
Int("0xff")               // 255
255.String(.hex).Int()!   // 255 — prefixed forms round-trip
7 / 2                     // 3
1 + 1.5                   // type error: Int ≠ Double
```

Only Int bounds a `Range` (`1...10`); see [Range.md](Range.md).
