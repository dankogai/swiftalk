# Tuple

A grab bag of values (round 70): `(v0, v1, ...)`. One type — `Tuple`
— for every arity and every mix; **not** Swift's `(T0, T1, ...)`
typing, deliberately. Elements are read by position. A tuple is a
value: equality is element-wise, it can be a Dictionary key, and its
source form round-trips.

| Form | Meaning |
|---|---|
| `(a, b, ...)` | a tuple literal; `(x,)` is a 1-tuple, `()` the empty tuple, `(x)` just groups |
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
| `let (a, b) = t`, `var (a, b) = t` | destructuring (round 71): by position, arity checked, `_` discards, nests; each name takes its own lock |
| `(a, b) = (b, a)` | destructuring assignment — the right side evaluates whole first, so swaps work; targets may be paths |
| `for (k, v) in d`, `for k, v in d` | destructuring loop variables — parentheses optional (round 72) |
| `if let (a, b) = t` | destructures a non-nil tuple; nil takes the else; a shape mismatch is an error |
| `f((1, 2))` | **a tuple is a rigid Array of arguments** (round 73): a sole tuple argument IS the argument list — `$` holds its elements, `$0`/`$1` are k/v in `d.map { }`, declared parameters bind to them; to pass a tuple whole, wrap it: `f(((1, 2),))`. Builtins take Values raw |

Dictionaries hand out `(key, value)` tuples: in `for`-`in`, `map`,
`filter`, and `reduce`.

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

OPEN: labeled tuples `(x: 1, y: 2)`.
