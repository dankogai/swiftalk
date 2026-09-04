# Data

Bytes — `[UInt8]`, distinct from String: bytes are bytes, text is
text (§3b). Source form is `Data([255, 1])` and round-trips.

| Member / constructor | Result |
|---|---|
| `Data()` | empty |
| `Data(d)` | `d` |
| `Data(s)`, `s.Data()` | the String's UTF-8 bytes — infallible |
| `Data([b, ...])` | from an Int Array; any non-byte value → `nil` |
| `d.count` | byte count |
| `d[i]` | the byte as an Int |
| `d[1..<3]`, `d[1...]` | a Data of those bytes (round 92) — Swift's bounds rule, as Array's |
| `d[i] = 255` | a byte write: an Int in 0...255, else a type error (round 92) |
| `d[0..<1] = Data([...])`, `d[d.count...] = xs.Data()` | assignment through a Range: `replaceSubrange`, the right side a Data (round 92) |
| `d.String(.utf8)` | decoded text, or `nil` — bytes may not be text |
| `d.String()` | source form: `"Data([99, 97])"` |
| `d.debugDescription` | bytes in hex: `Data([0xff])` |
| `d == e` | byte equality; usable as a Dictionary key |

```swiftalk
"café".Data()                          // Data([99, 97, 102, 195, 169])
Data([255, 254]).String(.utf8) == nil  // true
Data([104, 105]).String(.utf8)         // "hi"
```

OPEN: Data as a Sequence, base64 format.
