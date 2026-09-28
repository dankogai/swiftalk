# BigInt

**Prelude** — the `BigInt` module, preimported by the CLI (`--no-prelude` skips it); `import from "BigInt"` otherwise, or `Interpreter.preimport(["BigInt"])`.

An arbitrary-precision integer — a **module's type with a literal of its
own** (round 201), the shape Regex set in round 186: the literal `123n`
is grammar, the type and its arithmetic are the **BigInt module**
(`modules/BigInt`, built as `libBigInt.dylib`; in the JavaScript
runtime, `js/src/modules/BigInt.js`). The literal is JavaScript's
spelling, and the `n` is mandatory: without it twenty digits are an Int
overflow. The literal calls the `BigInt` type in scope; without it, it
is an error naming the module. The Swift engine is
[swift-bignum](https://github.com/dankogai/swift-bignum)'s `BigInt`,
vendored into the module (not an SPM dependency); the JS engine is the
platform's own `BigInt`.

**Strict**, as swiftalk's numbers are (§3b): a BigInt meets a BigInt.
`1n + 1` is a type error that names the conversion; so are `1n == 1`
and `1n < 2`. `BigInt(x)` widens, `b.Int()` narrows (an overflow error
past 64 bits), `b.Double()` approximates.

| Form | Meaning |
|---|---|
| `123n`, `-1n`, `1_000n` | the literal, any size; `-1n` is prefix `-` on `1n` |
| `0xffn`, `0o17n`, `0b101n` | radix prefixes, as Int's |
| `1.5n`, `1e3n` | syntax errors — a BigInt literal is an integer |
| `BigInt()` | `0n` |
| `BigInt(i)`, `BigInt(byte)` | from an Int or a Byte, exactly |
| `BigInt(d)` | from an integral Double (`BigInt(1e3)` is `1000n`); `BigInt(1.5)` is an error |
| `BigInt("0xdead_beef")`, `BigInt("-12n")` | from the literal's spelling — sign, radix prefix, `_`, an optional `n` |
| `BigInt("zz", 36)` | bare digits in a radix 2...36 |
| `BigInt(b)`, `x.BigInt()` | itself; the round-47 law in both spellings |
| `b.Int()`, `Int(b)` | back to an Int, or an overflow error |
| `b.Double()`, `Double(b)` | the nearest Double |
| `b.String()`, `String(b)`, `"\(b)"` | `123n` — re-enters (§3d); `b.description` the same, `b.debugDescription` hex: `+0x7bn` |
| `b.String(.hex)`, `.oct`, `.bin` | `0xffn`, `-0o377n`, `0b101n` — literal-ready, prefixed |
| `b.String(16)`, `b.String(radix: 36)` | bare digits in that radix |
| `b.String(.sign)` | the decimal with its sign written: `+42` |

**Operators** — the core's, answered by the module (a host value's
`operate`, new in round 201, the hook a struct's operator members use):

| Operator | Meaning |
|---|---|
| `+ - *` | exact, never overflowing |
| `/` `%` | truncating division and its remainder, the dividend's sign — Int's rules; by zero, the core's error |
| `**` | `2n ** 256n`; a negative exponent is an error (no integer answer) |
| `-b`, `+b` | negation, identity |
| `== != < <= > >=` | Comparable among BigInts; `sorted()`, `min()`, `max()` work; a Dictionary key, a Set element |
| `+& +\| +^ +< +>`, `+^b` | Raku's bitwise operators (round 193), at any width — two's complement, an arithmetic right shift |
| `case 42n:` | in a `switch`, equality; an Int subject is no match, and as a binding's source an error |

**Members** — Swift's names where Swift has them:

| Member | Meaning |
|---|---|
| `b.magnitude` | `\|b\|`, a BigInt |
| `b.signum` | `-1`, `0`, `1` — an Int |
| `b.isZero` | whether zero |
| `b.bitWidth` | two's-complement bits, sign included: `255n.bitWidth` is 9 |
| `b.trailingZeroBitCount` | as Int's |
| `b.power(e)` | `b` to the `e` — an Int or BigInt, non-negative |
| `b.power(e, m)` | modular exponentiation, Python's three-argument `pow` |
| `b.squareRoot()` | ⌊√b⌋; negative, an error |
| `b.gcd(c)` | the greatest common divisor, non-negative |

```swift
let f = (1...30).reduce(1n) { acc, i in acc * BigInt(i) }   // 265252859812191058636308480000000n
BigInt(Int.max) + 1n                                        // 9223372036854775808n — Int would trap
(2n ** 100n).Int()                                          // overflow: ... does not fit in an Int
3n.power(100n, 7n)                                          // 4n
```

**Where the JS runtime differs**: nowhere in what is above; `bitWidth`
and the shifts are computed on the platform's BigInt to the same
answers.
