# Modules — `import` and `export`

Round 100. A module is a `.swt` file. It is evaluated **once per
program** (per Interpreter), in strict mode, in a scope of its own
whose parent is the builtins — it sees `Int` and `print`, never the
importer's variables — and **only what it exports is importable**.
The shape is JavaScript's more than Swift's, because what loads is a
file: `from` is required, and the "where" is a path or a URL.

| Form | Meaning |
|---|---|
| `import from "./mod.swt"` | **every export, by its own name** (round 148) — the plain form: `import from "./modules/Complex.swt"` then `Complex(0.0, 1.0)`. A name already bound is the usual redeclaration error |
| `import M from "./mod.swt"` | every export under `M` — a **type whose statics are the exports** (round 184; a labeled tuple before), so `M.x` reads, `M.f(args)` calls through, `M.Point(x:)` constructs, `M` prints as `M`, `M.Type` is `Function`, and `M()` is an error: a module has no instances. `extension M { static let g = ... }` adds to it — for every importer, since the type object is one per module, named by its first importer and aliased by the next (`import N from` the same file: `N == M`). `M` is a `let`. Mind the trap: `import Complex from` makes `Complex` the *namespace*, so the struct is `Complex.Complex` — `import from` is what that sentence means |
| `import (foo, bar) from "./mod.swt"` | the named exports, bound directly (as `let`s); a name the module does not export is an error that lists what it does. Parentheses, not braces |
| `"./mod.swt"`, `"../lib/x.swt"`, `"/abs/x.swt"` | resolved **beside the importing file** (the CLI script, or the module doing the importing); the REPL resolves from the cwd |
| `"https://host/path/mod.swt"` | the CLI fetches with `curl -fsSL`; an embedder supplies `Interpreter.moduleLoader` (the core refuses URLs without one) |
| `"Env"` — a **bare name**: no `/`, no `.swt` | a **native module** (round 182): one an embedder registered by that name, else `libEnv.dylib` (`.so` on Linux) found on `Interpreter.modulePath` — the CLI's own directory and its `../lib`, or `SWIFTALK_MODULE_PATH`. Node's rule for `fs`, with a capital: module names are written like types, `Env` not `env` — a convention, not grammar (round 183). Neither found: an error naming the file it looked for |
| `"./libx.dylib"` | a module library by its path, resolved like a file |
| `export let x = ...`, `export var`, `export struct`, `export enum`, `export let (a, b) = t` | a declaration, exported |
| `export (a, b)` | existing names, exported |
| `extension Int { }` in a module | an extension of a **builtin** type is program-wide (round 147), as Swift's are: `modules/Complex.swt`'s `extension Double { var i }` gives the importer `Double.pi.i`. (A struct's extension always was, the type object being one.) |
| `eval(source)` in a module | the **module's own** `eval` (round 123; a `Result` since round 159): runs at the module's top level — its unexported names visible, its declarations landing there — whoever calls the function that calls it; the importer's names are not visible. See [README.md](README.md) |

Exports are **values, copied at import** — a module's `var` reaches the
importer as a snapshot in a `let`. Module-private state lives in the
closures that export it: a non-exported `var` mutated by an exported
Function persists across calls, and every importer shares the one
instance.

```swift
// geometry.swt
export struct Point { var x: Double; var y: Double }
var calls = 0                              // private
export let area = { w, h in calls = calls + 1; return w * h }
export let count = { calls }

// main.swt
import Geometry from "./geometry.swt"
Geometry.area(3.0, 4.0)                    // 12.0
Geometry.Point(x: 1.0, y: 2.0)
import (area, count) from "./geometry.swt" // the same instance
count()                                    // 1 — the call above counted
Geometry                                   // Geometry — a type, its statics the exports
extension Geometry { static let perimeter = { w, h in 2.0 * (w + h) } }
Geometry.perimeter(3.0, 4.0)               // 14.0 — round 184
```

`import` and `export` belong at a file's top level; a circular import
is an error; an error inside a module is reported with the module's
path. `export` in the main program is allowed and inert.

Not (yet): live bindings; re-export (`export (x) from`); an import
in a type annotation (`let p: M.Point` — import `Point` by name).

## Native modules (round 182)

A native module is Swift: a `Swiftalk.Module` with a name and exports,
each an ordinary `Value`. `function(name) { args in }` makes a
swiftalk Function of a Swift closure — the arguments come in order,
labels dropped; what it returns is the call's value; a thrown
`Swiftalk.Error` is the caller's error. `export(name, value)`
publishes a constant, or anything else. The import forms above all
apply: `import from "Env"`, `import Env from "Env"`, `import (get)
from "Env"`. Name a module with a capital, like a type (round 183) —
and it is one: `import Net from "Net"` then `extension Net { static
let resolve = { host in ... } }` adds `Net.resolve` in swiftalk on top
of what the Swift module exports (round 184).

```swift
import Swiftalk

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "Greet")
    m.function("hello") { args in
        guard case .string(let who)? = args.first else {
            throw Swiftalk.Error.type("hello(name) takes a String")
        }
        return .string("hello, \(who)")
    }
    m.export("answer", .int(42))
    return m
}

@_cdecl("swiftalk_module")                       // the one C symbol a library exports
public func swiftalkModule() -> UnsafeMutableRawPointer { build().entryPoint() }
```

Two ways in. An embedder calls `interpreter.register(build())` and
imports by the name. Or the file is a target of its own with a dynamic
library product named after the module — SwiftPM builds
`libGreet.dylib` — and the interpreter finds it on `modulePath` and
loads it with dlopen; the symbol above is the whole boundary, and
everything else crosses as Swift. That works because host and module
link the ONE `libSwiftalk`: the core is a dynamic library product of
its own package, `Core/`, and a module's target depends on
`.product(name: "Swiftalk", package: "Core")` exactly as the CLI does
(see [`modules/Env`](../modules/Env/EnvModule.swift) and the root
`Package.swift`). Build modules with the host's toolchain.

The example, `Env`: `get(name)` (nil when unset), `set(name, value)`,
`unset(name)`, `all()` (a `[String: String]`), and the constant
`platform` (`"darwin"` or `"linux"`).

### A module's own values, types, and extensions (round 186)

| API | Meaning |
|---|---|
| `Value.host(object)` | a value the module owns: `object` is a `Swiftalk.HostValue` — a class answering `typeName`, `type` (what `x.Type` gives), `member(name, args, called)` (nil: no such member, the core's universal ones then answer), `isEqual(to:)`, `hash(into:)`, `sourceString(debug:)` (what prints and re-enters), and `patternMatch(subject, binding:)` — Swift's `~=` for `case pattern:` and the source of `case let m = pattern`, nil being no match |
| `m.type("Name") { args in }` | exports a type: the closure constructs from the call's arguments; round 47's law holds (`s.Name(args)` is `Name(s, args)`), `let x: Name` is an annotation, `x.Type == Name` for what it makes. Returns the type Value — give it to the values you make |
| `m.extend("String", "member") { receiver, args, called in }` | a member added to a core type, program-wide once the module is loaded (round 147's rule); returning nil **declines**, and the core's own member, if any, answers — so a module adds an argument type to `contains` and leaves `contains("x")` alone |
| `Swiftalk.call(f, args)` | calls a swiftalk Function from Swift — for a member that takes a closure |
| `TypeAnnotation("Array", parameters: [TypeAnnotation("String")])` | a stamp for a container the module builds |

The Regex module ([Regex.md](Regex.md), `modules/Regex/RegexModule.swift`)
uses all five: the `Regex` type, the value behind `/re/`, six String
members, `replacing(/re/) { m in }`, and `split`'s `[String]`.

## The prelude (round 185)

The core ships two modules of its own, `IO` (`print`, `debugPrint` —
[IO.md](IO.md)) and `Net` (`fetch`, `Response` — [Net.md](Net.md)),
registered on every Interpreter and imported by nobody until asked.
The CLI **preimports** them: every export lands in the builtins scope
before the program runs, so a script, the REPL, and every module they
import have `print` and `fetch` as they always did, and `let print = 1`
is still "a builtin". An embedder calls `Interpreter.preimport()` (the
default is `["IO", "Net"]`; any registered or module-path name goes)
for the same, or imports what it wants, or leaves the interpreter
silent. The top level itself keeps one function, `eval`; `zip` and
`sleep` became `Sequence.zip` and `Task.sleep`. The CLI then preimports
**`Regex`** from the module path (round 186) — `libRegex.dylib` beside
the executable — and, when it is missing, says so once and runs on,
`/re/` literals failing when evaluated. `swiftalk --no-prelude` (round
187) skips all three: the top level has `eval` and nothing else, and
`import from "IO"` or `import (Regex) from "Regex"` brings what a
script wants.
