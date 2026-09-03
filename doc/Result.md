# Result

A built-in enum (§8, round 51) — swiftalk's errors are values, not
exceptions: `Result.success(v)` / `Result.failure(e)`, payloads
untyped. All of [enum.md](enum.md)'s machinery applies: `switch`,
case accessors, equality, source form.

| Form | Result |
|---|---|
| `Result.success(v)`, `Result.failure(e)` | construction; `let r: Result = .success(7)` with an annotation |
| `Result(x)` | error — construct via a case |
| `r.success` | the payload, or `nil` if it is a failure (case accessor) |
| `r.failure` | the error, or `nil` |
| `r?` | postfix: unwraps success, **early-returns the failure** (or nil) from the enclosing function |
| `r!` | unwraps success; traps on failure |
| `r ?? d` | the success payload, or `d` on failure/nil (lazy right side) |
| `switch r { case let v = .success: ... case let e = .failure: ... }` | exhaustive; `if let e = r.failure { }` for one side |
| `r.Type == Result`, `r == s` | as any enum |

```swiftalk
let halve = { n in n / 2 * 2 == n ? Result.success(n / 2) : Result.failure("odd: \(n)") }
let quarter = { n in Result.success(halve(halve(n)?)?) }
quarter(8)          // Result.success(2)
quarter(6)          // Result.failure("odd: 3") — propagated through ?
quarter(6) ?? -1    // -1
```

`?` treats `nil` the same way — one rule for absence and failure
(§3a). Postfix `?` is unspaced; the spaced `?` is the ternary.
