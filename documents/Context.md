# Context

**Core** — built into the interpreter, there in every embedding.

An execution state (round 237): a top level of its own — the bindings
a program has made, each with its value, lock and mutability — where
`eval` runs. `global` is the program's own top level; `Context()` is a
copy of the top level it is made in; `eval(source, ctx)` runs `source`
at `ctx`'s top level, so what it declares lands there and what it
assigns changes that state and no other. Without a context, `eval`
runs in a fresh copy, gone when it returns.

```swift
var v = 0.0
eval("v = 1.0")              // Result.success(1.0) — in a copy of the top level
v                            // 0.0 — the copy is gone
eval("v += 1.0", global)     // Result.success(1.0) — the top level itself
v                            // 1.0
var ctx = Context()          // a copy, kept
eval("v = 42.0", ctx)        // Result.success(42.0)
v                            // 1.0
eval("v += 0.195", ctx)!     // 42.195
eval("let kept = 2", global)
kept                         // 2
```

| Form | Meaning |
|---|---|
| `Context()` | a **copy of the top level it is made in** — the program's, or, inside a module's function, the module's — the bindings as they are at that moment, value, lock and mutability. No arguments (`Context(x)` is a type error), and made where it is called: `Context` passed as a Function, `xs.map(Context)`, refuses |
| `global` | the program's top level itself, a `let` in the builtins scope — every file sees it, so a module's `eval(s, global)` runs in the program |
| `eval(source, ctx)` | runs at `ctx`'s top level: a declaration lands there, an assignment changes it, a redeclaration is the error it would be at the top; a `Result`, as ever ([toplevel.md](toplevel.md)). The second argument must be a Context |
| `eval(source)` | `eval(source, Context())` — a disposable copy of the file's top level: it sees every name and keeps nothing |
| `ctx.Type == Context`, `ctx == ctx`, `[ctx: v]` | a type like any (`Context.Type == Function`); equality and hashing by identity — `Context() == Context()` is false, `global == global` true |
| `global.String()`, `ctx.String()` | `global`, `Context()` — the source form; `print(ctx)` the same |
| `let c: Context = Context()` | an annotation like any; `global` is one (`let g: Context = global`) |
| *an `eval` of its own* | each context's `eval` defaults to a copy of that context, so `eval("eval(\"x\")", ctx)` sees `ctx`'s `x` and keeps nothing |
| *a copy, not a window* | a declaration made after the copy is not in it; a container in it is its own (`eval("a.append(2)", ctx)` leaves the top level's `a` alone); a lock holds in it as at the top (`eval("v = \"s\"", ctx)` is the same type error) |
| *a Function keeps its scope* | a closure made at the top level reads and writes the top level it was made in, whichever context calls it: `var v = 0; let bump = { v += 1 }; eval("bump()")` leaves `v` at 1. Lexical scope is the law (round 123), so a Context is not a sandbox |
| *types and imports* | a `struct`, `enum` or `import` evaluated in a context is that context's: `eval("struct P { }", ctx)` then `P` at the top is undefined |

A module's `eval` (round 123) runs in a copy of the module's top
level — its unexported names visible, nothing kept. A module that
wants state across calls keeps a Context of its own, made as it
loads: `let scope = Context()` at its top level, then `eval(s, scope)`
from its functions; `global` reaches the program's top level from
anywhere, which is explicit and so allowed. The builtins and the
prelude are under every context — `print` and `fetch` are there —
and a context has no members of its own beyond the universal ones.
