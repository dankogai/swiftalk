# swiftalk in JavaScript

The core runtime — the interpreter of `Core/Sources/Swiftalk` — ported to
JavaScript (round 197 onward), so swiftalk runs wherever a modern JS
engine does: Node 22+, and the browser. The port takes the core alone;
`import` waits, and the prelude modules follow as JS now that the
evaluator stands (`node js/repl.mjs` is a REPL over it). What the Swift core does, this does, checked against the same
corpus: `tools/extract-fixtures.mjs` turns every `eval(source) == value`
expectation in `Tests/SwiftalkTests` into JSON, and the tests here run
the JS runtime over it.

```sh
cd js
npm test            # extracts the fixtures, then node --test
node repl.mjs       # a REPL over the runtime (pipe a program in, or type)
```

```js
import { Swiftalk, Interpreter, TaskModule, SequenceModule } from './src/index.js';
Swiftalk.eval('[1, 2, 3].map { $0 * $0 }.reduce(0, +)');   // 14n — Int is a BigInt
const i = new Interpreter();
i.register(TaskModule()); i.register(SequenceModule()); i.preimport(['Task', 'Sequence']);
i.declareBuiltin('print', (args) => { console.log(...args); return null; });
i.eval('let x = 40'); i.eval('print(x + 2)');
await i.evalAsync('let t = async { Task.sleep(0.5); 42 }; await t');   // waits half a second; eval would not
```

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
| `src/modules/` | the prelude modules in JS: `Task.js` (`Task.sleep`), `Sequence.js` (`Sequence.zip`) — IO, Net, Regex to come |
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
4. **D — the rest of the prelude as JS modules** (IO over the host's
   output, Net over `fetch`, Regex over `RegExp`) and the notebook page.

FIXMEs are marked in the source where the port knowingly falls short.
