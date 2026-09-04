# Tuple

A grab bag of values (round 70): `(v0, v1, ...)`. One type — `Tuple`
— for every arity and every mix; **not** Swift's `(T0, T1, ...)`
typing, deliberately. Elements are read by position. A tuple is a
value: equality is element-wise, it can be a Dictionary key, and its
source form round-trips.

| Form | Meaning |
|---|---|
| `(a, b, ...)`, `(x: 1, y: 2)` | a tuple literal, elements optionally labeled (round 74); `(x,)` and `(x: 1)` are 1-tuples, `()` the empty tuple, `(x)` just groups |
| `t.x`, `t.x = v` | by label — labels name positions, so `.0`/`.1` still work; unknown label / duplicate label are errors |
| `t.0`, `t.1`, … | elements; out of range is an error; `t.0.1` nests |
| `t.0 = v` | rebuilds the tuple (a value) — needs a `var` root |
| `t.count` | arity |
| `t == u` | element-wise |
| `t.Type` | `Tuple`, whatever the contents |
| `t.String()` | `"(1, \"a\")"` — `(7,)` for a 1-tuple |
| `for x in t`, `t.map`, `t.filter`, `t.reduce`, `t.Array()` | a Tuple conforms to Sequence |
| `seq.enumerated()` | `(index, element)` tuples — see [Sequence.md](Sequence.md) |
| `Tuple()`, `Tuple(seq)`, `seq.Tuple()` | empty; gathered from any Sequence conformer |
| `case (1, "x"):` | a tuple literal is an expression pattern — matched by equality |
| `let (a, b) = t`, `var (a, b) = t`, `let a, b = t` | destructuring (round 71): by position, arity checked, `_` discards, nests; each name takes its own lock; the parentheses are optional (round 99) — labels need them |
| `let (x: a, y: b) = t` | labeled destructuring (round 75): a labeled element binds **by label** (order free), an unlabeled one by position; a missing label is an error — in `let`/`var`, `if let`, `for`, and assignment |
| `(a, b) = (b, a)` | destructuring assignment — the right side evaluates whole first, so swaps work; targets may be paths |
| `for (k, v) in d`, `for k, v in d` | destructuring loop variables — parentheses optional (round 72) |
| `if let (a, b) = t` | destructures a non-nil tuple; nil takes the else; a shape mismatch is an error. The parentheses stay here: in `if`/`while` a comma separates conditions (`if let a, b = t` is two of them) |
| `case let w, h = .rect:` | a `switch` binding without parentheses (round 99) — the `let` is what makes the comma a list, not alternatives |
| `f((1, 2))` | **a tuple is a rigid Array of arguments** (round 73): a sole tuple argument IS the argument list — `$` holds its elements, `$0`/`$1` are k/v in `d.map { }`, declared parameters bind to them; to pass a tuple whole, wrap it: `f(((1, 2),))`. Builtins take Values raw |

**Labels are cosmetic**: equality, hashing, destructuring, and the
argument splat all ignore them — `(x: 1, y: 2) == (1, 2)`. Source
form keeps them. Dictionaries hand out `(key:, value:)` tuples and
`enumerated()` gives `(offset:, element:)`, as Swift names them — so
`pair.key`, `pair.value`, `e.offset`, `e.element` read, while `.0`,
destructuring, and `{ k, v in }` all still work.

```swiftalk
let t = (1, "one", 2.0)
t.1                                   // "one"
((1, 2), (3, 4)).1.0                  // 3
for pair in ["a": 1] { print(pair.0, pair.1) }
```

```swiftalk
var (a, b) = (0, 1)
for _ in 1...10 { (a, b) = (b, a + b) }   // a == 55
```

```swiftalk
for (value: v, key: k) in years { ... }     // by label, any order
let (element: x, offset: i) = xs.enumerated()[0]
```
