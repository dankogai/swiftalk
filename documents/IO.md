# IO

The module of the output functions (round 185; top-level builtins from
round 1 until then; a library, `modules/IO` built as `libIO.dylib`,
since round 189). `import from "IO"` binds `print` and `debugPrint`,
`import IO from "IO"` binds the namespace, `IO.print(x)`. **The CLI preimports
it** as its prelude, so in a script or the REPL `print` is simply there,
a builtin for the redeclaration rule (`let print = 1` is refused); an
embedder gets the same from `Interpreter.preimport()`, or stays silent.
Where the text goes is the host's: `Interpreter.output`, stdout by
default.

| Form | Meaning |
|---|---|
| `print(x, ...)` | writes each value's display text, space-separated, newline-terminated; `nil`. A String is bare, everything else is its `.String()` — a type's own `String` member speaks here (round 152). `print()` writes an empty line |
| `debugPrint(x, ...)` | the same with each value's `debugDescription`: quoted Strings, signed hex numbers (`.String(.sign, .hex)`, round 125), the memberwise form of a struct — a type's `String` member is not asked |
| `IO.print`, `IO.debugPrint` | the same Functions off the namespace; `extension IO { static let ... }` adds to it (round 184) |

```swift
print(1, "two", [3])          // 1 two [3]
debugPrint(1, "two", [3])     // +0x1 "two" [+0x3]
let r = print("x")            // r is nil
```

Thirty lines of Swift: `Swiftalk.output` reaches the running
Interpreter's sink, `Swiftalk.display` is a value's display text
([module.md](module.md)).
