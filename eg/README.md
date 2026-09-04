# swiftalk by example — the `eg/` directory

Runnable examples (round 66). Run any of them with:

```sh
swift run swiftalk eg/lambda.swt
```

(`swiftalk file.swt` is script mode: the whole file evaluates as one
strict program, and only `print()` output appears. Piping into the
bare `swiftalk` remains REPL mode, echoes and all.)

Every example is verified by the test suite (`EgTests`) — the quine
laws are checked byte-for-byte, the outputs line-for-line.

* **[quine.swt](quine.swt)** — the *value* quine:
  `Swiftalk.eval(source)` returns `.string(source)`, exactly. The
  engine is `.String(.quoted)`, whose escaping is canonical (§3d) —
  write the data literal in that same escaping and the round-trip
  law does the rest. (In script mode it prints nothing — its law
  lives at the `eval` level.)
* **[quine-print.swt](quine-print.swt)** — the *printing* quine:
  `swift run swiftalk eg/quine-print.swt` outputs its own source,
  byte for byte, trailing newline included.
* **[lambda.swt](lambda.swt)** — lambda calculus: Church booleans,
  numerals, pairs, PRED, and the **Z combinator** with an anonymous
  factorial. Swift cannot type `x(x)`; swiftalk has one `Function`
  type, so the classical terms transcribe directly.
* **[ski.swt](ski.swt)** — SKI combinators, plus the iota bird
  deriving all three from one.
* **[array.swt](array.swt)** — Arrays: COW copies, inferred element
  locks, `map`/`filter`/`reduce`, nested paths — and `reverse`,
  `contains`, `join`, and a sort written in swiftalk, since no
  builtin exists for them yet.
* **[dictionary.swt](dictionary.swt)** — Dictionaries: `[Key: Value]`
  with any Hashable key, nil as a stored value vs `.has`, the
  sparse-array idiom, and a histogram.
* **[sion.swt](sion.swt)** — **MySION**, a SION parser written in
  swiftalk (round 85): swift-sion's README sample, every literal
  form, `.Date`/`.Data` with a hand-rolled base64, `\u{...}` built
  from UTF-8 bytes, comments — and the round-trip law verified
  through it. No RegExp, no String subscripts. The write-up, with
  what carried it and what got in the way, is [sion.md](sion.md).
* **[formats.swt](formats.swt)** — SION built in (round 97): a
  document read with `SION(text)`, written back with `.String()`,
  and carried through JSON and property lists (XML and `bplist00`)
  and back, `==` at every step; Data's base64 literal.
* **[sequence.swt](sequence.swt)** — Sequences, lazy by default: a
  generator, coroutines that `yield`, deferred `map`/`filter`,
  infinite primes pulled by `.prefix` and `for`-`in` with `break`.
