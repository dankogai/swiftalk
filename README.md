# swiftalk

an attempt to design a scripting language inspired by Swift —
the way JavaScript was "inspired" by Java.

The language is being designed through dialogue; every decision is
recorded in [Design.md](Design.md).

## Status

**Milestone 0 — `eval()`** is underway: primitives, collection
literals (`[element]`, `[Key: Value]`), same-type arithmetic with
trapping overflow, `let`/`var` bindings with type locks, and the
round-trip law `eval(x.String()) == x`.

```swift
import Swiftalk

try eval("(0.1 + 0.2).String()")   // .string("0.30000000000000004")
try eval(#"[1, "one", 2.0]"#)      // heterogeneous — [Primitives], not [Any]
try eval("0xff")                   // .int(255)
try eval("1 + 1.5")                // throws: type error — Int ≠ Double
try eval("9223372036854775807 + 1")// throws: overflow traps
try eval("var x = 1\nx = \"1\"")   // throws: x is type-locked to Int
try eval("var x: Int? = nil")      // flat optional: Int-or-nil, no box

let interp = Interpreter()          // persistent environment
try interp.eval("var count = 1")
try interp.eval("count = count + 1")// .int(2)
```

```sh
swift test
```
