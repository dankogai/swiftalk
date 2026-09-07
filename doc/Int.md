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
| `i % j` | the remainder, the dividend's sign; `% 0` is an error (round 93) |
| `a.bitAnd(b)`, `a.bitOr(b)`, `a.bitXor(b)`, `a.bitNot()` | bitwise `& \| ^ ~` as methods (round 105; bit-prefixed since round 107 — `and`/`or`/`xor`/`not` are Bool's) — the symbols stay free |
| `a.shifted(by: n)` | `<<` for a positive `n`, `>>` (arithmetic, sign-filling) for a negative one; an overshift gives 0 or -1, as Swift's smart shift does |
| `a.bit(i)` | the `i`th bit as a Bool, `i` in 0..<64 |
| `a.bits` | the `[Bool]` view — 64 elements, bit 0 first |
| `Int(bits: [Bool])` | back from the view; fewer than 64 zero-extend, more is an overflow |
| `a.nonzeroBitCount`, `a.leadingZeroBitCount`, `a.trailingZeroBitCount` | Swift's own |
| `Int.min`, `Int.max`, `Int.bitWidth`, `Int.zero`, `Int.isSigned` | Swift's static properties (round 113): -2⁶³, 2⁶³-1, 64, 0, true |
| `Int.random(in: 1...6)`, `Int.random(0..<3)` | a random Int from a bounded, non-empty Range — the system generator (round 109); uncalled, a Function value. The only form: a Range says `f..<t` or `f...t` itself, and `Int.min...Int.max` is the whole line (round 120 took back a `to:`/`from:` spelling; Double's is different because Range is Int-only) |
| `i < j` etc., `==` | Comparable, Equatable |
| `i === j`, `i !== j` | the same type and the same value — `1 !== 1.0`, `Byte(1) !== 1`; never a type error (round 121) |
| `+i`, `-i` | prefix: the number itself / negation (`+` since round 121) |
| `i.String()` | decimal, e.g. `"255"` |
| `i.String(.hex)` / `.oct` / `.bin` | prefixed, literal-ready, **signed both ways**: `"+0xff"`, `"-0o377"`, `"+0b11"` (round 121 for `.hex`, 124 for the rest); the debug form stays unsigned |
| `i.String(radix: n)` | bare digits, n in 2...36: `"ff"` |
| `i.Double()` | `Double(i)` |
| `i.debugDescription` | hex: `0xff` |

```swift
9223372036854775807 + 1   // overflow: traps
Int("0xff")               // 255
255.String(.hex).Int()!   // 255 — prefixed forms round-trip ("+0xff")
7 / 2                     // 3
1 + 1.5                   // type error: Int ≠ Double
```

Only Int bounds a `Range` (`1...10`); see [Range.md](Range.md).
