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
| `s.Data()` | UTF-8 bytes, infallible |
| `for c in s` | graphemes |
| `s.map { }` | an **Array** of results |
| `s.filter { }` | a **String** (Swift-compatible) |
| `s.reduce(init) { }` | fold over graphemes |
| `s.Array()` | `["h", "é", ...]` |
| `s.prefix(n)`, `s.suffix(n)` | the first / last n graphemes, **as a String** (round 89, revising 41's Array) |
| `s.dropFirst(n)`, `s.dropLast(n)` | all but the first / last n graphemes, a String; `n` defaults to 1 (round 89) |
| `s.split { }` | pieces between graphemes the predicate accepts, as Strings — beside `split(", ")` and `split(/re/)` (round 89) |
| `s.sorted()` | the graphemes, sorted, as an Array (round 83) |
| `s.contains("ell")`, `s.contains { }` | substring (as Swift's; `""` is found) / grapheme predicate (round 83) |
| `s.reversed()` | the graphemes, reversed, as an Array — `s.reversed().joined()` reverses a String (round 84) |
| `s.takeWhile { }`, `s.dropWhile { }` | a String, as `filter` gives: `"hello world".takeWhile { $0 != " " }` is `"hello"` (round 88) |
| `s.joined("-")` | the graphemes interleaved: `"abc".joined("-")` is `"a-b-c"` (round 84) |
| `s.contains(/re/)`, `s.firstMatch(/re/)`, `s.wholeMatch(/re/)`, `s.matches(/re/)` | Regex search (round 86) — see [Regex.md](Regex.md) for the match shape |
| `s.replacing(/re/, "x")`, `s.replacing(/re/) { }`, `s.replacing("a", "b")` | replace every match / substring (round 86) |
| `s.split(/re/)`, `s.split(", ")` | the pieces, empty ones omitted (round 86) |
| `s[i]` | undecided (§11) — an error for now |

```swiftalk
"héllo".count                       // 5
"héllo".filter { $0 != "l" }        // "héo"
"héllo".reduce("") { $1 + $0 }      // "olléh"
"x = \(40 + 2)"                     // "x = 42"
"foo".String(.quoted)               // "\"foo\""
```
