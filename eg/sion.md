# MySION — a SION parser written in swiftalk

Round 85 asked a question before committing to anything heavy: *how
far can swiftalk go without RegExp?* The test case is a parser for
[SION](https://github.com/dankogai/swift-sion) — JSON in Swift's
literal syntax — written entirely in swiftalk, as
[sion.swt](sion.swt). SION is to become a built-in type, so the
example lives under its own name, `MySION`.

The answer: **all the way.** The parser handles every SION form —
`nil`, Bool, Int with `0x`/`0o`/`0b` and `_`, Double with exponents
and hex floats, Strings with Swift's escapes including `\u{...}`,
`.Date(epoch)`, `.Data("base64")`, Arrays, Dictionaries with *any*
key, `[:]`, trailing commas, `//` and `/* */` comments — and the
round-trip law `eval(x.String(.quoted)) == x` (§3d) holds through it
for every value type. RegExp was never missed, and neither were
String subscripts.

```sh
swift run swiftalk eg/sion.swt
```

```text
-42 42.195 true nil true
漢字、カタカナ、ひらがなの入ったstring😇
[nil, true, 1, 1.0, "one", [1], ["one": 1.0]]
["array": [], "bool": false, "dictionary": [:], "double": 0.0, "int": 0, "nil": nil, "string": ""]
.Date(0.0) Date
42 Data
Unlike JSON and Property Lists, / Yes, SION / does accept / non-String keys. / like / Map of ECMAScript.
[255, 15, 5, 1000, -7, 1000.0, 0.25, 6.02e+23]
tab	new
line 😀 "quoted"
[1, 2, 3]
true nil
true true
true -42
true 42.195
true 1e+100
true "漢字😇\n"
true [1, [2, [3]]]
true ["k": [nil, 1.5]]
true ["😇": true, 1.0: [], nil: [:]]
true .Date(1234567890.5)
true Data([99, 97, 102, 195, 169])
expected ',' or ']' at 5
expected ',' or ']' at 3
unterminated string at 5
expected ',' or ']' at 5
bad base64 at 6
unexpected 'x' at 4
unexpected 't' at 0
```

## How it is built

```swift
struct MySION {
    var chars: [String] = []                      // graphemes
    init { text in .chars = text.Array() }
    let at = { i in i < .chars.count ? .chars[i] : "" }
    ...
    let value = { i in                            // → Result.success((value:, next:))
        let c = .at(i)
        if c == "[" { return .container(i) }
        if c == "\"" { return .string(i) }
        ...
    }
}
MySION(text).parse()        // Result.success(value) or Result.failure("what at where")
```

* **Graphemes, not indices.** `text.Array()` is the one String
  primitive used; `.at(i)` reads a grapheme or `""` at the end. That
  is exactly the random-access story rounds 83/84 completed
  (`Array()` out, `joined()` back), and it is why no String
  subscript was needed.
* **Pure recursive descent.** Every step takes a position and
  returns a labeled tuple `(value:, next:)` (rounds 70–75). No
  method mutates `self`, so `MySION(text).parse()` works on a
  temporary — value semantics never get in the way.
* **Failures are Results.** Each step returns `Result.success(tuple)`
  or `Result.failure("expected ',' or ']' at 5")`, and the callers
  write `let r = .value(j)?` — postfix `?` propagates the failure
  out of the enclosing method (§8). The top level hands back one
  Result; `!` or `??` or `.failure` reads it.
* **Numbers by shape, conversion by the builtins.** The scanner only
  decides where a number ends and whether it is a Double; `Int(text)`
  and `Double(text)` do the rest, since they accept everything the
  lexer does — prefixes, `_`, exponents, hex floats (round 59).
* **`\u{1F600}` without a scalar constructor.** There was none, so the
  code point is turned into UTF-8 bytes by arithmetic and decoded
  with `Data(bytes).String(.utf8)`. *(Round 114 added
  `String.fromCodePoint`; the example keeps the hand-rolled encoder
  as round 105's bitwise demonstration.)* Base64 is the same trick in the
  other direction: `n / 65536`, `n - n / 256 * 256`.
* **A dictionary with any key** just works: `dict[key] = r.value`
  with `nil`, `1.0`, `[]`, `[:]` as keys, `nil` as a stored value,
  `.has` telling the two apart.

## What carried it

`struct` with `let` methods and implicit self (`.at(i)`, round 49),
labeled tuples and field access, `Result` with `?`, `if` as an
expression (round 80), `for (a, b) in [...]` over tuples, `contains`
(round 83), `joined` (round 84), `enumerated()`, flat optionals (`if
v == nil` then use `v` — nothing to unwrap), `Data(bytes).String(.utf8)`,
`Int("0x..")`/`Double("..p..")`, and value-semantics structs whose
methods are pure.

## What got in the way

Each of these is a finding, with the workaround the example uses.

1. **A strict `let` refuses `nil`** — `let v = Int(text)` fails with
   "cannot infer a type for 'v' from nil" when the conversion fails,
   *before* the code can test it. Workaround: `let v: Any = ...`.
   Same for `let (value: v, next: j) = r?` when the parsed value is
   `nil` (a legitimate SION value): the tuple was read by field
   instead, `r.value` / `r.next`. *(Landed in round 101: `nil` infers
   an `Any` lock, so `let v = Int(text)` binds and a nil tuple element
   destructures — the example lost its `: Any` workarounds. The field
   reads stay for a different reason: the sample's keys are mixed,
   and round 59's homogeneous-or-annotate rule stands.)*
2. **No `%`.** `v - v / n * n` throughout the base64 and UTF-8
   arithmetic. *(Landed in round 93. Round 105 then gave bitwise
   operations as methods, and the example's base64 and UTF-8 code
   now reads `n.shifted(by: -16)`, `c.bitAnd(63)`, `0x80.bitOr(...)`.)* No bit operators either (already OPEN). `%` is cheap
   and Swift has it.
3. **Newlines end statements everywhere except inside `[ ]` and
   `( )`** — a long `||` chain had to be parenthesized to continue on
   the next line; a line that starts with `||` is a syntax error.
   *(Landed in round 95: a trailing binary operator continues the
   line, and the parser's long conditions lost their outer
   parentheses. Round 96 added the leading form, Swift's rule.)*
4. **No `"""` multi-line String literals.** The README sample was an
   Array of lines `.joined("\n")`. *(Landed in round 94; the example
   now spells the sample as a `"""` literal, verbatim.)*
5. **Implicit self shadows format tags.** A method named `utf8` made
   `.String(.utf8)` inside the struct resolve to `self.utf8`. Renamed
   to `fromCodePoint`. A rule ("a `.name` argument to a builtin is a
   tag") would remove the trap; for now it is a naming hazard.
6. **No Array Range subscript** (`a[1..<3]`) — the scanner
   accumulates `text = text + c` instead. Planned with the slicing
   family (`suffix`, `dropFirst`, `dropLast`, `split`).
7. **Errors carry no line number** — `swiftalk file.swt` says what
   went wrong, not where. Finding a syntax error in 300 lines meant
   bisecting. Worth adding to the lexer's error path.
8. **Data's source form was `Data([99, 97])`, not SION's
   `.Data("base64")`** — the parser accepts both. *(Settled in round
   97, when SION became built-in: the source form is SION's, and
   `Data(s)` decodes base64.)*
9. Minor: no `uppercased()`/`lowercased()`; `.count` on a Sequence
   is deliberately an error, so lengths come from `.Array().count`.
10. **No recursion guard.** The tree-walker's recursion budget is its
    thread's stack (round 45), and nothing checks it: this parser
    runs fine from the CLI's 8 MB main thread, but the test suite's
    first run of it died with SIGBUS on a default test thread. The
    test now runs it on a 64 MB pthread, as coroutines already do
    for their bodies. A depth counter that throws "recursion too
    deep" would turn a crash into an error; an embedder running
    swiftalk on a pool thread will hit this before anyone else.

## Verdict

A parser is the kind of program regular expressions are *bad* at,
so this is the honest half of the answer: the language's core —
graphemes as Arrays, tuples, Results, structs — is enough for
structured text with nothing added. Where RegExp earns its footprint
is ad-hoc text: "does this line look like a date", "split on runs of
whitespace", "replace every `\s+` with one space". That is the case
for making it a module rather than a core type — which puts
`import` on the table first (OPEN, round 85).
