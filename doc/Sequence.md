# Sequence

Lazy by default (round 41) — unlike Swift's opt-in `.lazy`. Two ways
to make one, and `map`/`filter` on either **defer** until something
pulls. `Sequence` is also the protocol that Array, String,
Dictionary, and Range conform to (§10).

| Constructor | Meaning |
|---|---|
| `Sequence(state) { next }` | a generator: `state`'s elements arrive as arguments (`$0`, `$1`, …); the return value is the element; `nil` ends it; the closure's final `$` is the next state |
| `Sequence(f)`, `f.Sequence()`, `Sequence { ... }` | a coroutine (round 52): each pull resumes `f`, each `yield v` emits `v`, returning ends it |

| Member | Result |
|---|---|
| `s.map { }`, `s.filter { }` | **lazy** — another Sequence |
| `s.prefix(n)` | the first n, materialized as an Array |
| `s.enumerated()` | `(offset:, element:)` tuples — lazy on a Sequence, an Array of tuples on Array/String/Range/Dictionary/Tuple (rounds 73/74); `e.offset`/`e.element`, `for i, x in xs.enumerated()`, `.map { i, x in }` |
| `s.Array()` | everything (do not ask an infinite one) |
| `s.reduce(init) { }` | fold (consumes the whole sequence) |
| `for x in s` | pull one at a time; `break` stops a coroutine cleanly |
| `for x in s where c` | `for x in s.filter({ })` with the loop's names, decided per pulled element — lazy on a lazy Sequence (round 82) |
| `s.count` | error — a Sequence may be infinite; `.prefix` or `.Array()` it deliberately |
| `s.Type` | `Sequence` |

A Sequence is a re-iterable value: every iteration restarts from the
initial state / a fresh run of the coroutine body. `yield` is
dynamic: a helper function called from the body may yield on its
behalf. `yield` outside a wrapped function is an error.

```swiftalk
let fib = Sequence([0, 1]) { $ = [$1, $0 + $1]; return $0 }
fib.prefix(8)                                  // [0, 1, 1, 2, 3, 5, 8, 13]
let naturals = Sequence { var n = 0; while true { yield n; n = n + 1 } }
naturals.filter { $0 / 2 * 2 == $0 }.prefix(3)  // [0, 2, 4]
```

See [eg/sequence.swt](../eg/sequence.swt) for infinite primes.
