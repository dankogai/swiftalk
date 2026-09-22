# Function

The one function type (§2.4): every `{ ... }` is a Function, every
type constructor and protocol is a Function, builtins like `print`
are Functions. There is no `func`; signatures are not part of the
type (a deliberate divergence from Swift) — arity and labels are
checked at call time.

| Form | Meaning |
|---|---|
| `{ x, y in body }` | declared parameters: strict arity, labels = names, reorderable |
| `{ body }` | no parameters: variadic; `$` is the argument Array, `$0` ≡ `$[0]` |
| `{ _, x in }` | `_` is positional-only: no label, no binding, `$0` only (round 61) |
| `f(x: 1, y: 2)`, `f(y: 2, x: 1)`, `f(1, 2)` | all the same call; an undefined label is an error |
| `f(a) { ... }` | trailing closure — the pinned last argument |
| `f((1, 2))` | a sole tuple argument IS the argument list (round 73): `$` = its elements, parameters bind to them, arity checked against them; wrap as `f(((1, 2),))` to pass a tuple whole. Builtins exempt |
| `$(args)` | recursion — calls the innermost enclosing function |
| `let f: Function = .todo` | deferred init: exactly one later assignment (named/mutual recursion) |
| `f.Type` | `Function` |
| `f.name` | a type's or protocol's name; `nil` for a plain closure; `"(+)"` for an operator |
| `reduce(0, +)`, `sorted(by: <)`, `map(-)`, `f(**, 2, 3)` | **the bare form** (round 145), Swift's: an operator token that is the whole argument — before `,` or `)` — is the operator as a Function. One corner: `/` before `,` reads as a regex literal (`split(/,/)` is a regex of a comma), so write `(/)` there |
| `(+)`, `(**)`, `(==)`, `(??)`, `(\|)`… | **an operator is a Function** (round 144): `(+)(2, 4)` is 6, `xs.reduce(0, (+))`, `xs.sorted((<))`; every binary operator, applying exactly as its infix form does (so `(+)(1, 2.0)` is the same type error); `(-)`, `(+)`, `(!)` with one argument are the prefix forms — `xs.map((-))`. One Function per operator, so `(+) == (+)`; no labels; `(&&)` and `(??)` cannot short-circuit, both arguments having arrived. `.String()` is `"(+)"`, which re-enters |
| `f == g` | identity |
| `T.conforms(to: P)` | for a type constructor: protocol conformance (`Array.conforms(to: Sequence)`) |
| `f.Sequence()` | wraps a yielding function into a Sequence — see [Sequence.md](Sequence.md) |
| `f.Task()` | spawns it — see [Task.md](Task.md) |
| `f.String()` | a placeholder: `"{ x, y in ... }"` (source text is OPEN) |

```swift
let fac = { n in n < 2 ? 1 : n * $(n - 1) }
fac(20)                         // 2432902008176640000
let sum = { $.reduce(0) { $0 + $1 } }
sum(1, 2, 3)                    // 6
42.Type                         // Int — a Function
```

Any function may `yield` (round 52) and may `await` (round 53):
functions are colorless. Multi-dispatch exists only for a type's
`init`s (§6).
