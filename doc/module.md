# Modules — `import` and `export`

Round 100. A module is a `.swt` file. It is evaluated **once per
program** (per Interpreter), in strict mode, in a scope of its own
whose parent is the builtins — it sees `Int` and `print`, never the
importer's variables — and **only what it exports is importable**.
The shape is JavaScript's more than Swift's, because what loads is a
file: `from` is required, and the "where" is a path or a URL.

| Form | Meaning |
|---|---|
| `import M from "./mod.swt"` | every export under `M` — a **labeled tuple** of the exports in export order, so `M.x` reads and `M.f(args)` calls through; `M` is a `let` |
| `import (foo, bar) from "./mod.swt"` | the named exports, bound directly (as `let`s); a name the module does not export is an error that lists what it does. Parentheses, not braces |
| `"./mod.swt"`, `"../lib/x.swt"`, `"/abs/x.swt"` | resolved **beside the importing file** (the CLI script, or the module doing the importing); the REPL resolves from the cwd |
| `"https://host/path/mod.swt"` | the CLI fetches with `curl -fsSL`; an embedder supplies `Interpreter.moduleLoader` (the core refuses URLs without one) |
| `export let x = ...`, `export var`, `export struct`, `export enum`, `export let (a, b) = t` | a declaration, exported |
| `export (a, b)` | existing names, exported |

Exports are **values, copied at import** — a module's `var` reaches the
importer as a snapshot in a `let`. Module-private state lives in the
closures that export it: a non-exported `var` mutated by an exported
Function persists across calls, and every importer shares the one
instance.

```swiftalk
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
Geometry                                   // (Point: Point, area: { w, h in ... }, count: { ... })
```

`import` and `export` belong at a file's top level; a circular import
is an error; an error inside a module is reported with the module's
path. `export` in the main program is allowed and inert.

Not (yet): live bindings; re-export (`export (x) from`); an import
in a type annotation (`let p: M.Point` — import `Point` by name);
`import` of anything but `.swt` source.
