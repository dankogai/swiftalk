# Task

A spawned concurrent computation (§12, round 53): what `Task { ... }`
returns and `await` joins. swiftalk is **colorless** — no function is
marked `async`; any function may `await`. Tasks are cooperative green
threads: they interleave only at suspension points (`await`,
`sleep`), never preemptively, so programs stay deterministic.

| Form | Meaning |
|---|---|
| `Task { ... }`, `Task(f)`, `f.Task()` | spawn — **eager**: the body runs at once until it suspends or completes, then the spawner resumes |
| `async { ... }` | sugar for `Task { ... }` |
| `await t` | the task's value, memoized; a body error rethrows at every `await`; prefix at unary precedence (`await a + await b`) |
| `sleep(seconds)` | a builtin: suspends the current context; parked tasks run meanwhile |
| `t.Type` | `Task` |
| `t == u` | identity |
| `t.String()` | `"Task { ... }"` |

Top-level `await` is allowed (the REPL drives the loop). An `await`
that can never complete is detected and thrown as a deadlock error.
Tasks persist across a persistent interpreter's evals and are
cancelled at teardown. The wrapped body declares no parameters.

```swift
let t1 = async { sleep(0.02); 1 }
let t2 = async { sleep(0.01); 2 }
[await t1, await t2]          // [1, 2]
let f = { t in await t + 1 }  // colorless: an ordinary function awaits
f(Task { 41 })                // 42
```

OPEN: `await` inside a coroutine body, task groups, cancellation
as API, `.done`.
