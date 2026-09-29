# swiftalk in JavaScript

The core runtime — the interpreter of `Core/Sources/Swiftalk` — ported to
JavaScript (round 197 onward), so swiftalk runs wherever a modern JS
engine does: Node 22+, and the browser — the core, the prelude (IO,
Net, Regex, Sequence, Task, BigInt, BigRat) as JS modules, and a notebook page. What the Swift core does, this does, checked against the same
corpus: `tools/extract-fixtures.mjs` turns every `eval(source) == value`
expectation in `Tests/SwiftalkTests` into JSON, and the tests here run
the JS runtime over it.

```sh
cd js
npm test            # extracts the fixtures, then node --test
npm run repl        # a REPL over the runtime, with the prelude (pipe a program in, or type)
npm run build       # dist/swiftalk.js (one file) and dist/notebook.html (the notebook, runtime inlined)
```

**The notebook**: `notebook.html` is a page of swiftalk cells — Shift-Enter
runs a cell and moves on, Cmd/Ctrl-Enter runs in place, Alt-Enter runs
and inserts a cell below; a cell shows what it printed, then its value
(a nil stays silent), or its error; bindings persist from cell to cell;
the cells autosave in the browser, and save and open as JSON. Serve the
directory to use it from source (`python3 -m http.server`, then
`/notebook.html`), or `npm run build` and open `dist/notebook.html` from
a file — the runtime is inlined.

```js
import { Swiftalk, Interpreter, withPrelude } from './src/index.js';
Swiftalk.eval('[1, 2, 3].map { $0 * $0 }.reduce(0, +)');   // 14n — Int is a BigInt
const i = withPrelude(new Interpreter());                  // IO, Net, Regex, Sequence, Task, BigInt, BigRat, as the CLI has them
i.output = (s) => process.stdout.write(s);                 // where print goes
i.hooks.set('readLine', () => 'a line');                   // what the host lends: readLine, openFile, fetch — may return a Promise
i.eval('let x = 40'); i.eval('print(x + 2)');
await i.evalAsync('let t = async { Task.sleep(0.5); 42 }; await t');   // waits half a second; eval would not
```

In Node, `nodeHost(i)` from `src/host/node.js` lends stdin, stdout,
stderr, files, and `.swt` modules from disk or URLs.

| Where | What |
|---|---|
| `src/errors.js` | `SwiftalkError` — the five kinds, the core's wording |
| `src/lexer.js` | the lexer, line for line: tokens as tagged objects |
| `src/parser.js` | the parser, line for line: the AST as tagged objects, `TypeAnnotation` |
| `src/value.js` | the value model — JS primitives where they fit (`BigInt` for Int, `number` for Double, `string`, `boolean`, `null`), classes for the rest; `keyOf` for Dictionary and Set keys (canonical equivalence for Strings), `sourceString` with Swift's `Double` spelling and hex floats, graphemes through `Intl.Segmenter` |
| `src/objects.js` | `FunctionObject`, enum and struct types and values, `SequenceObject`, `TaskObject`, the control-flow signals |
| `src/env.js` | `Environment` and `Binding` — scopes, type-locked declaration and assignment |
| `src/types.js` | type locks, stamps, inference — `checkValue`, `inferLock`, `typeValue` |
| `src/builtins.js` | the type constructors (`Int(...)`, `Array(...)`, …), protocols and conformance, `Result`, the math library |
| `src/eval.js` | the evaluator — statements, expressions, application, assignment paths, operators, iteration; every function that can run swiftalk code is a `function*` |
| `src/members.js` | the member switch (`.map`, `.sorted`, `.count`, …), conversions (`x.T()` is `T(x)`), String formats, `.pretty`, statics |
| `src/formats.js` | SION text, JSON, XML and binary property lists, string escapes |
| `src/scheduler.js` | the cooperative scheduler, Task.swift without threads: contexts are generators, requests (spawn, await, sleep, offload, yield) pass the baton; `AsyncScheduler` on timers and Promises, `SyncScheduler` on a virtual clock |
| `src/modules.js` | the module API (`Module.function/export/type/extend/static/prelude`) and system (`register`, bare-name and `.swt` imports through `Interpreter.moduleLoader`, namespace types) |
| `src/modules/` | the prelude in JS: `IO.js` (`print`, `debugPrint`, `readLine`, the `IO` handle type), `Net.js` (`fetch`, `Response`), `Regex.js` (the `Regex` type behind `/re/`, String's regex members — over RegExp; see its FIXME), `Sequence.js` (`Sequence.zip`), `Task.js` (`Task.sleep`), `BigInt.js` (the `BigInt` type behind `123n`, over the platform's BigInt), `BigRat.js` (exact rationals, a pair of them) |
| `src/prelude.js` | `withPrelude(interp)`: the five registered and preimported |
| `src/host/node.js` | what Node lends: stdin, stdout, stderr, files, module loading |
| `notebook.html` | the notebook page (loads `src/index.js`; `npm run build` inlines it) |
| `tools/bundle.mjs` | the bundler, no dependencies: `dist/swiftalk.js`, `dist/notebook.html` |
| `src/interpreter.js` | `Interpreter` — the persistent global scope, `eval` (synchronous) and `evalAsync` (timers and Promises awaited) driving the generator, `register`, `preimport`; `needsMoreInput` for a REPL |
| `repl.mjs` | a REPL for Node over the runtime |
| `tools/extract-fixtures.mjs` | the Swift corpus → `test/fixtures.json` (generated, not committed; disabled Swift suites are dropped) |
| `test/` | Node's test runner |

## Milestones

1. **A — the pure subset** (round 197): lexer, parser, values, the
   fixture extractor and harness. Every value fixture parses.
2. **B — the evaluator** (round 198), generator-based from the first
   line: a `yield`, an `await`, a spawn, or a `sleep` anywhere is a
   request yielded up the whole interpreter stack to the driver, which
   answers and resumes — coroutine Sequences without threads. 2,553 of
   the 2,671 fixtures evaluate to the Swift core's value or throw where
   it throws; the 118 that name a prelude module (`print`, `Regex` and
   the regex literal, `Sequence.zip`, `Task.sleep`, `readLine`) wait
   for D. The driver is synchronous: `sleep` waits nothing yet.
3. **C — Tasks over real time** (round 199): the Swift scheduler
   without threads — contexts are generators, the baton passes at
   every request; `evalAsync` waits on timers and Promises, `eval` runs
   the same scheduler on a virtual clock. The module API and system in
   JS, `Task` and `Sequence` its first modules, `.swt` imports through a
   host loader. 2,588 fixtures pass; 83 wait for IO, Net, Regex.
4. **D — the prelude and the notebook** (round 200): IO, Net, Regex as
   JS modules over host hooks that may answer with Promises; a Node
   host and a browser host; the bundler; `notebook.html`. 2,665 of
   2,671 fixtures agree with the Swift core; the six that do not are
   Swift's Character-level Regex, pinned in the test as known
   divergences with their reasons.

FIXMEs are marked in the source where the port knowingly falls short.
