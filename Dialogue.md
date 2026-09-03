# swiftalk — Dialogue log

The append-only, chronological record of the design dialogue:
one entry per round, revisions citing what they revise, nothing
ever rewritten. Sections live in [Design.md](Design.md); this is
the history. (Moved out of Design.md in round 65.)


* **2026-08-28** — Project start. Decided: name, `[Key: Value]` dictionary
  literals. Opened: semantic model (§1), type discipline (§3), value
  semantics (§4), implementation host (§5).
* **2026-08-28, round 1** — Decided: semantic model is *Dynamic Swift*
  (§1); *strong latent typing with type-locked bindings*, runtime-queryable
  via `x.type` (§3); full Optional suite (§3a); COW value semantics for
  collections (§4). Opened: numeric tower, `Any` & heterogeneous
  collections, first-classness of types.
* **2026-08-28, round 2** — Decided: bignum `Int` + distinct `Double`
  (§3b); `Any` exists for now but enums/unions preferred (§3c); `var`/`let`
  mandatory in files, relaxed in REPL (§2.2); argument labels optional and
  reorderable, trailing-closure slot pinned last (§2.3). Opened: dispatch &
  overloading (§6), enums & pattern matching (§7), error handling (§8).
* **2026-08-28, round 3** — Decided: one name, one function — no free-
  function overloading; methods dispatch on receiver type (§6); full Swift
  enums with runtime exhaustiveness enforcement (§7); **Result-first error
  handling, no exceptions** (§8); both `struct` (COW value) and `class`
  (reference, inheritance) with Swift semantics (§4). Opened: propagation
  sugar spelling (§8), protocols/extensions/generics (§10), strings (§11),
  concurrency (§12).
* **2026-08-28, round 4** — Decided: Rust-style postfix `?` for Result
  propagation; no `throw`/`do-catch` (§8); protocols *and* extensions,
  Swift-style (§10); full `<T>` generics *for the time being, subject to
  change* (§10); Swift-faithful grapheme strings (§11). Added §13
  "swiftalk by example". Opened: mixed error types under `?` (§8),
  integer subscripts on String (§11).
* **2026-08-28, round 5 — basic types (§3b). REVISES round 2**: `Int` is
  now **fixed 64-bit, device-independent** (was: arbitrary-precision);
  bignum demoted to a possible distinct `BigInt` with `n`-marked
  literals, undecided. Also decided: `nil` has an honest type (no
  `typeof null === 'object'`); `Bool` is not numeric; `Double` distinct
  from `Int`; `String` has `.utf8`/`.utf32` views but **no `.utf16`**;
  `Data` (bytes) distinct from `String`; `Array` is a real array;
  `Dictionary` stringifies as `[Key: Value]`. Opened: `nil.type` and
  `var x = nil`, Int overflow behavior, BigInt adoption, Data literals.
* **2026-08-28, round 6** — Decided: `Int` overflow **traps** (§3b);
  `BigInt` is **in but detachable** (§3b) — which crystallized a broader
  goal: **minimal core implementation, Lua as the size benchmark,
  detachable batteries** (§5). `nil` is swiftalk's JS-`undefined`,
  done honestly (§3b). New language-wide convention: **`obj.TypeName`
  is the type converter** (§3d) — `data.String` failable, `string.Data`
  infallible, `.String` mandatory on every type; lowercase `.type`
  queries, Capitalized `.Type` converts. Opened: BigInt literal
  spelling, `&+` family, initializer-style conversions, Optional/nil
  interplay.
* **2026-08-29, round 7** — Added §13 Milestones: 0. `eval()`,
  1. REPL (a loop around `eval()`); later milestones TBD. Opened:
  whether `eval()` is exposed in the language itself.
* **2026-08-29, round 8** — Decided: file extension is **`.swt`** (§13).
* **2026-08-29, round 9** — Decided: **no `func` — `{}` closure
  literals are the only function form**, bound with `let`/`var` (§2.4).
  `$` is the universal placeholder (the arguments as an array), `$0` ≡
  `$[0]`, arity = `$.count`; variadics fall out for free, and §6's
  one-name-one-function becomes a theorem. Opened: recursion in
  `let f = {...}`, arity-mismatch behavior, method/`init` declaration
  without `func`, closure type annotations, params-as-labels.
* **2026-08-29, round 10** — Decided: **`$` is also callable — `$()`
  recurses into the current function** (`$.callee` considered, callable
  `$` chosen); **strict arity** for named-param functions (runtime
  error on mismatch), param-less `$` functions stay variadic;
  Swift-style annotations allowed in closures; **declared param names
  double as reorderable call-site labels**. Method/`init` syntax
  deferred until milestone 0. Opened: `{ 42 }` called with arguments.
* **2026-08-29, round 11** — Decided: **`{ constant }` collapses to
  the constant** — `{ 42 }` evals to `42`; applies to any constant
  (§2.4). Opened: the exact boundary for non-constant param-less
  bodies (presumably still deferred closures).
* **2026-08-29, round 12 — CORRECTS round 11**: no collapsing —
  **`{ }` always makes a `Function`**. `{ 42 }` is a zero-param
  function that is `42` only when evaluated: `{42}.type == Function`,
  `{42}().type == Int` (§2.4). `Function` added to the basic-type
  roster (§3b). Opened: parameterized signature in `.type`?; args
  passed to a param-less, `$`-less function.
* **2026-08-29, round 13** — Decided: **`Function` is one collective
  type**, JS-style — signatures are not part of the type; arity/type
  mismatches trap at runtime, with compile-time catches as best-effort
  diagnostics, never a guarantee (§2.4, §3b). Still open: args passed
  to a param-less, `$`-less function (`array.map { 0 }` is the nub).
* **2026-08-29, round 14** — Decided: **no declared params = variadic**
  — strict arity applies only when parameters are declared;
  `array.map { 0 }` is valid, and `array.fill(0)` must be identical to
  it (§2.4). §2.4 (functions) is now complete but for method syntax
  (deferred to milestone 0).
* **2026-08-29, round 15 — nil & Optional settled (§3a)**: **flat
  union model** — `T?` is "`T` or `nil`", no `Optional<T>` box, no
  `.some`/`.none`, no nesting (`Int??` ≡ `Int?`); `nil` is the sole
  value of type `Nil`; bare `var x = nil` is an error; postfix `?`
  unified across Optionals and Results, postfix `!` kept (traps);
  `[K: V?]` lookups collapse missing/stored-nil, `d.has(k)` for the
  distinction. Opened: confirm `d[k] = nil` deletes (Swift-compatible).
* **2026-08-29, round 16** — Added built-in **`enum Primitives`**
  (§3c): one case per §3b primitive (`nil`, `Bool`, `Int`, `Double`,
  `String`, ...), a closed, exhaustively-switchable sum whose purpose
  is to keep users away from `Any`. Opened: exact case roster
  (BigInt/Data/Function/collections → JSON-complete?), case naming,
  implicit lifting (does `[1, "one", 2.0]` infer `[Primitives]`?).
* **2026-08-29, round 17** — **`Primitives` is SION-complete** (§3c):
  cases for `nil`, `Bool`, `Int`, `Double`, `String`, `Data`, `Date`,
  plus `Array`/`Dictionary` of `Primitives` (non-`String` keys
  included) — hence JSON-complete. **SION is swiftalk's native
  serialization format** (as JSON is to JS);
  https://github.com/dankogai/swift-sion. Consequence: **`Date` joins
  the basic types** (§3b). Opened: SION `Ext`, `Date`
  representation/literals; still open: case naming, implicit lifting.
* **2026-08-29, round 18** — Decided: **`[1, "one", 2.0]` infers
  `[Primitives]`** with implicit lifting; **`Any` arises when and only
  when explicitly written** (`var a: [Any] = []`) — never from
  inference (§3c). Opened: what `.type` reports for a lifted element;
  the unwrap surface.
* **2026-08-29, round 19 — refines round 6**: the type converter is a
  **method, `obj.TypeName()`**, not a property — parentheses accept
  format arguments: `255.String(.hex)` → `"ff"`; encodings for
  `Data`⇄`String` (UTF-8 default), date formats, etc. (§3d).
  `.String()` remains mandatory on every type; lowercase `.type` stays
  a property.
* **2026-08-29, round 20** — Refined §3d formats: **`.String(.hex)` ≠
  `.String(radix: 16)`** — the enum form prepends the literal prefix
  (`0xff`, `0o377`, `0b...`), the `radix:` form emits bare digits;
  same for `Double` (hex-float notation).
* **2026-08-29, round 21** — Confirmed as a language invariant:
  **prefixed strings round-trip** — `x.String(.hex).Int()! == x` holds
  for every `Int` (likewise `.oct`/`.bin`, and `Double` via hex-float)
  (§3d).
* **2026-08-29, round 22** — Decided: **`Primitives` is a flat union**,
  same model as `T?` — no box, `x.type` reports `Int` (never
  `Primitives`), `case .Int(let i)` classifies rather than unwraps
  (§3c). User-defined enums still box. Remaining `Primitives` opens:
  `Ext`, `BigInt`, case naming.
* **2026-08-29, round 23** — **The general round-trip law**:
  `.String()` emits swiftalk source that restores the value —
  `eval(x.String()) == x` for **all** data types; `(0.1 + 0.2).String()`
  is `"0.30000000000000004"`, not `"0.3"` (shortest-round-trip
  decimals). For `Primitives` values `.String()` *is* SION emission.
  Consequences: `String.String()` quotes+escapes; bare `Data.String()`
  becomes infallible source form with failable decode moving to
  `data.String(.utf8)` (revises round 6's example). Opened: what
  `print`/interpolation use (quoted vs raw), `Function.String()`.
* **2026-08-29, round 24** — Decided: **functions are also
  coroutines — any function can `yield`** (§2.4); no separate
  generator syntax, the Lua model. §12 notes coroutines as the
  cooperative-concurrency substrate. Opened: creation/resume surface,
  `for`-`in` integration, values through `yield`/resume, `.type` of a
  suspended instance, `yield` scoping in nested closures.
* **2026-08-29, round 25** — Refined protocols (§10):
  **coarse-grained** — no Swift-style fine taxonomy; at minimum
  **`Sequence`**, conformed to by `String`, `Array`, `Dictionary`.
  **Types are constructor `Function`s** (`Type()` constructs;
  `Int.type == Function`) — resolving §3's first-classness question —
  with **`.conforms(to:)`** as the runtime conformance test (JS
  `instanceof`'s role). §3d: initializer-style spelling exists after
  all, as construction. Opened: constructor-vs-converter division of
  labor; `is`/`as?` as sugar.
* **2026-08-29, round 26** — Decided: **`Equatable`/`Hashable`/
  `Comparable` exist**, with built-in types conforming natively (§10);
  `Hashable` gates dictionary keys, so every `Primitives` type hashes.
  Opened: per-type coverage (`Function` equality, `Comparable` reach),
  synthesis for user types.
* **2026-08-29, round 27 — milestone 0 begins.** First Swift code:
  `eval()` over primitives — scalar & collection literals (radix
  prefixes included), same-type arithmetic with trapping overflow,
  unary minus, comments, and two members: `.String()` (source form)
  and `.type` (as a name, until types become constructor Functions).
  The round-trip law `eval(x.String()) == x` is the anchor test and
  passes. CI re-enabled.
* **2026-08-29, round 28 — let/var with type locks implemented.**
  Multi-statement programs (newline or `;` separated; newlines flow
  freely inside brackets; a program evaluates to its last statement's
  value); `let`/`var` declarations with runtime-enforced annotations
  incl. `Int?` flat optionals; the §3 lock, `let` immutability,
  no-redeclaration, and reject-undeclared-assignment all enforced;
  `Interpreter` class with a persistent environment (the REPL's
  engine). Decisions made in passing: **trailing commas allowed** in
  collection literals and argument lists (as Swift 6.1+); a
  declaration evaluates to its bound value. Inference locks are
  coarse for now (`Array`, not `[Int]`) — element-type locks TBD.
* **2026-08-29, round 29 — milestone 1: the REPL.** `swift run
  swiftalk`: relaxed mode per §2.2 (bare `x = 1` declares a var,
  still type-locked; file mode stays strict); the printer is
  `.String()` source form, so echoes re-enter as what they were —
  answering §3d's open "what does the REPL print" with *quoted*
  (the raw display form for `print` proper remains OPEN);
  multi-line continuation while brackets are open
  (`needsMoreInput`); non-TTY stdin suppresses prompts.
* **2026-08-29, round 30 — `{}` functions with `$` implemented
  (§2.4).** `Function` joins `Value` (identity equality, one
  collective type); closure literals with optional `x, y in` params;
  calls with §2.3 labels (optional, reorderable, mixable with
  positionals); strict arity for declared params, variadic via `$`
  otherwise (`{ 0 }(1,2,3)` works); `$`, `$0…`, `$.count`
  per-closure with shadowing; **`$()` recursion works** —
  `fac(20)` exact, `fac(21)` traps. Lexical closures via
  environment chains, mutation included, locks reaching through.
  Companions needed to make recursion testable: **comparison
  operators** (`==`/`!=` any same-type; `< <= > >=` on
  Int/Double/String; `x == nil` of anything; mixing types errors)
  and **ternary `?:`** (Bool condition only — nothing is truthy).
  `.count` on String/Array/Dictionary (graphemes for String).
  Newlines are separators inside `{}` but not `[`/`(`.
  `Function.String()` emits a placeholder — source text still OPEN.
* **2026-08-29, round 31 — embedding-API housekeeping.** The Swift
  public surface is namespaced: a caseless `public enum Swiftalk`
  holds `eval`, `Interpreter`, `needsMoreInput`, `Value`,
  `FunctionObject`, and `Error` (`SwiftalkError` renamed to idiomatic
  `Swiftalk.Error`). Importing the library claims exactly one
  top-level name — befitting §5's embeddable-scripting-layer goal.
  Implementation keeps terse internal typealiases.
* **2026-08-29, round 32 — subscripts implemented.** Reads: `a[i]`
  with Int index, trapping out-of-range/negative (Swift-faithful);
  `d[k]` flat-optional (missing → `nil`, §3a); chained; on any
  expression. Writes through lvalue paths (`a[i] = x`,
  `m[1][0] = x`, `d[k] = v`) as read-modify-write over COW values —
  `let` collections immutable, value semantics verified
  (copy-then-mutate leaves the copy alone). **`d[k] = nil` deletes
  the key** (implements round 15's "presumably", still awaiting
  confirmation). **`$0` is now literally `$[0]`** — the parser
  desugars `$N`, and the pre-bound `$N` variables are gone.
  `String[Int]` errors, pointing at §11's open question.
* **2026-08-29, round 33 — `if`/`else` and loops, Swift-style.**
  `if`/`else if`/`else` (Bool-only conditions — nothing is truthy),
  `while`, `repeat`-`while`, `for`-`in`, `break`/`continue` (which
  cannot escape a function body); blocks are child scopes;
  control-flow statements evaluate to `nil` (statements, as in
  Swift — an if-*expression* à la Swift 5.9 is a possible later
  refinement). `for`-`in` iterates §10's Sequence conformers:
  Array elements, String graphemes (as single-`Character` `String`s
  until a `Character` type is decided), Dictionary `[key, value]`
  pair-arrays (until tuples are decided). **Ranges arrived
  provisionally**: `a...b` / `a..<b` on Ints evaluate to eager
  `[Int]` arrays (`a > b` traps as in Swift) — **OPEN**: a real lazy
  `Range` type, its place in `Primitives`/SION, `Comparable`
  generalization.
* **2026-08-29, round 34 — string interpolation, Swift-style.**
  `"\(expr)"` with any expression inside (calls, subscripts, ternary,
  `$`), nested strings-in-interpolations to arbitrary depth, `\\(`
  staying a literal. **Display decision (partially answers round
  23's OPEN)**: inside interpolation a `String` embeds *raw*
  (`"\("a")"` is `"a"`), every other type embeds as its `.String()`
  source form — exactly Swift's `description` behavior. What bare
  `print()` does — and indeed adding `print()` at all, as the first
  built-in function value in the global environment — remains OPEN.
* **2026-08-29, round 35 — REVISES rounds 15/32: `d[k] = nil` does
  NOT delete.** `nil` is a right value for a key; presence is checked
  via **`d.has(k)`** (implemented: `true` for a stored `nil`, `false`
  for a missing key). Reads still collapse (`d[k]` is `nil` in both
  cases), but no-key and has-an-empty-key are semantically distinct.
  Diverges from Swift's subscript-assignment-deletes. Opened: the
  explicit removal API, since assignment no longer deletes.
* **2026-08-29, round 36 — `print()` and `debugPrint()`.** Completes
  round 23's display question, the Swift way: **`print` is raw
  display** (Strings bare, everything else `.String()` source form —
  the same rule as interpolation), **`debugPrint` is source form for
  everything** (quoted, round-trippable). Space-separated,
  newline-terminated, return `nil`. Structurally: **the first
  built-in `Function` values** — pre-bound `let`s in the global
  environment, per §2.4's stdlib-as-values philosophy (they reject
  labels, resist global redeclaration, shadow lexically, and pass
  around like any function). Output routes through an embedder hook
  (`Interpreter.output`, default stdout) — the host owns I/O, as in
  Lua (§5). The REPL suppresses `nil` echoes (the Python way), so
  statements and `print` don't double-report.
* **2026-08-29, round 37 — trailing closures, map/filter/reduce,
  `d.remove(k)`, and hex debugDescription.** Decisions: **`d.remove(k)`**
  is the explicit dictionary removal (mutating, returns the removed
  value or `nil`; requires a `var` path) — closing round 35's OPEN.
  **`print`/`debugPrint` are `description`/`debugDescription`**, and
  for `Int`/`Double`, `description` is decimal for the human's sake
  while **`debugDescription` is hexadecimal for the programmer's**
  (`0xff`; `0x1.fep7` hex-float — recursively through collections;
  exposed as `.description`/`.debugDescription` members). Note: hex
  Int output re-enters via the lexer; hex-*float* literals are not
  yet lexable — that half of the round trip is OPEN. Implemented:
  **trailing closures** (bare `f { }`, after args, on methods,
  chained; disabled inside control-flow headers, Swift's rule) and
  **`map`/`filter`/`reduce`** over the Sequence conformers —
  prerequisites for `Sequence` proper — with Swift-compatible result
  types (`String.filter` → `String`, `Dictionary.filter` →
  `Dictionary`). §14's opening example, `(1...20).reduce(1) { $0 * $1 }`,
  now runs verbatim.
* **2026-08-29, round 38 — `Range` decided and `Sequence`
  implemented.** *(Supersedes round 33's eager-array provisional.)*
  **`Range` is a first-class lazy type, `Range<I>`**: `I` accepts
  only `Int` today, is designed to admit `BigInt` someday (BigInt
  stays unimplemented), and never `Double` — narrowing Swift's
  versatile `Range` on purpose. `(1...10^12).count` is O(1); huge
  ranges iterate without materializing; offset subscript `r[i]`;
  prints as its literal (`"1...5"` — round-trips, hex in
  debugDescription); not in `Primitives`/SION — a language value,
  not an interchange value. **`Sequence` is now uniform behavior**
  over its four conformers — `Array`, `String`, `Dictionary`,
  `Range` — all driving `for`-`in`, `map`/`filter`/`reduce`,
  `.count`, and **`.Array()`**, the §3d converter doubling as the
  Sequence materializer. Iteration is lazy underneath (a Swift
  `AnySequence`). User-visible `conforms(to: Sequence)` awaits
  types-as-constructor-Functions (§10, round 25).
* **2026-08-29, round 39 — types as constructor Functions with
  `.conforms(to:)`, implemented** (§10, rounds 25/26 made real).
  `x.type` now returns **the constructor itself** — the singleton the
  global name binds — so `42.type == Int` is identity comparison, and
  a type's name round-trips (`eval("Int").String() == "Int"`).
  `Type()` gives Swift-style defaults (`Int() == 0`, `String() == ""`);
  `Type(x)` converts — identity from the same type, `nil` where the
  *value* can't convert (`Int("x")`), a type error where the source
  *type* never converts (`Int([1])`). `Int(s)` accepts everything the
  lexer does (`0x/0o/0b`, `_`); **`Double(s)` parses hex floats** —
  `Double("0x1.fep7") == 255.0` — closing the debugDescription round
  trip through the constructor (hex-float *literals* in source remain
  unlexable, OPEN). Protocols are values too (`Sequence`, `Equatable`,
  `Hashable`, `Comparable`; calling one is an error);
  `.conforms(to:)` — label optional per §2.3 — reads the conformance
  table: Sequence = the four iterables, Comparable = Int/Double/String,
  Equatable/Hashable = everything. Types are ordinary values: bind
  them, pass them (`make(Int, "7")`), use them as dictionary keys.
  Method calls gained labeled arguments along the way. Noted
  asymmetry, decided: `String(x)` is *description* (so `String("a")`
  is identity), while `x.String()` is source form (quoting).
* **2026-08-30, round 40 — `x.type` renamed to `x.Type`; constructors
  get `.name`.** `x.Type` returns the constructor Function, à la JS's
  `.constructor` (capitalized: type-talk members are Capitalized —
  `.Type` queries, `.TypeName()` converts). Stringification already
  agrees — a `Function` stringifies to its name when it has one. And
  since swiftalk's functions are anonymous, **constructors MUST carry
  `.name`, a `String`** (`Int.name == "Int"`, `42.Type.name == "Int"`;
  protocols carry theirs too); a plain `{ }`'s `.name` is `nil`.
  (Also repaired: §2.4's "no declared params means variadic" bullet
  header, accidentally clobbered by round 24's edit.)
* **2026-08-30, round 41 — Sequence types are lazy by default.**
  Unlike Swift, which opts in via `.lazy`, swiftalk's `Sequence`
  values defer everything until pulled. **`Sequence(initialState)
  { next }` constructs a generated sequence**: each pull calls the
  closure with the state elements as arguments; the *returned* value
  is the emitted element (**returning `nil` ends the sequence**); the
  closure's final `$` is the next state. The marquee runs verbatim:
  `Sequence([0, 1]) { $ = [$1, $0 + $1]; return $1 }.map { "\($0)" }`
  stays an unevaluated `Sequence` until `.prefix(n)` materializes
  `["1", "1", "2", "3", "5", ...]`. `map`/`filter` on a `Sequence`
  value return lazy `Sequence`s; `.prefix(n)` is the terminal
  (→ `Array`, on every conformer); `.count` on a `Sequence` errors
  (possibly infinite — take `.prefix` or `.Array()` deliberately);
  a `Sequence` value is re-iterable (generators restart from their
  initial state). `Sequence` remains the protocol (and now also
  constructs — fitting types-as-constructor-Functions); a lazy
  sequence's `.Type` is `Sequence`, conforming to itself.
  Two newcomers this forced, now general: **the `return` statement**
  and **reassignable `$`** with `$N` as entry snapshots (see §2.4).
  Eager `map` on Array/String/Dictionary/Range is unchanged —
  **OPEN**: whether those should also propagate laziness, and how a
  legitimate `nil` *element* coexists with nil-terminates.
* **2026-08-30, round 42 — `str.String()` is just `str`.** Argless
  `.String()` becomes *description* (identity on Strings; source form
  elsewhere), unifying `.String()` ≡ `String(x)` ≡ `print`'s form —
  round 39's asymmetry dissolved. **Quoting is explicit:
  `.String(.quoted)`**, and the round-trip law relocates:
  `eval(x.String(.quoted)) == x` for every value (argless still
  round-trips every non-String; nested Strings in collections stay
  quoted). Along the way, **implicit-member parsing** landed (`.hex`
  in argument position), unblocking rounds 20–21 as implemented:
  `.String(.hex)/.oct/.bin` (prefixed, literal-ready — the invariant
  now executes: `Int(255.String(.hex)) == 255`, hex-float `Double`s
  included) and `.String(radix: n)` (bare digits, 2–36). Format
  members evaluate *provisionally* as `String`s until enums land —
  flagged.
* **2026-08-30, round 43 — milestone added: self-hosting** (§13, not
  necessarily next): a swiftalk interpreter written in swiftalk —
  `eval.swt`. Distinct from milestone 0's Swift-implemented `eval()`;
  the metacircular proof that the language can describe itself, and
  the forcing function for enums, user types, `Data`, and stdlib
  maturity.
* **2026-08-30, round 44 — `.todo`: named recursion via deferred
  initialization** (§2.4). `let fact: Function = .todo` declares a
  placeholder; the one later assignment initializes it (then frozen —
  a `var` overwrites freely); the closure refers to `fact` *by name*,
  and mutual recursion falls out. Calling a `.todo` errors; displays
  as `.todo`; bare `= .todo` infers `Function`.
* **2026-08-30, round 45 — enums implemented (§7).** `enum Shape {
  case circle(r: Double), rect(w: Double, h: Double), point }` —
  associated values labeled or bare, multiple cases per line. The
  enum type is a **constructor Function** (round 39 style): member
  access constructs (`Shape.circle(r: 3.0)`, labels optional and
  reorderable per §2.3, associated types checked at runtime per §3;
  calling the type itself errors), `.name`/`.Type` work, and
  `conforms` reports **synthesized `Equatable`/`Hashable`** — enum
  values are structurally equatable and usable as dictionary keys.
  **`switch`** lands as a statement: `.case(let x)` destructuring,
  bare `.case` matching any payload, comma-shared patterns,
  expression patterns (`case 1, 2:`), Range patterns (`case 3...4:`),
  `_`, `default` — and §7's rule enforced: **no match with no
  `default` is a runtime error**. **`if case`** binds too;
  annotation-directed initializers work (`let s: Shape = .circle(r:
  1.0)`, the round-44 `.todo` mechanism generalized). Source form
  round-trips where the enum is declared. §14's `area` example runs.
  Boxing, not flat — the §3c contrast holds: `Wrap.just(42)` has
  typeName `Wrap` until destructured. OPEN: `guard case`/`if let`
  (still no `guard`), labeled patterns, `break` inside `switch`
  (currently loop-`break`, diverging from Swift), switch-as-
  expression, methods on enums (with user types), `Primitives` as a
  real declared enum, `indirect` enums.
* **2026-08-30, round 46a — case accessors: `.casename` by default.**
  Every enum value answers every of its type's case names — the
  associated value when it *is* that case, **`nil`** otherwise —
  dissolving the endless `if case .casename(let v)` ceremony (the
  piece Swift itself is missing; cf. the CasePaths libraries built to
  fake it). One payload comes bare (`s.circle` → `3.0`), several come
  as an `Array` (`s.rect` → `[w, h]` — tuples TBD), a payload-less
  case answers with itself (`s.point != nil` asks "is it `.point`?").
  Flat-optional in spirit: absence is `nil`, presence is the value.
* **2026-08-30, round 46b — structs implemented (§4).** `struct Point
  { var x: Int = 0\nvar y: Int = 0 }` — stored `var`/`let` properties
  with annotations and/or defaults (one of the two required; defaults
  evaluate at construction, in the declaring scope). **Calling the
  type is the memberwise initializer** (labels optional/reorderable
  per §2.3, positionals fill declaration order, annotations checked
  per §3). Property reads (`p.x`), writes through lvalue paths —
  including mixed nesting (`r.origin.x = 5`, `ps[1].y = 7`,
  `b.items[0] = 9`) — with `let` bindings and `let` properties both
  refusing. **COW value semantics verified**: copies are copies (§4,
  free from the Swift host). Structural `Equatable`/`Hashable`
  (dictionary keys work); `.Type`/`.name`/`conforms`; memberwise
  source form round-trips where declared. Engineering note: the
  evaluator's `execute`/`evaluate` split into thin hot dispatchers +
  slow paths — a Swift switch's frame carries the union of its cases'
  locals, and frame size is the language's recursion budget (round
  45's lesson, now structural). OPEN: **methods and `init` on user
  types — the §2.4 deferred question is now due**; also computed
  properties, `mutating`, nested type declarations, `class`.
* **2026-08-30, round 47 — the conversion law: `x.TypeName(tag:)` ≡
  `TypeName(x, tag:)`** (§3d; closes round 39's division-of-labor
  OPEN). One operation, two spellings, formats included —
  `dbl.String(radix: 16) == String(dbl, radix: 16)`; Swift prefers
  the constructor form, swiftalk keeps both with the method form
  favored for chaining. Implementation: one shared `convert` path
  behind both ends (constructor side: first unlabeled arg = subject,
  rest = formats). Consequences: the **full converter-method family
  now exists** (`"42".Int()`, `x.Double()`, `x.Bool()`,
  `"abc".Array()`, ...), sloppy extra constructor args now error
  instead of being ignored, and a bonus fell out:
  **`state.Sequence { next }` ≡ `Sequence(state) { next }`** —
  trailing-closure generator construction. OPEN: `Int(s, radix: 16)`
  parsing (Swift has it).
* **2026-08-30, round 48 — methods and `init` on user types;
  multi-dispatch initializers** (closing §2.4's oldest deferred
  question — see the updated §2.4 bullet for the full design).
  Methods: `let name = { ... }` in type bodies, `self` bound at
  invocation, uncalled access = bound `Function`, chaining through
  `map` et al. works, `$()` and `self.method()` both recurse. Enums
  get methods too (`switch self` inside), coexisting with round 46's
  case accessors. Inits: `init { params in ... }` with prefilled
  defaults, `self.x = ...` assignment, post-init verification of
  non-optional annotated properties, and **multi-dispatch** — first
  declared match on arity + labels wins, memberwise as the last
  candidate. Stored `Function` properties call through (`s.f()`).
  OPEN: mutating methods (`self` is a `let`), enum `init`, computed
  properties, runtime-type dispatch for inits, `class`.
* **2026-08-30, round 49 — mutating methods, implicit self, and
  extensions.** With `func` gone, **`mutating name = { ... }`** is the
  spelling (`mutating` replaces `let`); inside, `self` is a `var`, and
  the mutated self **writes back through the receiver's lvalue** —
  composing through nested paths (`arr[1].push(9)`), refusing `let`
  receivers and non-lvalues. **Implicit self**: in type/extension
  bodies, leading-dot members mean `self.` — `.value` reads,
  `.value = x` writes, `.method()` calls — the marquee runs verbatim:
  `mutating push = { item in .value.append(item) }`. Resolution
  prefers self's members, falling back to format members (a self
  member named `hex` shadows `.hex` — documented, tested).
  **`extension Name { ... }` implemented** (§10 delivered): `let` and
  `mutating` methods onto user types (merged into the type) and
  builtins (hidden per-scope bindings — declared and greppable, as
  §10's monkey-patching discipline demands): `extension Int { let
  doubled = { self * 2 } }`. **`Array.append` arrives** as the first
  builtin mutator (variadic, lvalue-bound). OPEN: the rest of the
  mutator family (insert/removeLast/...), extension `init`s/stored
  properties, enum mutating methods (`self = .case`).
* **2026-08-30, round 50a — REVISES round 49: the `mutating` keyword
  is unnecessary.** Functions are anonymous; a method is just a
  closure a name is assigned to — so whether it may mutate is not the
  *method's* declaration but **the properties' `var`/`let` and the
  receiver's `var`-ness**. Given `struct Foo { var x: Int ... }`, a
  method that assigns `.x` mutates `foo` when `foo` is a `var`; make
  `x` a `let` to suppress it. Implementation: `self` is always a
  `var` inside methods; **mutation is detected at runtime** (self
  compared before/after — §3's runtime-enforcement philosophy applied
  to methods) and written back through the receiver's lvalue; a `let`
  receiver or a temporary errors *only when actually mutated* — a
  read-only call on a `let` is fine. Bonus: **enum methods may
  reassign `self`** (`self = Gear.high`), closing round 49's OPEN.
  An uncalled method remains a closure bound over a *copy* (value
  semantics). Glimpsed in the dialogue and left OPEN: computed
  properties (`var getset { ... }`).
* **2026-08-30, round 50b — `Data` and `Date` implemented: the §3b
  SION roster is COMPLETE.** `Data` is `[UInt8]`, Foundation-free:
  `Data(str)` ≡ `str.Data()` (UTF-8 in, infallible),
  `data.String(.utf8)` decodes failably, `Data([255, 1])` is the
  round-tripping source form (hex under debug; SION's base64 OPEN),
  byte subscripts and `.count` read. `Date` is epoch seconds as a
  `Double` — SION's representation — printing SION's spelling
  `.Date(epoch)` (hex-float under debug, exactly as SION writes it),
  re-entering via a new sugar: **leading-dot type calls** —
  `.Date(x)` ≡ `Date(x)` when no `self` claims the name and the name
  binds a type. `Date()` is now (wall clock via `clock_gettime`);
  `Date` is `Comparable` (§10's "Date surely" honored). Every §3b
  primitive now exists: nil, Bool, Int, Double, String, Data, Date,
  Array, Dictionary — plus Function, Range, Sequence. OPEN: Data as
  Sequence, base64 format, byte-subscript writes, calendar output,
  debug hex-float literals in the lexer.
* **2026-08-30, round 51 — `Result` and the `?`/`!` family
  implemented** (§8 and §3a made real). **`Result` is a built-in
  enum** riding round 45's machinery — `switch`, round-46 case
  accessors (`r.success` → value-or-nil, `r.failure` → error-or-nil),
  equality, and `Result.success(42)` source form all free; payloads
  are **untyped** (a failure carries any value — §8's
  mixed-error-types OPEN answered as "E is untyped until typed errors
  are designed"). **Postfix `?`** unwraps `.success`, early-returns
  `.failure` *or* `nil` from the enclosing function (via the `return`
  machinery — one rule for absence and failure, as §3a unified);
  **postfix `!`** force-unwraps, trapping on either; **`??`** defaults
  on nil/failure, unwraps success, lazy on the right; **`?.`** skips
  the member (arguments unevaluated) on nil — chains of `?.` compose,
  though a bare `.` after nil errors rather than Swift's whole-chain
  short-circuit (noted divergence). Lexing disambiguation: unspaced
  `?` is postfix, spaced is ternary, `??` and unspaced `?.` are their
  own operators. §8's marquee chain runs:
  `Result.success(halve(halve(n)?)?)`.
* **2026-08-30, round 52 — coroutines and `yield` implemented**,
  closing round 24's OPEN surface (§2.4, §12). Asked, the user chose
  **Sequence-unified** creation (no `Coroutine` type: `Sequence(f)` /
  `f.Sequence()` / `Sequence { ... }` wraps a yielding Function into
  an ordinary lazy Sequence — `for`-`in`, `.map`/`.filter`/`.prefix`,
  `.Array()`, re-iterability, and `.Type == Sequence` all inherited)
  and **out-only** yields (symmetric Lua resume deferred, layerable
  later). `yield expr` emits an element; bare `yield` yields `nil`;
  `return` *terminates* (value discarded); `yield` outside a wrap
  errors, Lua's rule — so an unwrapped call of a yielding function is
  a plain call. One divergence from round 24's speculation, decided
  the Lua way: **`yield` is dynamic, not lexical** — it suspends the
  innermost *running* coroutine, so helper functions can yield on the
  body's behalf (nested coroutines resolve naturally: each body knows
  its own runner). The §2.4 marquee runs:
  `Sequence(fib).prefix(8)` → `[0, 1, 1, 2, 3, 5, 8, 13]`, lazily,
  off `while true { yield a; ... }`. Implementation: the tree-walking
  evaluator cannot suspend its own Swift stack, so a coroutine body
  runs on a **dedicated pthread under a strict baton-pass** (mutex +
  condvar; exactly one thread ever executes interpreter code — the
  interpreter stays effectively single-threaded), with an 8MB stack
  (round 45's law: frame size is the recursion budget), a
  thread-local for `yield`'s dynamic lookup, and a cancellation
  throw that unwinds a parked body when the pull side walks away
  (`.prefix(8)` of infinite fib leaks no thread). The wrapped body
  must declare no parameters and cannot be a builtin. OPEN: symmetric
  resume (values in through `yield`), and whether `async`/`await`
  ever rides this substrate (§12).
* **2026-08-31, round 53 — `async`/`await` implemented, and swiftalk
  is colorless** ("Heck, both Swift and JS has gotten them already"),
  closing §12's OPEN the day after round 52 built its substrate.
  Asked the deep question — is `async`-marking necessary? — the user
  chose **colorless**: no function is marked `async`, *any* function
  may `await` (round 52's dynamic rule, again), and the famous
  two-color split Swift and JS are stuck with never enters the
  language — `async` joins `func` and `mutating` in the graveyard of
  keywords swiftalk proved unnecessary, surviving only as spawn-site
  sugar. Also chosen: **`Task { }` spawning** per
  types-are-constructors (a new built-in `Task` type, exactly
  parallel to round 52's `Sequence(f)`; `async { ... }` is
  parse-level sugar for `Task { ... }`, and `f.Task()` falls out of
  the round-47 law), and **top-level `await`** (eval drives the
  loop — JS's own retrofit, for the same REPL reasons). Decisions
  made in implementation and logged: **spawn is eager** (JS
  semantics: the body runs to its first suspension before the
  spawner resumes); await is **unary-tight** (`await t1 + await t2`
  works); results are **memoized** and errors **rethrow at every
  await** (unawaited errors vanish); `sleep(seconds)` is the first
  suspending builtin; **deadlock is detected and thrown**, not hung;
  tasks persist parked across REPL lines and are cancelled at
  interpreter teardown. The marquee, deterministic by construction:
  two tasks logging around `sleep`s produce `[1, 2, 4, 3]`.
  Implementation: round 52's baton generalized to N contexts (main +
  tasks) under one cooperative scheduler — green threads on parked
  pthreads, a symmetric scheduling loop run by whichever context is
  parked, timers via `pthread_cond_timedwait`, and a thread-local
  "current context" that is all colorless costs. OPEN: `await`
  inside a coroutine body (the two batons don't compose yet); task
  groups/cancellation-as-API/actors; `Task` members like `.done`.
* **2026-08-31, round 54 — actors implemented: swiftalk's first
  REFERENCE type** ("Let's implement actors"), and §12 is OPEN no
  more. Asked three questions, three recommendations taken:
  **colorless calls** (`counter.inc()` from anywhere, cooperatively
  parking when busy — no `await` at actor call sites, extending round
  53's rule: serialization is a property of the running context, not
  the syntax); **reads open, writes sealed** (`a.count` reads from
  anywhere; `a.count = 1` outside the actor's own methods errors,
  including through paths like `a.list.append(x)`; inside, var/let
  still governs per round 50a); and **held to the end** — a method
  call owns the actor from entry to exit, suspensions included, so
  state cannot be interleaved mid-method: a deliberate divergence
  from Swift, whose reentrancy-at-await is a documented gotcha
  swiftalk declines. The premise stated and accepted silently: an
  actor only means something *shared*, so actors arrive as the first
  reference type, ahead of `class` (§4 amended — "value types by
  default, actors when identity-plus-concurrency matters"). The body
  grammar is a struct's verbatim (one `parseStruct(kind:)` serves
  both; rounds 46/48/49/50 machinery — memberwise/multi-dispatch
  init, implicit self, extensions — carries over wholesale), but
  instances alias, equality is identity, and mutation is in place —
  the COW write-back path stops at an actor boundary, so a
  `let`-bound actor (or one inside a `let` collection) mutates fine.
  Self-calls re-enter via a depth count; circular waits hit round
  53's deadlock detector; method errors release on the way out;
  extracted methods (`let f = a.inc`) get a serializing wrapper so
  the guarantee survives extraction. The marquee pair: two tasks
  doing read-`sleep`-write through an actor end at 2; the identical
  pattern on a bare shared `var` ends at 1 — the lost update, live in
  the test suite as the reason actors exist. Echo form
  `Counter { count: 1 }` — informative placeholder; identity never
  round-trips. OPEN: actor calls inside coroutine bodies,
  nonisolated escape hatches, `class`.
* **2026-08-31, round 55 — `class` implemented** ("Let's implement
  `class`. But do we really need it?" — answered honestly in §4, and
  implemented regardless, as asked). **Mostly no — and that's the
  design**: struct for unshared state, actor for shared; `class`
  earns its keep exactly where neither fits — object graphs values
  cannot express (cycles, shared nodes: parent pointers, linked
  structures, observers, caches) when you want *identity without
  concurrency semantics*, plus inheritance when a hierarchy genuinely
  is one. Implementation confirms round 54's musing: **class IS the
  smaller step** — one `serialized` flag on the reference-type
  machinery (false: no baton, no isolation, works inside coroutine
  bodies where actors error), plus what's genuinely new: **single
  inheritance** — `class Dog: Animal`, properties merged at
  declaration (shadowing errors), methods resolved up the chain at
  call time giving real **dynamic dispatch** (Animal's `intro` calls
  `.speak()`, gets Dog's override — "Rex says woof"), subtype-aware
  type locks (`let pet: Animal = Dog()`; the lock check walks the
  chain), and superclass extensions reaching subclasses. `super`
  calls and init inheritance are OPEN; a class inherits only from a
  class. One crash found and fixed in the same round: cyclic
  references (`a.next = b; b.next = a`) sent the recursive
  `sourceString` printer into a stack overflow — the printer now
  threads a visited set and elides re-visited references
  (`N { next: N { ... } }`); cycles are precisely what class made
  newly possible, so the printer had to learn about them the same
  day. The honest cost, in the test suite: the round-54 lost update
  returns the moment shared state is a class — classes give
  identity, actors give safety, pick on purpose.
* **2026-08-31, round 56 — `super` implemented** ("Let's implement
  `super`. But hey, is that `class` only?"). **Yes — and by
  construction, not by fiat**: `super` is the companion of
  *override*; override exists only where inheritance does;
  inheritance is class-only (§4) — actors deliberately don't inherit
  (as shipped Swift's don't), values have no hierarchy, and
  extensions can't override, so nowhere else is there a covered-up
  method to reach. Surface: `super.m(...)` and `super.init(...)`
  (declared superclass inits, multi-dispatch; none declared → guided
  error, since memberwise prefill already ran). The load-bearing
  subtlety: **resolution starts at the *declaring* class's
  superclass, never self's dynamic type** — else `C: B: A` with
  chained `super.who()` loops on a C instance. Implemented lexically:
  a hidden `@superclass` binding (the `@callee` trick) in each
  class's method-closure environment — methods, inits, and class
  *extensions* alike — bound to a nil sentinel in root classes so a
  class nested inside another class's method can't inherit the outer
  binding by accident. `self` stays dynamic inside a super-dispatched
  body (Swift semantics): Dog's `intro` calling `super.intro()` runs
  Animal's body, whose `.speak()` still finds Dog's override —
  `"[dog] Rex says woof"`. Uncalled `super.m` extracts the bound
  superclass implementation; `super.prop` errors with guidance
  (properties are never overridden); bare `super` is not a value.
  The marquee chain: `C().who()` → `"C>B>A"`.
* **2026-08-31, round 57 — computed properties implemented** ("Let's
  implement computed properties. Ahem, have we not :-?" — and the
  tease lands: **three quarters existed**). Builtins have had
  paren-less computed reads since round 40 (`.count`, `.Type`,
  `.description` all run code on read); `let m = { ... }` methods are
  getters spelled `()`; round 50's own message glimpsed the syntax
  (`var getset {}`) and round 50a logged it OPEN. The missing
  quarter, now in: **paren-less reads on user types and the setter
  half**. Surface: `var name { body }` (bare block = read-only
  getter) and `var name { get { } set { } }` (implicit `newValue` or
  `set(v)`), optional annotation checked at runtime on read and
  write; struct/class/actor bodies plus extensions — user types get
  get/set, builtins get read-only getters (`extension Int { var
  squared { self * self } }` → `12.squared`; a setter has no storage
  to reach and is refused at declaration). Setters run through the
  normal write paths, so struct COW write-back and get-modify-set
  subscript paths hold; classes inherit computed up the chain,
  override by redeclaring, and `super.prop` reaches a covered
  computed getter (found by a test failure mid-round: superDispatch
  knew methods only). The round-54 coherence bonus: an actor's
  getter/setter are the actor's *own code* — callable from outside
  and serialized like any method, so `b.dollars = 250` (computed)
  works while `b.balance = 1` (storage) stays isolated. OPEN: enums,
  builtin setters, `willSet`/`didSet`.
* **2026-08-31, round 58a — `let name(x:y:) { body }` implemented**
  ("before that, I want to make sure that argument labels goes
  straight to the variable names"). The semantic already held — since
  round 32, `{ x, y in ... }` binds its declared names directly,
  labels and all, reorderable, no `$0` unpacking — and the user chose
  to ALSO add the spelling from their example: labels attached to the
  name, no `in` header. Pure sugar: it desugars to (and echoes as)
  `{ x, y in ... }`, keeping §2.4's "`{}` is the only function form"
  true underneath. Empty labels give a variadic (round 17). The happy
  accident: the declared name is in scope when the body later runs,
  so this spelling does named recursion without `.todo` — `let
  fact(n:) { n < 2 ? 1 : n * fact(n: n - 1) }` just works. (Noted in
  passing: no `sqrt` — math builtins remain an undecided battery.)
* **2026-08-31, round 58b — `willSet`/`didSet` implemented**,
  closing round 57's last OPEN the same day it was logged. Stored
  `var` properties of struct/class/actor take an observer block —
  after the default (`var x = 0 { willSet { } didSet { } }`) or on an
  annotated default-less property; `willSet` runs before the store
  (self old, incoming value as `newValue` or a `willSet(v)` custom
  name), `didSet` after (self new, replaced value as `oldValue`/
  custom), either order, each at most once. Swift's semantics kept
  where they are load-bearing: **observers are silent during init**
  (both memberwise and declared — suppression keys claimed around the
  init body), and **didSet may reassign its own property without
  recursing** — the canonical clamp `didSet { if .x > 10 { .x = 10 } }`
  terminates via a thread-local re-entrancy guard (per-identity for
  references, per-type for structs, which have none). A struct's
  didSet writes back COW-style (it can clamp); classes inherit
  observers with their properties; an actor's observers are its own
  code, running inside the already-held method write. Two parsing
  battles won: a brace whose first word is `willSet`/`didSet` is
  never a trailing closure (so `var x = 0 { willSet { } }` parses
  while `var squares = (1...3).map { $0 * $0 }` still does), and the
  same test distinguishes observer blocks from round-57 computed
  bodies. Observers remain stored-property-only — computed
  properties put that code in their setters. OPEN: observers on
  globals/locals.
* **2026-08-31, round 59 — type inference: homogeneous-or-annotate,
  typed collection locks, and hex-float literals.** Three decisions
  in one drop. (1) **`let ary = [0, 1, 2, 3]` is `[Int]`; `[0.0, 1,
  2, 3]` is an error** — annotate `[Primitives]`, `SION`, or `Any` to
  accept it. This REVISES rounds 18/21 (heterogeneous used to infer
  `[Primitives]` silently); the two round-trip tests that embodied
  the old rule were re-annotated. `SION` (full roster, Data/Date
  included) and `Any` (everything; an `Any` binding may retype) join
  `Primitives` as annotation vocabulary — annotations are now
  structural and recursive (`[T]`, `[K: V]`, `[String: [Int?]]?`),
  and inferred locks ENFORCE element-deep: `var a = [1, 2]` rejects
  `a.append("x")` through every write path, subscripts and mutators
  included. Mixed literals as bare expressions still evaluate — only
  binding refuses to guess. (2) **`1` is explicitly Int, `1.0`
  explicitly Double — and so are `1e0` and `0x1p0`**: scientific
  notation already lexed; **hex-float literals now lex too**
  (`0x1.fep7`, `0x1.8p-1`; the p-exponent is required with a
  fraction, Swift's rule, which is what keeps `0xff.description` a
  member access — `d` and `e` are hex digits). This closes the
  round-50 OPEN: the round-37 DEBUG round trip is complete —
  `debugPrint`'s hex output re-enters, and the Date debug test
  un-trimmed. (3) **`let dict = [0: "zero", 1: "one"]` is
  `[Int: String]`** — keys and values each homogeneous or annotated;
  values are implicitly optional (round 35: nil is a right value for
  a key, and shapes no inference); a **sparse array is made of
  Dictionary, like JS and PHP** — arrays stay dense (`[1, nil]`
  needs `[Int?]`). OPEN: reifying Primitives/SION/Any as values;
  Primitives as a real switchable enum (§3c) unchanged.
* **2026-08-31, round 60 — `if let` implemented; `guard` skipped, by
  decree** ("Ahem. skip `guard` it is only `if not`. I want to reduce
  as many keywords as possible" — §9 now keeps the keyword graveyard:
  func, mutating, async-as-color, and guard; `let guard = 1` is
  legal, and a test proves it). `if let x = expr` binds non-nil into
  the then-scope — flat optionals mean the bound value IS itself, no
  unwrap layer (§3a); nil takes the else. With it, the full Swift
  condition-list surface: **comma chains** mixing bindings and
  booleans (`if x > 0, let y = f(x), y < 9`), left-to-right,
  short-circuiting, later clauses seeing earlier bindings; **`if
  var`** for a mutable binding; the **Swift 5.7 shorthand** `if let
  x { }` shadowing an optional-typed x; `else if let` composing via
  the existing else machinery. A boolean clause stays strictly Bool —
  nothing is truthy. Single-boolean conditions still parse to the
  round-36 ifS, so nothing else moved. OPEN: `while let`.
* **2026-08-31, round 61 — simplification: "swiftalk is getting too
  close to swift."** Four strokes. (1) **Multi-dispatch is bounded to
  Type inits** (§6): round 48's init multi-dispatch is now the ONLY
  multi-dispatch there will be — everything else stays
  one-name-one-body. (2) **Round 58a REVERTED**: the `let f(x:y:)
  { body }` declaration sugar is gone, two rounds after it landed —
  `let f = { x, y in body }` is again the one notation (and named
  recursion is back to `.todo`; the 58a bonus died with the sugar).
  The append-only log keeps both entries, as ever. (3) Confirmed
  standing law (rounds 10/32): labels are the parameter names,
  reorderable — `f(x:3, y:4)` ≡ `f(y:4, x:3)` — omitted labels are
  positional (`x = $0, y = $1`), and **an undefined label raises**.
  (4) NEW: **`_` is a positional-only parameter** — `{ _, x, y in }`
  is invoked `g(5, x:4, y:3)` (or all-positional): the `_` slot
  takes no label (`g(_: 5)` is a syntax error), binds no name (the
  value reaches the body as `$0` alone), and may repeat
  (`{ _, _, z in }`), while named parameters may not.
* **2026-08-31, round 62 — actor, class, and super SHELVED** ("When
  we implemented actor, we resorted to implement class. Let us shelve
  them for the time being. leave the source codes in case we need
  them later" — asked, the user confirmed BOTH reference types go).
  The round-61 simplification arc reaches the reference types: the
  round-54 actor led to the round-55 class led to the round-56
  super — a slippery slope of Swift-shaped surface, now paused
  whole. The cut is surgical: the parser no longer routes `actor`/
  `class` declarations or `super` (three fewer keywords — all three
  are plain identifiers again, `let class = 1` legal like `guard`);
  Actor.swift, the scheduler's acquire/release, inheritance,
  isolation, and the superDispatch machinery all stay in-tree,
  compiled and dormant, per the instruction to leave the source; the
  three test suites (plus the class/actor tests inside the computed
  and observer suites) are `.disabled("shelved")`, not deleted — 33
  tests skipped, ready to re-arm. §4 and §12 keep the full designs
  under SHELVED banners: shelved is not the graveyard (§9) — these
  earned their designs and may return. Until then swiftalk is values
  + coroutines + tasks: the round-53 concurrency story (colorless
  Task/await/sleep) never depended on actors and stands whole.
* **2026-08-31, round 63 — the REPL's continuation prompt is two
  spaces** ("`........` is just annoying"). The dotted continuation
  prefix is replaced by two quiet spaces — a continued line now reads
  like an indented line, so transcripts paste back INTO the REPL more
  cleanly too. Recorded alongside: the recommended indent in `.swt`
  source files is 4 spaces (the REPL's 2 is a prompt, not a style).
  README transcripts revised wholesale to match.
* **2026-08-31, round 64 — REPL history and line editing** ("Can you
  make SwiftalkCLI support history? Do you need something beyond
  Swift to implement that like readline?"). Answered: **nothing
  beyond Swift.** GNU readline is GPL and a system dependency;
  libedit is BSD but still a dependency with a module map; raw-mode
  termios needs only Darwin/Glibc, which the CLI has imported since
  milestone 1 — so SwiftalkCLI grew a ~200-line pure-Swift
  LineEditor, the linenoise approach. Features: arrow-key history
  (up/down and ^P/^N) with a draft slot, `~/.swiftalk_history`
  persistence (last 1000, consecutive dedup), emacs editing
  (^A ^E ^B ^F ^K ^U ^W, Home/End/Delete sequences), ^L clear, ^C
  cancels the whole pending multi-line statement, ^D is EOF on an
  empty line and delete-forward otherwise, UTF-8 input per scalar.
  Non-TTY input keeps plain reads — pipes and tests unchanged. Two
  termios lessons paid for in the pty test harness: restoring with
  TCSAFLUSH *discards queued input* (eating type-ahead and multi-line
  paste at line boundaries), and TCSADRAIN *blocks until the reader
  drains output* (hanging on an idle pty) — TCSANOW, which touches
  neither queue, is the correct third option. Verified end-to-end by
  driving a real pty: recall-and-edit, ^C with surviving type-ahead,
  paste across continuations, cross-session recall from the history
  file, clean ^D exit.

* **2026-08-31, round 65 — the documents reorganized** ("README.md
  and Design.md are getting crowded"). Three moves: README's Status
  section → **Status.md** (the feature-by-feature record with
  verified transcripts); Design.md's §14 "swiftalk by example" →
  **README.md** (the front page is the example page now, its one
  stale comment — round 59's inference revision — fixed in transit);
  Design.md's Dialogue log → **Dialogue.md**, this file. Design.md
  keeps the numbered sections and pointers where the moved content
  was; the log remains append-only and chronological, one entry per
  round, exactly as before — only the address changed.
* **2026-08-31, round 66 — the `eg/` examples: quines, lambda
  calculus to Z, SKI** ("I want a few examples"). Four `.swt` files,
  each verified by a new `EgTests` suite the way Status.md verifies
  transcripts. **Two quines**: `quine.swt`, the value flavor —
  `eval(source) == source` exactly, powered by `.String(.quoted)`
  being canonical (§3d): write the data literal in the escaping the
  quoter emits and the round-trip law closes the loop; and
  `quine-print.swt`, whose output is its own source byte-for-byte,
  trailing newline included. **`lambda.swt`**: Church booleans,
  numerals, pairs, Kleene's PRED, and the Z combinator with an
  anonymous factorial — the user's point made runnable: Swift cannot
  type `x(x)`, swiftalk's ONE `Function` type (§2.4) takes the
  classical terms verbatim. **`ski.swt`**: S, K, I, derived I (SKK),
  booleans, B, and the iota bird deriving all three combinators from
  one. Building the print quine exposed a gap and filled it:
  **script mode** — `swiftalk file.swt` now evaluates the whole file
  as one strict program (§2.2 file mode), echo-free, printing only
  what `print()` prints; piped stdin keeps REPL echo semantics.
* **2026-09-01, round 67 — more examples: the collection types**
  ("Sequence, Array, Dictionary"). Three `.swt` files in `eg/`, each
  pinned line-for-line in `EgTests`. `array.swt`: COW copies,
  inferred `[Int]` locks, map/filter/reduce, nested subscript paths,
  concatenation and `.Array()` — and, since no `reverse`/`contains`/
  `join`/`sort` builtin exists yet, each written in swiftalk in a
  line or a loop (bubble sort needs only subscript swaps). `dictionary.swt`:
  `[Key: Value]` with any Hashable key (`1`, `"1"`, `1.0` are three
  keys), nil as a stored value vs `.has`/`.remove`, the round-59
  sparse-array idiom, COW, pair iteration (aggregated — order is
  unspecified), a histogram. `sequence.swt`: lazy Range, a generator,
  deferred map/filter, coroutines that yield, infinite primes by
  trial division pulled by `.prefix` and `for`-`in`/`break`,
  re-iterability, Strings and Dictionaries as Sequences. One
  behavior surfaced while writing: `filter` on a Dictionary keeps
  the Dictionary while `map` returns an Array — recorded in the
  example. OPEN (noted by absence): builtin sort/contains/reverse/
  join, and `&&`/`||` — the examples spell them via ternaries.
* **2026-09-01, round 68 — the type reference: `doc/<Type>.md`**
  ("document all methods for each types"). Seventeen pages under
  `doc/`: one per builtin type (Nil, Bool, Int, Double, String, Array,
  Dictionary, Range, Function, Sequence, Data, Date, Task, Result)
  plus `struct.md` and `enum.md` for the user-type kinds, and an
  index (`doc/README.md`) carrying what every value shares — `.Type`,
  `.description`/`.debugDescription`, `.String()` and `.String(.quoted)`,
  equality — the round-47 conversion law, extensions, the
  annotation-only names, and an operator-by-type table. Every entry
  was derived from the evaluator's dispatch tables rather than from
  memory, and the non-obvious claims were verified in the REPL before
  writing (`Bool("yes")` → nil, `Int(3.9)` → 3, `1 == 1.0` a type
  error, `radix:` Int-only, `String.filter` → String and
  `Dictionary.filter` → Dictionary, `d.remove(k)` returning the
  removed value, Range patterns in `switch`). Absences are recorded
  as OPEN where a reader would look for them: no `&&`/`||`/`!`, no
  sort/contains/reverse/join, no String subscripts, no Data writes.
* **2026-09-01, round 69 — logical operators** ("Add logical
  operators to Bool. Same as Swift."). `&&`, `||`, prefix `!` — Bool
  operands only (nothing is truthy, §3b; `1 && true` is a type
  error), short-circuit on the right, and Swift's precedence: `!`
  tightest, then comparison, `&&`, `||`, the ternary loosest, with
  `??` above comparison as before. Prefix `!` and the round-51
  postfix `!` coexist by position. Two parser facts earned their
  keep: `parseComparison` treats any unknown operator as a
  comparison, so `&&`/`||` had to be excluded there explicitly; and
  the ternary now sits above a new disjunction → conjunction chain.
  A lone `&` or `|` is a syntax error — bitwise operators are
  undecided. The eg/ workarounds (`a ? b : false`) stay as written;
  they still run.
* **2026-09-01, round 70 — tuples, as a grab bag** ("Not as strict
  as Swift's typing as `(T0, T1...)`. Just `(v0,v1,...).0` and
  `.count`. Make Dictionary return `(key, value)` in for-in and
  .map"). One `Tuple` type for every arity and mix — `(1, 2).Type ==
  ("x", true, nil).Type` — elements untyped; `.0`/`.1` read, and on
  a `var` write (a value: the write rebuilds it); `.count`; equality
  element-wise, usable as a Dictionary key; source form `(1, "a")`
  round-trips, with `(x,)` for the 1-tuple so it can (`()` is empty,
  `(x)` merely groups — the comma makes the tuple, as in Python).
  Being a grab bag it conforms to Sequence: `for`-`in`, `map`,
  `.Array()`, and `Tuple(seq)`/`seq.Tuple()` gather one from
  anything. **Dictionaries now yield `(key, value)` tuples** in
  `for`-`in`, `map`, `filter` (still returning a Dictionary), and
  `reduce` — the round-41 `[key, value]` Array was a stand-in until
  tuples existed; three tests and two examples moved from `pair[1]`
  to `pair.1`. One lexer trap sprung and fixed: `t.0.1` must be two
  member accesses, not `t` then the Double `0.1` — digits directly
  after a `.` never take a fraction. A tuple literal also serves as
  an expression pattern in `switch`, by equality, for free. OPEN:
  labeled tuples, destructuring `let (a, b) = t`.
* **2026-09-01, round 71 — tuple destructuring** ("`let (a, b) =
  t`"). Bound by position with the arity checked at runtime (a
  3-tuple into two names is an error, as is a non-Tuple), `_`
  discards, patterns nest (`let ((a, b), c) = ...`), and every name
  takes its own type lock exactly as a declaration would (round-59
  inference; a nil element must be bound separately with an
  annotation; the pattern itself takes none — swiftalk has no tuple
  types to annotate with). Three companions landed with it because
  the language was visibly waiting for them: `var (a, b)`;
  **destructuring assignment** `(a, b) = (b, a + b)` — the right
  side evaluates whole before any element lands, so the swap idiom
  works and targets may be paths (`(xs[1], d["k"]) = (5, 6)`) — which
  means §2.4's round-24 fib example, `var (a, b) = (0, 1); (a, b) =
  (b, a + b)`, finally runs verbatim; and **`for (k, v) in dict`**,
  the natural sequel to round 70's `(key, value)` pairs. The REPL's
  relaxed mode distributes: `(x, y) = (1, 2)` declares both. OPEN:
  destructuring in `if let`; labeled tuples.
