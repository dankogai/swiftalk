# Regex

A regular expression — a **core type with a literal of its own**
(round 86, §11): `/pattern/flags`, with `Regex("pattern")` and
`Regex("pattern", "i")` as the constructor. It wraps Swift's stdlib
`Regex`, so the syntax is Swift's (PCRE-flavored): `\d \w \s`,
classes, quantifiers, `(?<name>...)` named groups, lookarounds.

| Form | Meaning |
|---|---|
| `/\d+/`, `/a\/b/` | the literal; `\/` is a `/` in the pattern, every other backslash reaches the engine as written |
| `/abc/i`, `/x/ims` | flags: `i` ignore case · `m` `^`/`$` at line ends · `s` `.` matches newline · `x` extended (whitespace ignored) |
| `Regex(s)`, `Regex(s, "i")`, `s.Regex("i")` | the constructor (the round-47 law); a bad pattern or flag is an error |
| `r.pattern`, `r.flags` | the pieces; flags come back sorted |
| `r.String()` | `/pattern/flags` — re-enters (§3d) |
| `r == q` | by pattern and flags; usable as a Dictionary key |
| `Regex("")` | the empty regex — `//` is a comment, so the literal cannot spell it |

**Where `/` is a regex**: JavaScript's rule — a `/` starts a regex
where an operand cannot end: at a statement's start, after `( [ { ,
: = ?`, after an operator, after a keyword (`return /re/`, `case
/re/:`, `where /re/`). After a value, a name, or a closing bracket it
is division: `x / 2`, `(x) / 2`, `a[0] / 2`.

## On Strings

| Member | Result |
|---|---|
| `s.contains(/re/)` | Bool (round 83's `contains`, one more argument type) |
| `s.firstMatch(/re/)`, `s.wholeMatch(/re/)` | the match, or `nil`; Swift's `of:` accepted |
| `s.matches(/re/)` | an Array of the matches |
| `s.replacing(/re/, "x")` | every match replaced; `with:` accepted; `s.replacing("a", "b")` for a plain String |
| `s.replacing(/re/) { ... }` | the Function gets each match and returns its replacement |
| `s.split(/re/)`, `s.split(", ")` | the pieces, empty ones omitted (Swift's default); `separator:` accepted |

**A match** is the matched String when the regex has no capture
groups, and a **tuple** when it has: `.0` the whole match, then the
groups in order, labeled by name where the group has one, `nil` where
a group did not participate — Swift's own output shape, in swiftalk's
labeled tuples (rounds 74/75).

```swiftalk
"hello 42".firstMatch(/\d+/)                                   // "42"
"2026-09-03".firstMatch(/(\d+)-(\d+)-(\d+)/)                   // ("2026-09-03", "2026", "09", "03")
"2026-09-03".firstMatch(/(?<year>\d+)-(?<month>\d+)/).year     // "2026"
if let (_, y, m, d) = s.firstMatch(/(\d+)-(\d+)-(\d+)/) { }     // arity rigid: the whole match is .0
if (_, year: y, month: m) = s.firstMatch(/(?<year>\d+)-(?<month>\d+)/) { }
"ab".firstMatch(/a(x)?b/)                                       // ("ab", nil)
for m in "x=1, y=22".matches(/(\w)=(\d+)/) { print(m.1, m.2) }
"a1b22c".replacing(/\d+/) { m in "<" + m + ">" }               // "a<1>b<22>c"
"a1b22c".replacing(/(\d)(\d)?/) { _, first, _ in first + "!" } // the tuple splats (round 73): name the parts, or use $1
```

## In `switch`

```swiftalk
switch s {
case /\d+/:                          "number"        // the WHOLE String must match (Swift's ~=)
case /[a-z]+/i:                      "word"
case let (_, u, v) = /(\w+)@(\w+)/:  "mail \(u) at \(v)"   // round 78's binding, with a Regex source
case m = /a(b)?/ where m.1 != nil:   "with b"
default:                             "other"
}
```

A Regex pattern against a non-String subject is simply no match; a
Regex *binding* needs a String subject (a type error otherwise).

## A character is a grapheme

The engine matches **extended grapheme clusters** — the same unit
`s.count` and `s.Array()` use (§11) — never Unicode scalars (round
87). Consequences, each pinned by a test:

* `.` and `\X` both match one grapheme: `"e\u{301}🇯🇵a".matches(/./)`
  is `["é", "🇯🇵", "a"]` — five scalars, three matches. (`.` honors the
  `s` flag for newlines; `\X` always takes one cluster.)
* Comparison is canonical: `/^é$/` matches the decomposed `e\u{301}`,
  and `/[\u{E9}]/` does too; `/[a-z]/` does not, because that grapheme
  is not equal to any single letter.
* **A scalar range matches a grapheme only when the grapheme *is* a
  single scalar in the range** (or is canonically equal to one).
  `[\u{3040}-\u{309F}]+` matches `ひらがな`, but `か\u{309A}` (ka plus
  combining handakuten, one grapheme) slips through it, and a flag
  never matches `[\u{1F1E6}-\u{1F1FF}]` — a pattern cannot match half
  a cluster. **Use the script and property classes for text with
  combining marks**: `\p{Hiragana}`, `\p{Han}`, `\p{Latin}`,
  `\p{RegionalIndicator}` match whole graphemes. A literal sequence
  matches its grapheme (`/か\u{309A}/`), so does a class written with
  it (`[か\u{309A}]`).
* There is no scalar mode: the stdlib rejects the inline `(?u)`
  (scalar semantics) and `(?X)` (explicit grapheme semantics) with
  "not currently supported", and swiftalk does not expose the
  API-level switch. If scalar matching is ever wanted, the route is a
  `u` flag mapped to `matchingSemantics(.unicodeScalar)` — OPEN.
  Bytes are `Data`'s business, not a Regex's.

Not (yet): a `=~` operator, replacement templates (`$1`), match
positions/ranges, `Data` matching, a scalar-semantics flag. Regex is
not a Sequence conformer.
