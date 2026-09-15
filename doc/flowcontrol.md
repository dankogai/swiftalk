# Flow control

Every construct the interpreter parses for choosing and repeating,
on one page (round 155). The conditions are Bools — nothing is
truthy (§3b) — with one reading that is not a Bool test: a *bare
variable* as a condition asks "not nil?" (round 80). `if` and
`switch` are expressions. Assignment is a statement, so an `=` inside
a condition or a `case` can only mean "bind". See
[grammar.md](grammar.md) for the productions and
[Bool.md](Bool.md) for the logical operators.

## `if` / `else if` / `else` — an expression

```swift
if x > 0 { "positive" } else if x < 0 { "negative" } else { "zero" }
let sign = if x > 0 { 1 } else { -1 }          // the taken branch's last value (round 80)
if x > 0 { print("no else: the value is nil when not taken") }
```

The value of an `if` is the last statement of the branch taken, `nil`
when no branch is. The braces are required; the parentheses are not.
Trailing closures are off inside the header — `if c { }` reads `{` as
the block — so parenthesize a trailing-closure call there.

### Conditions

A header is a comma-separated list; every item must hold, in order,
and a binding's name is visible to the items after it and the block.

| Condition | Meaning |
|---|---|
| `if a > b` | a Bool expression — anything else is a type error |
| `if a > b and c, d != nil` | several, comma-joined; `and`/`&&` inside one item, the comma between items |
| `if o { o + 1 }` | a **bare variable**: a Bool is tested, anything else asks "not nil?" — inside, `o` is itself, no shadow, writes reach it (round 80). Expressions do not get this: `if Int(s) { }` is an error |
| `if let v = Int(s) { v + 1 }` | bind when not nil; `nil` fails the condition, a misfit errors |
| `if v = Int(s)` | the same — `let` is optional since round 78, an `=` in a condition can only bind |
| `if var v = ...` | a mutable binding |
| `if let x { }` | shorthand: `if let x = x` |
| `if let (a, b) = pair` | destructuring (round 72); labels bind by label |
| `if let r = shape.circle` | an enum case's payload — the case accessor is nil for another case (round 78); Swift's `if case` is a syntax error that names this |
| `if let m = s.firstMatch(/re/)` | a Regex match or nil — see [Regex.md](Regex.md) |

## The ternary and the short-circuits

```swift
let label = x > 0 ? "positive" : "non-positive"     // the ? must be spaced; unspaced ? is postfix propagate
let v = maybe ?? fallback                            // nil-coalescing: the right side only when needed
ready && go()                                        // go() only when ready
ready and go()                                       // the same, in words (round 155)
```

`c ? a : b` is right-associative and looser than `||`; the words
`not`/`and`/`or`/`xor` are looser still — `c ? a : b or d` is
`(c ? a : b) or d`. `??` and `!!` are on [Nil.md](Nil.md).

## `switch` — an expression

```swift
let name = switch shape {
case .circle: "round"                                // the subject's case, any payload
case let (w, h) = .rect where w == h: "square"       // bind the payload; the guard sees the bindings (round 81)
case let (w, h) = .rect: "rectangle"
case 0, 1: "a bit"                                   // equality; alternatives comma-separated
case 2...9: "a digit"                                // a Range matches an Int by containment
case /^a/: "starts with a"                           // a Regex matches a String
case let m = /(\d+)/: m.1                            // bind the match
default: "something else"
}
```

The first matching case runs; its last statement is the value. No
match and no `default` is a runtime error. Patterns are `_`, `.case`,
`[let] pattern = .case | expression` (the comma list needs the
`let`, a bare comma separates alternatives — round 99), or any
expression compared for equality. `where` guards belong to the
pattern they follow and may use the word operators. There is no
fall-through and no `fallthrough`. See [enum.md](enum.md) for the
case accessors and [Result.md](Result.md) for `.success`/`.failure`.

## Loops

```swift
for x in [1, 2, 3] { print(x) }                   // any Sequence: Array, String (graphemes), Range, Dictionary, Set, a generator
for (k, v) in dict { }                            // destructure each element (round 71); parentheses optional: for k, v in dict
for (i, x) in xs.enumerated() { }                 // (key: i, value: x) — positional destructuring
for i in 1...6 where i % 2 == 0 or i == 5 { }     // where filters with the loop's names (round 82)
for _ in 0..<3 { }                                // Ranges are lazy; 0... is unbounded — break out
while i < 10 { i += 1 }
while let line = next() { }                       // a condition list as if's, fresh bindings each pass (round 76)
while node { node = node.next }                   // a bare variable: until nil (round 80)
repeat { i -= 1 } while i > 0                     // the body first
```

`break` leaves the innermost loop, `continue` starts its next pass. A
loop's value is `nil`. `for` over an infinite Sequence is fine as long
as something breaks.

### Labels

```swift
outer: for row in grid {                          // Swift's spelling: a name, a colon, the loop (round 156)
    for cell in row {
        if cell == 0 { continue outer }           // the next row
        if cell < 0 { break outer }               // out of both
    }
}
retry: while true { repeat { if done { break retry } } while false }
```

`label: for`, `label: while`, `label: repeat`; `break label` and
`continue label` name the loop to act on, bare `break`/`continue` the
innermost. The label must be an enclosing loop's — an unknown name, a
label from a loop already closed, or one reused by a nested loop is a
syntax error. A closure is not a loop: `break` inside `.forEach { }`
or any other closure is an error even under a labeled loop. Labels
live in their own namespace, so `outer` may also be a variable.

### `forEach`

```swift
xs.forEach { print($0) }                          // eager, returns nil (round 156)
dict.forEach { k, v in print(k, v) }
Sequence { yield 1; yield 2 }.forEach { print($0) }
```

`s.forEach { }` walks any Sequence for its side effects and returns
`nil`. It is not `_ = s.map { }`: `map` is lazy on a Sequence, so
that line would run nothing. Use `for` when the body needs `break`,
`continue`, or a label.

## Early exit

| Form | Effect |
|---|---|
| `return`, `return v` | leave the enclosing function with `nil` / `v`; at a file's top level, end the script |
| `x?` (unspaced, postfix) | **propagate**: the value when `x` is not nil and not a `.failure`; otherwise return that nil/failure from the enclosing function at once (§3a/§8) — one rule for absence and error |
| `x!` | the value, or trap (a runtime error stops the program) |
| `yield v` | in a coroutine (`Sequence { }`): emit `v` and pause until the next pull — see [Sequence.md](Sequence.md) |
| a runtime error | stops the program (or the REPL line); swiftalk has no `throw`/`try`/`catch` — errors are values, `Result.failure`, and `?` carries them |

```swift
let quarter = { n in Result.success(halve(halve(n)?)?) }     // a failure in either halve returns it from quarter
```

## What is not here

No `guard` (write `if not c { return }`), no `fallthrough`, no
`do`/`catch`, no `defer`, no labels on `if`/`switch` (loops only). `async`/`await` and
`Task` are on [Task.md](Task.md). Swift's `if case` and `guard let`
are syntax errors that name the swiftalk spelling.
