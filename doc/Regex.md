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

Not (yet): a `=~` operator, replacement templates (`$1`), match
positions/ranges, `Data` matching. Regex is not a Sequence conformer.
