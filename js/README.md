# swiftalk in JavaScript

The core runtime — the interpreter of `Core/Sources/Swiftalk` — ported to
JavaScript (round 197 onward) and written in TypeScript since round 255
(`src/**/*.ts`, compiled by `tsc` to `lib/`), so swiftalk runs wherever a
modern JS engine does: Node 22+, and the browser — the core, the prelude (IO,
Net, Regex, Sequence, Task, BigInt, BigRat) as JS modules, and a notebook page. What the Swift core does, this does, checked against the same
corpus: `tools/extract-fixtures.mjs` turns every `eval(source) == value`
expectation in `Tests/SwiftalkTests`, and every `#expect(throws:)` of an
`eval`, into JSON, and the tests here run the JS runtime over it.

```sh
cd js
npm install         # typescript and @types/node, the only dependencies, for development
npm test            # extracts the fixtures, compiles (tsc → lib/), then node --test over lib/test
npm run repl        # a REPL over the runtime, with the prelude (pipe a program in, or type) — lib/repl.js
npm run build       # tsc, then dist/swiftalk.js (one file), dist/notebook.html (the notebook, runtime inlined), and dist/notebook.fragment.html (the same page without its document skeleton, for hosts that supply one)
```

**TypeScript and the package** (round 255): the sources are `src/**/*.ts`,
`test/*.ts`, and `repl.ts`; `tsc` (`tsconfig.json`: ES2022, Node's module
resolution, plain `strict` — no `any`, no cast, no `!` in the sources:
round 256's rule, literally so since round 264 cleared the thirty that
had survived it) emits `lib/` with
declarations beside every file, and nothing runs from `src/` directly —
the tests, the REPL, the bundler and the notebook all read `lib/`.
`package.json` is laid out for `npm publish` (not yet published): `main`
and `types` point at `lib/src/index.js` and its `.d.ts`, `exports` adds
`swiftalk/node` for the Node host, `bin` gives `swiftalk-js` (the REPL),
`files` ships `lib/src` and the REPL only, and `prepublishOnly` builds.
The types worth knowing: `Value` (the value model as a union) and its
guards `isArray`, `isString`, `isFunction`… (one per kind, narrowing as
`kindOf` cannot), `Token`, `Expr`/`Stmt`/`Pattern` (the AST), `Role`,
`HostObject` (what a module's value implements), `Builtin`, `Request`
and `Answer` (the scheduler's protocol behind `G<T>`), `Hooks` and
`HookTable` (what a host lends, by name), `Extension`.

**The notebook**: `notebook.html` is a page of swiftalk cells — Shift-Enter
runs a cell and moves on, Cmd/Ctrl-Enter runs in place, Alt-Enter runs
and inserts a cell below; a cell shows what it printed, then its value
(a nil stays silent), or its error; bindings persist from cell to cell;
the cells autosave in the browser, and save and open as JSON. Serve the
directory to use it from source (`python3 -m http.server`, then
`/notebook.html`), or `npm run build` and open `dist/notebook.html` from
a file — the runtime is inlined.

```js
import { Swiftalk, Interpreter, withPrelude } from './lib/src/index.js';   // or from 'swiftalk', installed
Swiftalk.eval('[1, 2, 3].map { $0 * $0 }.reduce(0, +)');   // 14n — Int is a BigInt
const i = withPrelude(new Interpreter());                  // IO, Net, Regex, Sequence, Task, BigInt, BigRat, as the CLI has them
i.output = (s) => process.stdout.write(s);                 // where print goes
i.hooks.set('readLine', () => 'a line');                   // what the host lends: readLine, openFile, fetch — may return a Promise
i.eval('let x = 40'); i.eval('print(x + 2)');
await i.evalAsync('let t = async { Task.sleep(0.5); 42 }; await t');   // waits half a second; eval would not
```

In Node, `nodeHost(i)` from `lib/src/host/node.js` (`swiftalk/node`, installed) lends stdin, stdout,
stderr, files, and `.swt` modules from disk or URLs.

| Where | What |
|---|---|
| `src/errors.ts` | `SwiftalkError` — the five kinds, the core's wording |
| `src/lexer.ts` | the lexer, line for line: tokens as tagged objects |
| `src/keywords.ts` | the keyword list, Parser.swift's, as one Set |
| `src/parser.ts` | the parser, line for line: the AST as tagged objects, `TypeAnnotation` |
| `src/value.ts` | the value model — JS primitives where they fit (`BigInt` for Int, `number` for Double, `string`, `boolean`, `null`), classes for the rest; the `Value` union and a type guard per kind (`isArray`, `isString`, `isFunction`…, round 256) with `must` for a lookup that cannot miss and `codePointOf` for a grapheme's first scalar (round 264); `keyOf` for Dictionary and Set keys (canonical equivalence for Strings), `sourceString` with Swift's `Double` spelling and hex floats, graphemes through `Intl.Segmenter` |
| `src/objects.ts` | `FunctionObject`, enum and struct types and values, `SequenceObject`, `TaskObject`, `HostValue` and `HostObject` (a module's value), `ContextObject`, the control-flow signals; the scheduler's `Request` and `Answer` and the `G<T>` generator type every suspending function returns (round 256) |
| `src/env.ts` | `Environment` and `Binding` — scopes, type-locked declaration and assignment |
| `src/types.ts` | type locks, stamps, inference — `checkValue`, `inferLock`, `typeValue` |
| `src/builtins.ts` | the type constructors (`Int(...)`, `Array(...)`, …), protocols and conformance, `Result`, the math library |
| `src/eval.ts` | the evaluator — statements, expressions, application, assignment paths, operators, iteration; every function that can run swiftalk code is a `function*` |
| `src/members.ts` | the member switch (`.map`, `.sorted`, `.count`, …), conversions (`x.T()` is `T(x)`), String formats, `.pretty`, statics |
| `src/formats.ts` | SION text, JSON, XML and binary property lists, string escapes |
| `src/scheduler.ts` | the cooperative scheduler, Task.swift without threads: contexts are generators, requests (spawn, await, sleep, offload, yield) pass the baton; `AsyncScheduler` on timers and Promises, `SyncScheduler` on a virtual clock |
| `src/modules.ts` | the module API (`Module.function/export/type/extend/static/prelude`, `exported(name)` to read one back) and system (`register`, bare-name and `.swt` imports through `Interpreter.moduleLoader`, namespace types) |
| `src/modules/` | the prelude in JS: `IO.ts` (`print`, `debugPrint`, `readLine`, the `IO` handle type), `Net.ts` (`fetch`, `Response`), `Regex.ts` (the `Regex` type behind `/re/`, String's regex members — over RegExp; see its FIXME), `Sequence.ts` (`Sequence.zip`), `Task.ts` (`Task.sleep`), `BigInt.ts` (the `BigInt` type behind `123n`, over the platform's BigInt), `BigRat.ts` (exact rationals, a pair of them) |
| `src/prelude.ts` | `withPrelude(interp)`: the seven registered and preimported (five until round 201; `preludeNames` is the list) |
| `src/index.ts` | the public surface — every name the runtime exports, what the examples above import |
| `src/host/node.ts` | what Node lends: stdin, stdout, stderr, files, module loading |
| `notebook.html` | the notebook page (loads `lib/src/index.js`, so `npm run build` or `npx tsc` first; the build inlines it) |
| `tools/bundle.mjs` | the bundler, no dependencies, one scope for all modules (so top-level names must not collide): `dist/swiftalk.js`, `dist/notebook.html`, `dist/notebook.fragment.html` |
| `src/interpreter.ts` | `Interpreter` — the persistent global scope, `eval` (synchronous) and `evalAsync` (timers and Promises awaited) driving the generator, `register`, `preimport`, `hooks` (a `HookTable` typed by name: `readLine`, `openFile`, `fetch`; `HostFile` is what `openFile` answers); `needsMoreInput` for a REPL |
| `repl.ts` | a REPL for Node over the runtime — `lib/repl.js`, the package's `swiftalk-js` |
| `tsconfig.json`, `package.json` | the compiler's settings (`lib/` out of `src/`, `test/`, `repl.ts`) and the npm package's layout (round 255) |
| `tools/extract-fixtures.mjs` | the Swift corpus → `test/fixtures.json` (generated, not committed; disabled Swift suites are dropped) |
| `test/` | Node's test runner, in TypeScript — run compiled, from `lib/test/` |

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

Since D the port has kept pace with the Swift core round by round:
`BigInt` (round 201, the `123n` literal over the platform's BigInt) and
`BigRat` (round 203) joined the prelude as JS modules, and the fixtures
are extracted afresh on every `npm test`, so the corpus is whatever the
Swift tests hold — 3,042 fixtures as of round 276, the same six
divergences and no others.

FIXMEs are marked in the source where the port knowingly falls short.
