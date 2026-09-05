# Byte

`Data`'s element type (round 116) — Swift's `UInt8`. **A Byte is an Int
that fits a byte**: `Byte op Byte` is a Byte, trapping as `UInt8`
does; `Byte op Int` is an Int; comparison and equality are by value,
so `Byte(33) == 33` and a Byte hashes as the Int it equals. Type
locks still tell them apart: `x.Type == Byte`, and a `Byte` will not
land in an `Int`-locked variable.

| Member / constructor | Result |
|---|---|
| `Byte()` | `Byte(0)` |
| `Byte(b)` | `b` |
| `Byte(i)` for an Int | the byte, or `nil` outside 0...255 |
| `Byte(d)` for a Double | truncated toward zero, then as for an Int |
| `Byte(s)` for a String | parsed as `Int(s)` is, then as for an Int |
| `Byte.min`, `Byte.max`, `Byte.bitWidth`, `Byte.zero`, `Byte.isSigned` | `Byte(0)`, `Byte(255)`, 8, `Byte(0)`, false |
| `b + c`, `b - c`, `b * c`, `b / c`, `b % c` | Bytes, trapping on overflow and `/ 0` |
| `b + 1`, `b * n` | an Int — a Byte meets an Int as an Int |
| `b < c`, `b == 33` | by value, Byte or Int on either side |
| `b.Int()`, `b.Double()` | the value |
| `b.String()` | source form: `"Byte(104)"`; `.debugDescription` in hex |
| `b.bitAnd(x)`, `b.bitOr(x)`, `b.bitXor(x)`, `b.bitNot()`, `b.shifted(by: n)` | a Byte, masked to 8 bits; `x` a Byte or an Int |
| `Data([b, ...])` | Bytes and Ints mix freely in the literal |

```swift
let d = "hé!".Data(.utf8)
d[0]                      // Byte(104)
d[0] == 104               // true
d[0] + 1                  // 105 — an Int
Byte(200) + Byte(100)     // overflow: traps
d.filter { $0 > 127 }     // .Data("w6k=") — a Data of Bytes
```
