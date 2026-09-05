# String

Unicode text, Swift-sense: `.count` counts graphemes, iteration
yields graphemes (as one-Character Strings), and there is no UTF-16
view (§11). `"..."` literals with `\(interpolation)`, escapes `\" \\
\n \r \t \0 \u{...}`.

| Member / constructor | Result |
|---|---|
| `String()` | `""` |
| `String(x)` | `x`'s description: a String is itself, anything else its source form |
| `s + t` | concatenation |
| `s < t` etc., `==` | Comparable, Equatable |
| `s.count` | grapheme count |
| `s.String()` | `s` itself (argless `.String()` is description) |
| `s.String(.quoted)` | source form, escaped: `"\"hi\""` — `eval` re-enters it |
| `s.Int()`, `s.Double()`, `s.Bool()` | failable parses (see those pages) |
| `s.Data(.utf8)` | UTF-8 bytes, infallible (round 97; the bare `s.Data()` decodes base64) |
| `s.unicodeScalars`, `s.utf32` | the Unicode scalar values, as `[Int]` (round 114) |
| `s.utf8` | the UTF-8 bytes, as `[Int]` (round 114). There is no `.utf16` (§11) |
| `String.fromCodePoint(0x1F600, ...)` | a String from scalar values — JS's name, Swift's `String(UnicodeScalar)`; a surrogate or an out-of-range Int is an error; uncalled, a Function value (round 114) |
| `s.SION()`, `SION(json: s)`, `SION(propertyList: s)` | parse the String as SION / JSON / an XML property list — see [SION.md](SION.md) |
| `v.String(.json)`, `v.String(.propertyList)`, `v.String(.sion)` | any SION value as JSON / an XML property list / SION text (round 97) |
| `v.String(.pretty)`, `v.String(.json, .pretty)` | the same SION / JSON text laid out one element per line, two spaces a level — Arrays and Dictionaries open up, everything else stays on its line; `.pretty` alone means `.sion` (round 117) |
| `for c in s` | graphemes |
| `s.map { }` | an **Array** of results |
| `s.filter { }` | a **String** (Swift-compatible) |
| `s.reduce(init) { }` | fold over graphemes |
| `s.Array()` | `["h", "é", ...]` |
| `s.prefix(n)`, `s.suffix(n)` | the first / last n graphemes, **as a String** (round 89, revising 41's Array) |
| `s.dropFirst(n)`, `s.dropLast(n)` | all but the first / last n graphemes, a String; `n` defaults to 1 (round 89) |
| `s.split { }` | pieces between graphemes the predicate accepts, as Strings — beside `split(", ")` and `split(/re/)` (round 89) |

Literals (round 94): `"..."` with escapes and `\(expr)`; `"""` multi-line
(content on the lines between the delimiters, the closing `"""`'s
indentation stripped, `"` unescaped, `\` at a line's end joining
lines); raw `#"..."#` / `#"""..."""#` (backslashes and `"` verbatim,
`\#(expr)` to interpolate, more `#`s to nest a `"#`). See
[grammar.md](grammar.md).
| `s.sorted()` | the graphemes, sorted, as an Array (round 83) |
| `s.contains("ell")`, `s.contains { }` | substring (as Swift's; `""` is found) / grapheme predicate (round 83) |
| `s.reversed()` | the graphemes, reversed, as an Array — `s.reversed().joined()` reverses a String (round 84) |
| `s.prefix { }`, `s.dropFirst { }` | a String, as `filter` gives: `"hello world".prefix { $0 != " " }` is `"hello"` (round 88) |
| `s.joined("-")` | the graphemes interleaved: `"abc".joined("-")` is `"a-b-c"` (round 84) |
| `s.contains(/re/)`, `s.firstMatch(/re/)`, `s.wholeMatch(/re/)`, `s.matches(/re/)` | Regex search (round 86) — see [Regex.md](Regex.md) for the match shape |
| `s.replacing(/re/, "x")`, `s.replacing(/re/) { }`, `s.replacing("a", "b")` | replace every match / substring (round 86) |
| `s.split(/re/)`, `s.split(", ")` | the pieces, empty ones omitted (round 86) |
| `s[i]` | undecided (§11) — an error for now |

```swift
"héllo".count                       // 5
"héllo".filter { $0 != "l" }        // "héo"
"héllo".reduce("") { $1 + $0 }      // "olléh"
"x = \(40 + 2)"                     // "x = 42"
"foo".String(.quoted)               // "\"foo\""
```
