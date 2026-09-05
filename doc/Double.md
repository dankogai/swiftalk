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

## `Double.` — the math library (round 108)

libm and JS's `Math`, as static members of `Double`. Constants are
read bare; functions are called, or taken uncalled as Function values
(`xs.map(Double.sqrt)`). Int arguments are promoted — the type is named
in the call — and results are Doubles, except an Int from `ilogb`, a
Bool from the predicates, and labeled tuples from `modf`/`frexp`/`remquo`.

| Member | Meaning |
|---|---|
| `pi`, `tau`, `e`, `ln2`, `ln10`, `log2e`, `log10e`, `sqrt2`, `sqrtHalf` | the constants (JS's `Math.E`, `LN2`… in lowerCamel; `sqrtHalf` is `SQRT1_2`) |
| `infinity`, `nan`, `greatestFiniteMagnitude`, `leastNormalMagnitude`, `leastNonzeroMagnitude`, `ulpOfOne` | Swift's |
| `abs`, `sqrt`, `cbrt`, `pow(x, y)`, `hypot(x, y, ...)` | `hypot` is n-ary, as JS's |
| `exp`, `exp2`, `expm1`, `log`, `log2`, `log10`, `log1p`, `logb` | |
| `sin cos tan`, `asin acos atan`, `atan2(y, x)`, `sinh cosh tanh`, `asinh acosh atanh` | |
| `floor`, `ceil`, `trunc`, `round`, `rint`, `nearbyint` | `round` is half away from zero (C's, Swift's — JS rounds half up: `Double.round(-2.5)` is -3 here, -2 in JS); `rint` to even |
| `sign(x)` | -1, 0, 1 as Doubles (±0 and NaN come back as they are) |
| `max(...)`, `min(...)` | n-ary |
| `fmod`, `remainder`, `remquo(x, y)` | `remquo` → `(remainder:, quotient:)` |
| `fma(x, y, z)`, `fdim`, `fmax`, `fmin`, `copysign`, `nextafter` | |
| `ldexp(x, n)`, `scalbn(x, n)`, `frexp(x)`, `ilogb(x)` | `n` an Int; `frexp` → `(fraction:, exponent:)`; `ilogb` → an Int |
| `modf(x)` | `(integer:, fraction:)` |
| `erf`, `erfc`, `tgamma`, `gamma`, `lgamma`, `j0`, `j1`, `jn(n, x)`, `y0`, `y1`, `yn(n, x)` | libm's specials and Bessel functions |
| `fround(x)` | JS's: rounded through a 32-bit float |
| `isNaN`, `isFinite`, `isInfinite`, `isZero`, `isNormal`, `isSubnormal` | Bools |
| `random()`, `random(max)`, `random(min, max)` | in [0, 1), [0, max), [min, max) — the system generator; bounds finite, min < max (round 112). Range is Int-only, so a Double's bounds are arguments |

Not carried over from JS: `clz32` and `imul` (Int's business — see
`leadingZeroBitCount`).
| `d < e` etc., `==` | Comparable, Equatable |
| `d.String()` | the shortest round-tripping decimal: `0.30000000000000004` |
| `d.String(.hex)` | hex float, `"0x1.fep7"` — re-enters as a literal |
| `d.Int()` | truncation toward zero; `nil` if unrepresentable |
| `d.debugDescription` | hex float |

```swift
(0.1 + 0.2).String()     // "0.30000000000000004"
Double("0x1.fep7")       // 255.0
0x1.999999999999ap-4 == 0.1   // true — debugPrint output round-trips
3.9.Int()                // 3
```

`radix:` is an Int format; `.oct`/`.bin` too. Double has `.hex` only.
