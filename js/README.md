# swiftalk in JavaScript

The core runtime — the interpreter of `Core/Sources/Swiftalk` — ported to
JavaScript (round 197 onward), so swiftalk runs wherever a modern JS
engine does: Node 22+, and the browser. The port takes the core alone;
`import` waits, and the prelude modules follow as JS once the evaluator
stands. What the Swift core does, this does, checked against the same
corpus: `tools/extract-fixtures.mjs` turns every `eval(source) == value`
expectation in `Tests/SwiftalkTests` into JSON, and the tests here run
the JS runtime over it.

```sh
cd js
npm test            # extracts the fixtures, then node --test
```

| Where | What |
|---|---|
| `src/errors.js` | `SwiftalkError` — the five kinds, the core's wording |
| `src/lexer.js` | the lexer, line for line: tokens as tagged objects |
| `src/parser.js` | the parser, line for line: the AST as tagged objects, `TypeAnnotation` |
| `src/value.js` | the value model — JS primitives where they fit (`BigInt` for Int, `number` for Double, `string`, `boolean`, `null`), classes for the rest; `keyOf` for Dictionary and Set keys (canonical equivalence for Strings), `sourceString` with Swift's `Double` spelling and hex floats, graphemes through `Intl.Segmenter` |
| `tools/extract-fixtures.mjs` | the Swift corpus → `test/fixtures.json` (generated, not committed; disabled Swift suites are dropped) |
| `test/` | Node's test runner |

## Milestones

1. **A — the pure subset** (round 197): lexer, parser, values, the
   fixture extractor and harness. Every value fixture parses.
2. **B — the evaluator**, generator-based from the first line so that
   `await` and `yield` can suspend the whole interpreter stack later:
   arithmetic, strings, collections, closures, control flow, structs,
   enums, extensions, type locks and stamps, Formats.
3. **C — Tasks and coroutines** on that generator substrate.
4. **D — the prelude as JS modules** (IO, Net, Regex, Sequence, Task)
   and the notebook page.

FIXMEs are marked in the source where the port knowingly falls short.
