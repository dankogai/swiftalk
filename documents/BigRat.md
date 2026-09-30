# BigRat

**Prelude** — the `BigRat` module, preimported by the CLI (`--no-prelude` skips it); `import from "BigRat"` otherwise, or `Interpreter.preimport(["BigRat"])`.

An exact rational — a BigInt over a BigInt, reduced on construction, the
sign in the numerator — as a module beside [BigInt](BigInt.md) (round
203): `modules/BigRat`, built as `libBigRat.dylib`; in the JavaScript
runtime, `js/src/modules/BigRat.js`. There is no literal: `BigRat(1, 3)`
is the constructor and the source form, and it re-enters (§3d). The Swift
engine is [swift-bignum](https://github.com/dankogai/swift-bignum)'s
`BigRat`, in the vendored library `modules/BigNum` the two modules share;
the JS engine is a pair of the platform's `BigInt`s.

`BigRat(1, 3) + BigRat(1, 3) + BigRat(1, 3) == BigRat(1)` is exactly
true, which is what the type is for. **Strict**, as swiftalk's numbers
are (§3b): a BigRat meets a BigRat. `BigRat(1, 2) + 1`, `r * 3n`, `r ==
0.5` are type errors that name the conversion; `BigRat(x)` widens from
an Int, a BigInt, or a Double, `r.BigInt()` and `Int(r)` truncate,
`Double(r)` is the nearest Double.

| Form | Meaning |
|---|---|
| `BigRat(n, d)` | from two Ints or BigInts (or a mix); reduced; `d` of `0` is the division-by-zero error |
| `BigRat(i)`, `BigRat(b)`, `BigRat(byte)` | an integer over `1` |
| `BigRat(d)` | the Double, **exactly**: `BigRat(0.1)` is `BigRat(3602879701896397, 36028797018963968)`; infinities and nan are errors |
| `BigRat("1/3")`, `BigRat("0.1")`, `BigRat("1e-2")`, `BigRat("42")` | from text: a fraction of integers (radix prefixes, `_`, a trailing `n` allowed), an integer, or a decimal with an optional exponent — `"0.1"` is `BigRat(1, 10)` |
| `BigRat()` | `BigRat(0, 1)` |
| `BigRat(r)`, `x.BigRat()` | itself; the round-47 law in both spellings |
| `r.numerator`, `r.denominator` | BigInts — the BigInt module's values, so they need it in scope (the prelude has both) |
| `Double(r)` | the nearest Double (`r.Double()` is no member — a String's parse, round 206) |
| `r.BigInt()`, `BigInt(r)`, `Int(r)` | truncation toward zero; `Int` overflows past 64 bits |
| `r.String()`, `String(r)`, `"\(r)"` | `BigRat(7, 3)` — re-enters; `r.description` the same, `r.debugDescription` hex: `BigRat(+0x7n, +0x3n)` |
| `r.String(.fraction)` | `7/3` |
| `r.String(.mixed)` | `2 1/3`; `-2 1/3`; `-1/3`; an integer as `2` |

**Operators** — the core's, answered by the module (a host value's
`operate`, round 201):

| Operator | Meaning |
|---|---|
| `+ - * /` | exact; `/` by zero is the core's error |
| `**` | an Int or BigInt exponent, negative allowed: `r ** -2` is the reciprocal's square; `0 ** -1` divides by zero |
| `-r`, `+r` | negation, identity |
| `== != < <= > >=` | by value: `BigRat(2, 4) == BigRat(1, 2)`; `sorted()`, `min()`, `max()`; a Dictionary key, a Set element |
| `case BigRat(1, 2):` | in a `switch`, equality; an Int subject is no match |

**Members** — Swift's names where Swift has them:

| Member | Meaning |
|---|---|
| `r.rounded()` | to the nearest integer, ties away from zero — Swift's default; a BigRat with denominator `1` |
| `r.rounded(.down)` | `.up`, `.down`, `.towardZero`, `.awayFromZero`, `.toNearestOrEven`, `.toNearestOrAwayFromZero` — Swift's rules |
| `r.isInteger` | whether the denominator is `1` |
| `r.isZero` | whether zero |
| `r.magnitude` | `\|r\|` |
| `r.signum` | `-1`, `0`, `1` — an Int |
| `r.reciprocal` | `d/n`; of zero, the division-by-zero error |
| `r.power(e)` | as `**` |

```swift
BigRat(1, 3) + BigRat(1, 6)                 // BigRat(1, 2)
BigRat(7, 3).rounded(.down).BigInt()        // 2n
Double(BigRat(2n ** 70n, 3))                // 3.935305402391371e+20
(1...10).reduce(BigRat(0)) { acc, i in acc + BigRat(1, i) }   // BigRat(7381, 2520) — the tenth harmonic number, exactly
```
