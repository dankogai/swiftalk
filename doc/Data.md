# Data

Bytes — `[UInt8]`, distinct from String: bytes are bytes, text is
text (§3b). **The literal is SION's** since round 97: the source form
is `.Data("base64")`, and `Data(s)` decodes base64.

| Member / constructor | Result |
|---|---|
| `Data()` | empty |
| `Data(d)` | `d` |
| `Data(base64)`, `base64.Data()`, `.Data("...")` | the bytes, or `nil` if the String is not base64 (whitespace ignored, padding required) |
| `s.Data(.utf8)` | the String's UTF-8 bytes — infallible (round 97; was the bare form) |
| `Data([b, ...])` | from an Int Array; any non-byte value → `nil` |
| `d.count` | byte count |
| `d[i]` | the byte as an Int |
| `d[1..<3]`, `d[1...]` | a Data of those bytes (round 92) — Swift's bounds rule, as Array's |
| `d[i] = 255` | a byte write: an Int in 0...255, else a type error (round 92) |
| `d[0..<1] = Data("...")`, `d[d.count...] = xs.Data(.utf8)` | assignment through a Range: `replaceSubrange`, the right side a Data (round 92) |
| `d.String(.utf8)` | decoded text, or `nil` — bytes may not be text |
| `d.String()` | source form: `.Data("Y2Fmw6k=")` — re-enters |
| `d.debugDescription` | the bytes in hex: `Data([0x63, 0x61])` — re-enters too |
| `d.String(.json)` | a base64 String (JSON has no bytes) |
| `v.Data(.propertyList)` | any SION value as a binary property list — see [SION.md](SION.md) |
| `d == e` | byte equality; usable as a Dictionary key |
| `for b in d`, `d.map`, `d.filter`, `d.reduce`, `d.contains`, `d.sorted`, … | **a Sequence of its bytes, as Ints** (round 115): every Sequence member; `filter`, `prefix`, `suffix`, `dropFirst`, `dropLast`, `split` give Datas back, `map`/`sorted`/`reversed` Arrays — Swift's shapes |

```swift
"café".Data(.utf8)                     // .Data("Y2Fmw6k=")
Data("Y2Fmw6k=").String(.utf8)         // "café"
Data("hello")                          // nil — not base64
Data([255, 254]).String(.utf8) == nil  // true
```

(Data became a Sequence in round 115; nothing is OPEN here.)
