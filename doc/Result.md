# Result

A built-in enum (§8, round 51) — swiftalk's errors are values, not
exceptions: `Result.success(v)` / `Result.failure(e)`, payloads
untyped. All of [enum.md](enum.md)'s machinery applies: `switch`,
case accessors, equality, source form.

| Form | Result |
|---|---|
| `Result.success(v)`, `Result.failure(e)` | construction |
| `.success(v)`, `.failure(e)` | the same, **bare, anywhere** (round 160): in a closure's `return`, a ternary, an Array, `r == .success(2)` — no annotation needed, Result being the one enum every program knows. Inside a type body a member of the same name wins (`self.success(v)`); the payload is required |
| `Result(x)` | error — construct via a case |
| `r.success` | the payload, or `nil` if it is a failure (case accessor) |
| `r.failure` | the error, or `nil` |
| `r?` | postfix: unwraps success, **early-returns the failure** (or nil) from the enclosing function |
| `r!` | unwraps success; traps on failure |
| `r ?? d` | the success payload, or `d` on failure/nil (lazy right side) |
| `r.catch { err in ... }` | the success payload — the handler is not run — or, on a failure, **the handler's value**, called with the error (round 161): `eval(s).catch { err in print(err); nil }`. Result only; for nil, `??` is the form. The handler may itself return a Result |
| `switch r { case let v = .success: ... case let e = .failure: ... }` | exhaustive; `if let e = r.failure { }` for one side |
| `r.Type == Result`, `r == s` | as any enum |
| `eval(source)` | a Result (round 159): `.success(value)` or `.failure(message)` — see [toplevel.md](toplevel.md) |

```swift
let halve = { n in n / 2 * 2 == n ? Result.success(n / 2) : Result.failure("odd: \(n)") }
let quarter = { n in Result.success(halve(halve(n)?)?) }
quarter(8)          // Result.success(2)
quarter(6)          // Result.failure("odd: 3") — propagated through ?
quarter(6) ?? -1    // -1
quarter(6).catch { err in print(err); -1 }   // prints "odd: 3", -1 (round 161)
```

`?` treats `nil` the same way — one rule for absence and failure
(§3a). Postfix `?` is unspaced; the spaced `?` is the ternary.
