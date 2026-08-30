# swiftalk — Design Notes

> a scripting language inspired by Swift, the way JavaScript was "inspired" by Java.

This document is a running log of design decisions, updated through dialogue.
Sections are marked **DECIDED**, **LEANING** (tentative direction), or **OPEN**.

## 0. Identity

**DECIDED**

* Name: **swiftalk**. Swift is to swiftalk what Java is to JavaScript:
  the syntax and flavor are inherited, but the language is its own thing —
  a *scripting* language, not a systems language.
* The name also echoes **Smalltalk** (swif-*talk*). Whether that is merely a
  pun or a semantic commitment (message passing, blocks-as-control-flow,
  everything-is-an-object) is **OPEN** — see §1.

## 1. Semantic model — DECIDED

**Dynamic Swift.** Swift's object model with the static compiler relaxed —
not a Smalltalk message-passing machine. The "talk" in the name is a pun
(though a well-earned one: Swift's argument labels are Smalltalk keyword
messages wearing parentheses).

No `method_missing` / `doesNotUnderstand:`-style trapping as a core
mechanism; dispatch is ordinary method lookup on the runtime type.

## 2. Syntax

### 2.1 Collection literals — DECIDED

* Dictionary literals are `[Key: Value]`, **not** `{Key: Value}`:

  ```swiftalk
  let langs = ["swift": 2014, "smalltalk": 1972, "javascript": 1995]
  let empty = [:]
  ```

* Array literals are `[element, ...]`; empty array is `[]`.
* Consequence (inherited from Swift's own rationale): `{ }` is **never** a
  collection literal. Braces are free to mean blocks/closures exclusively,
  which keeps trailing-closure syntax unambiguous.

### 2.2 Declarations — DECIDED

* `var` / `let` distinction as in Swift.
* **Mandatory in files, relaxed in the REPL**: a script that assigns to an
  undeclared name is an error; the interactive REPL allows bare `x = 1`
  (which implicitly declares — still type-locked per §3).

### 2.3 Calling conventions — DECIDED (core)

A deliberate divergence from Swift: **argument labels are optional
keyword arguments, and labeled arguments may be reordered.**

```swiftalk
let move = { x, y in ... }      // functions are closure literals (§2.4)
move(x: 1, y: 2)   // fine
move(y: 2, x: 1)   // also fine — labels shuffle
move(1, 2)         // fine — labels are optional (positional)
```

* Exception: **a closure as the last argument stays last** — the
  trailing-closure slot is pinned, so trailing-closure syntax stays
  unambiguous.
* (Contrast: in Swift, labels are part of the function's *name* —
  `insert(_:at:)` — and order is fixed. swiftalk labels are closer to
  Python/OCaml keyword arguments.)
* **OPEN**: consequence for overloading — if labels aren't part of the
  name, can two functions share a base name at all? (See §7, dispatch.)

### 2.4 Functions: `{}` is the *only* function — DECIDED (core)

Swift eliminated `{}` dictionaries so `{}` could mean closures.
swiftalk goes a step further: **there is no `func`. A function is a
closure literal, bound like any other value.**

```swiftalk
let add = { x, y in x + y }
add(2, 3)                       // 5
```

* **`$` is the universal placeholder**: inside a function body, `$` is
  the array of actual arguments. `$0` is shorthand for `$[0]`, `$1` for
  `$[1]`, and so on. Swift's `$0` shorthand thus stops being a special
  case — it falls out of `$` + subscript sugar.
* **Arity is `$.count`** — the number of arguments actually passed,
  available at runtime. Variadic functions come for free:

  ```swiftalk
  let sum = { $.reduce(0) { $0 + $1 } }
  sum(1, 2, 3)                  // 6; inside, $.count == 3
  ```

  (Genealogy note: `$` is to swiftalk what `@_` is to Perl — the
  arguments as a first-class list — with Swift's `$0` spelling on top.)
* Named parameters (`{ x, y in ... }`) presumably bind positionally to
  `$[0]`, `$[1]`, ... — sugar over `$`.

Further decisions:

* **Recursion — `$` is also the function itself.** Calling `$(...)`
  inside a function body recurses into the current function (cf. JS's
  late `arguments.callee`, R's `Recall`), so even an unnamed function
  can recurse:

  ```swiftalk
  let fac = { n in n < 2 ? 1 : n * $(n - 1) }
  ```

  `$.callee` was considered as an interim spelling; callable `$` is
  the chosen form. (One sigil, two askable questions: `$` = "what are
  my arguments", `$()` = "call me again".)
* **Arity is strict**: calling `{ x, y in ... }` with any argument
  count other than 2 is a **runtime error** (a scripting language;
  compile-time checking may be too hard to promise). Param-less
  `$`-style functions (`{ $.reduce(0) { $0 + $1 } }`) remain variadic —
  that's what `$.count` is for.
* **`{ }` always makes a `Function` — no exceptions.** `{ 42 }` is a
  zero-parameter function (Swift's `() -> Int`, morally); it is `42`
  when and only when it is evaluated:

  ```swiftalk
  { 42 }.Type       // Function
  { 42 }().Type     // Int
  ```

  No constant-collapsing special case — braces are never grouping.
  Deferred evaluation is thus uniform: `{ expensive() }` is a thunk,
  and trailing-closure APIs (`async { ... }`) work on anything.
* Functions are first-class values whose runtime type is **`Function`**
  (§3b) — **collectively**, like JS. Unlike Swift, where every function
  is strictly typed by its argument and return types
  (`(Int, Int) -> Int`), swiftalk's functions are all just `Function`;
  signature mismatches (arity per round 10, §3-style argument type
  locks) are **trapped at runtime**, not compile time. The
  implementation *should* catch what it can at compile time — but as a
  best-effort diagnostic, never a language guarantee.
* **Functions are also coroutines — they can `yield`.** No separate
  generator syntax (no JS `function*`): any function may `yield`, and
  yielding suspends it, to be resumed where it left off — the Lua
  model, matching the Lua-sized ambition (§5).

  ```swiftalk
  let fib = {
      var (a, b) = (0, 1)
      while true { yield a; (a, b) = (b, a + b) }
  }
  ```

  **DECIDED (round 52) — the surface is Sequence-unified**: there is
  no `Coroutine` type. `Sequence(f)` (equivalently `f.Sequence()`,
  the round-47 law; `Sequence { ... }` with a bare trailing closure
  also works) wraps a yielding `Function` into an ordinary lazy
  `Sequence` — each pull resumes the body, each `yield expr` emits an
  element (`yield` alone yields `nil` — nil is a value, §3a), and
  *returning* terminates the sequence (the return value is
  discarded). `for i in Sequence(fib)`, `.map`/`.filter`/`.prefix`,
  and `.Array()` all just work; `.Type` reports `Sequence`, nothing
  more. `yield` is out-only for now (the yield expression resumes
  with nothing); symmetric resume à la Lua can be layered on later.
  Calling a yielding function *without* the wrap is a plain call, and
  its `yield` errors — Lua's "attempt to yield from outside a
  coroutine". And `yield` is **dynamic, the Lua way** — it suspends
  the innermost *running* coroutine, not the innermost `{}`: a helper
  function called from the body may yield on its behalf (this
  supersedes round 24's "presumably lexical, like `$`" speculation).
  The wrapped body declares no parameters (nothing is passed in on
  resume) and cannot be a builtin. A coroutine `Sequence` is
  re-iterable like any Sequence value: each iteration is a fresh run
  of the body.
* **No declared params means variadic.** Strict arity (round 10)
  applies only to functions that *declare* parameters. A function with
  none accepts any number of arguments — they're all in `$`, and
  whether the body looks is the body's business. So `array.map { 0 }`
  is valid: each element arrives as `$0`, `{ 0 }` ignores it, and a
  zero-filled array of equal length comes back. Corollary in the
  stdlib: **`array.fill(0)` must be identical to `array.map { 0 }`** —
  a constant and a constant function are interchangeable ways to say
  the same thing.
* **Annotations, Swift-style**: `{ (x: Int, y: Int) -> Int in ... }`
  is allowed; bare names stay fine. Where written, types are enforced
  at runtime per §3.
* **Params are labels**: declared parameter names double as the
  optional, reorderable call-site labels of §2.3 — `add(y: 3, x: 2)`
  just works. No separate label syntax.
* **Named recursion via `.todo`** (round 44): `Function` has a
  placeholder member, and a `let` holding it accepts **exactly one**
  later assignment — deferred initialization, Swift's
  declare-then-assign `let` reborn as a value:

  ```swiftalk
  let fact: Function = .todo
  fact = { n in n < 2 ? n : n * fact(n - 1) }   // by name, not $()
  fact = { 0 }                                  // error: fact is frozen
  ```

  A `var` overwrites as many times as you want. Calling a `.todo`
  is an error; it displays as `.todo`; bare `let f = .todo` infers
  `Function`. The payoff beyond self-reference: **mutual recursion**
  (`isEven`/`isOdd`), which `$()` alone cannot express.
* **`return` exists** (round 41): `return expr` / bare `return` exit
  the enclosing function early; the last-statement value remains the
  implicit return for bodies that never `return`.
* **`$` is reassignable** (round 41, revising round 10's immutability):
  `$` is a `var` locked to `Array` — Sequence generators reassign it
  to advance their state. **`$N` are entry snapshots** of the
  arguments (refining round 32): `$N == $[N]` holds until `$` is
  reassigned; `$[N]` stays the live subscript.
* **Methods / `init` without `func` — DECIDED (round 48).** Methods
  are **`let name = { ... }` closure properties** in the type body —
  the uniform no-`func` spelling — with `self` bound at invocation
  (a `let`; mutating methods OPEN). Uncalled access yields the bound
  `Function`. Initializers are **`init { params in ... }`**: the body
  assigns `self.x = ...` with defaults prefilled; a non-optional
  annotated property left unset errors. **Initializers are
  multi-dispatch** — a deliberate carve-out from §6's
  one-name-one-function: declare several `init`s and the `Type(...)`
  call dispatches to the first declared match by arity + labels
  (runtime-type dispatch awaits closure annotations; a param-less
  `init` is variadic per round 14 — declare it last). The memberwise
  init remains the *last* dispatch candidate (a divergence from
  Swift's custom-init-removes-memberwise; flagged). A stored
  `Function` wants a `var` property — `let` + closure literal means
  method.

### 2.5 Everything else — OPEN / TODO

* Semicolons/newlines Swift-style (newline-terminated, `;` optional)? (presumably yes)
* String interpolation `\(expr)`? (presumably yes)
* Multiple trailing closures?

## 3. Type discipline — DECIDED (core), details OPEN

**Strong latent typing with type-locked bindings.** Deliberately *more*
static than the 20th-century scripting languages (Perl, PHP, Python, Ruby,
and most especially JavaScript):

* A variable's type is fixed when it is first bound:

  ```swiftalk
  var x = 1      // x is an Int, forever
  x = 2          // fine
  x = "1"        // runtime error: cannot assign String to Int variable
  ```

* There is no static type *checker*; enforcement happens at runtime.
  Every variable/constant knows its type at runtime.
* Types are runtime-queryable: `x.Type` (renamed from `x.type` in
  round 40 — cf. JS's `.constructor`, Ruby's `x.class`,
  Swift's `type(of: x)`). This is what makes iterating a sequence of
  mixed types easy — inspect `element.Type` as you go.

Details:

* Presumably annotations are allowed and enforced: `var x: Int = 1`.
* **`x.type` is first-class** (decided round 25, §10; **implemented
  round 39**): types are constructor `Function`s — `x.type == Int`
  compares identity against the very object the global `Int` binds,
  `Int("42")`-style construction calls, `.conforms(to:)` tests
  protocol conformance. (**OPEN**: whether `is` / `as?` / `as!` also
  survive as sugar.)

### 3b. Basic types — DECIDED (core)

*(Revises round 2: `Int` was to be arbitrary-precision; it is now fixed
64-bit, with bignum demoted to a possible separate `BigInt` type.)*

Primitives:

* **`nil`** — the absence value, the sole inhabitant of type **`Nil`**
  (`nil.Type == Nil`). Never again JS's `typeof null === 'object'`.
  Role model: **`nil` in swiftalk is what `undefined` is in
  JavaScript** — a first-class value denoting "no value", minus the
  type lie. `Int?` is conceptually the flat union `Int`-or-`nil`;
  full model in §3a.
* **`Bool`** — `true` / `false`. Not numbers, not truthy-anything.
* **`Int`** — **exactly 64-bit**, on every platform. NOT device
  dependent (unlike Swift, where `Int` is word-sized).
  **Overflow traps** at runtime, as in Swift — never silent wraparound.
  (**OPEN**: whether Swift's explicit wrapping family `&+ &- &*` is kept
  for those who ask.)
* **`BigInt`** — **in, but detachable.** Arbitrary precision, part of
  the language *as a whole*, yet packaged so an embedder can leave it
  out — the core implementation must stay as small as possible (§5).
  bignum-as-`Int` is acknowledged as a success in Python/Ruby/Scheme,
  but swiftalk keeps `Int` fixed and `BigInt` separate.
  (**OPEN**: literal spelling — JS-style `123n` suffix or otherwise;
  mixing rules with `Int` — presumably explicit conversion only.)
* **`Double`** — IEEE 754 binary64; what JS calls `Number`. Integers and
  floating point are **distinct types** — one numeric type for
  everything has caused zillions of tragedies (so `var x = 1; x = 1.5`
  is a type error under §3's binding lock).
* **`String`** — Swift's sense: fully Unicode, `Character` = extended
  grapheme cluster (§11). `.utf8` and `.utf32` views available
  optionally. **No `.utf16` view — UTF-16 needs to go to hell.**
* **`Data`** — a sequence of unsigned 8-bit bytes, **distinct from
  `String`**. Bytes are bytes; text is text. **Implemented round 50**:
  `Data([255, 1])` source form (hex bytes under debug; SION's base64
  spelling OPEN); `Data(str)` ≡ `str.Data()` (UTF-8, infallible);
  `data.String(.utf8)` decodes failably (`nil` on invalid bytes);
  `.count` and read-only byte subscripts; `Hashable`.
* **`Date`** — joined the roster in round 17 as a consequence of
  `Primitives`' SION-completeness (§3c); **implemented round 50**:
  seconds since the Unix epoch as a `Double` — SION's own
  representation — printing as SION's own spelling, `.Date(epoch)`
  (hex-float under debug, exactly as SION serializes). `Date()` is
  now (wall clock, Foundation-free); `Date(x)` ⇄ `Double(date)`
  convert; `Comparable`. Calendar/format output stays **OPEN**.
* **`Range`** — first-class and **lazy** (round 38): `a...b` / `a..<b`.
  Spelled `Range<I>` in the design: `I` is `Int` today, `BigInt`
  someday (unimplemented), and **never `Double`** — a deliberate
  narrowing of Swift's more versatile `Range`. Conforms to `Sequence`
  (§10); prints as its literal, so it round-trips (§3d); **not** part
  of `Primitives`/SION (§3c) — it is a language value, not an
  interchange value; `.Array()` materializes it when needed.
* **`Function`** — the **one** type of every function/closure (§2.4):
  `{ 42 }.Type == Function`, `{ 42 }().Type == Int`. Signatures are
  not part of the type (unlike Swift's `(Int, Int) -> Int` zoo);
  functions are ordinary first-class values, JS-style, with signature
  errors trapped at runtime.

Collections:

* **`Array`** — a real array (ordered, contiguous, integer-indexed from
  0, one `count`), not a pseudo-array of string keys à la JS/PHP.
* **`Dictionary`** — literal *and stringified form* are `[Key: Value]`,
  never `{Key: Value}` (§2.1); empty is `[:]`.

**OPEN**: literal inference rules (`let x: Double = 1` OK as in Swift?);
no Int8/UInt zoo, presumably — `Data` covers the bytes use case;
`Data` literals.

### 3d. Type conversion: `obj.TypeName()` — DECIDED (core)

**The type converter is a method named after the target type** —
called with parentheses, and **accepting arguments to fiddle with
formats**:

```swiftalk
data.String(.utf8)  // Data → String?  (failable: bytes may not be valid text)
data.String()       // Data → String   (infallible: source form, round-trips)
string.Data()       // String → Data   (infallible: text always has bytes)
"42".Int()          // String → Int?   (failable, presumably)
42.String()         // Int → String    ("42")
255.String(.hex)    // Int → String    ("0xff") — format via arguments
```

* Failable conversions return an Optional; infallible ones return the
  type directly.
* Arguments select formats/options per conversion — and **the enum
  form and the `radix:` form are deliberately not the same**:

  ```swiftalk
  255.String(.hex)        // "0xff"       — prefixed, literal-ready
  255.String(.oct)        // "0o377"
  255.String(.bin)        // "0b11111111"
  255.String(radix: 16)   // "ff"         — bare digits, any radix
  ```

  `.hex`/`.oct`/`.bin` emit what the lexer accepts back, and
  **prefixed strings round-trip — as a language invariant**:

  ```swiftalk
  x.String(.hex).Int()! == x      // holds for every Int x
  ```

  (likewise `.oct`/`.bin`, and for `Double` via hex-float notation —
  `.hex` on a `Double` gives `0x1.fep7`-style output that
  `.Double()` parses back exactly.)
* Presumably likewise: encodings for `Data.String()` / `String.Data()`
  (defaulting to UTF-8), date formats for `Date.String()`, etc.
* **`.String()` is mandatory** — every type must convert to `String`.
* **Argless `.String()` is *description*** (round 42): a `String` is
  simply itself — `"foo".String()` is `"foo"` — and every other type
  gives its source form. `.String()`, `String(x)`, `print`, and
  `\(...)` interpolation thus all agree (round 39's noted asymmetry
  dissolved). **Quoting is explicit: `.String(.quoted)`** quotes and
  escapes.
* **The round-trip law** (round 23, restated by round 42):

  ```swiftalk
  eval(x.String(.quoted)) == x    // for every value x, every type
  eval(x.String()) == x           // for every non-String x
  (0.1 + 0.2).String()            // "0.30000000000000004" — not "0.3"
  ```

  `Double` stringifies as the shortest decimal that parses back to
  the same bits (JS/Ryū-style); `Array`/`Dictionary` emit literal
  syntax (`[1, 2, 3]`, `["a": 1]`) with **nested Strings quoted** (a
  collection's source form must re-enter); `nil` emits `nil`. For
  `Primitives` values the quoted form *is* SION emission (§3c) — the
  native serializer and `.String(.quoted)` are one mechanism.
* Remaining flagged consequences:
  * **`Data.String()`** argument-less: source form, *infallibly*; the
    failable decode is `data.String(.utf8) → String?` (revises the
    round-6 example where bare `data.String()` decoded).
  * `Function.String()` — source text of the function (JS can;
    Lua punts)? **OPEN**.
* Symmetry with §3 (revised round 40): `.Type` *queries* — a
  property returning the constructor — and `.TypeName(...)`
  *converts* — a method. Capitalized members are type-talk; the
  constructor's `.name` (a `String`, mandatory on constructors,
  `nil` on anonymous functions) gives the name back.
* **The two spellings are one operation — by law** (round 47,
  closing round 39's OPEN): `x.TypeName(tag: ...)` is normally
  identical to `TypeName(x, tag: ...)`, format arguments included —

  ```swiftalk
  dbl.String(radix: 16) == String(dbl, radix: 16)   // always
  "42".Int()            == Int("42")
  [0, 1].Sequence { next } == Sequence([0, 1]) { next }
  ```

  Swift prefers the constructor spelling; swiftalk supports both, and
  the method spelling is favored for chaining
  (`255.String(radix: 16).count`). Constructor side: the first
  *unlabeled* argument is the subject, the rest are format arguments.
  (**OPEN**: which conversions are failable, per pair; the
  format-argument vocabulary per pair — e.g. `Int(s, radix: 16)`
  parsing, which Swift has and swiftalk does not yet.)

### 3c. `Any`, `Primitives`, and heterogeneous collections — DECIDED (direction)

* `Any` exists **for the time being**, but the language *prefers enums*
  (sum types with associated values) as the idiomatic way to express
  "one of several types" — including heterogeneous collections.
* **The language ships that enum: `Primitives`** — a built-in enum
  whose cases are `nil`, `Bool`, `Int`, `Double`, `String`, and so
  forth (one case per §3b primitive). Its very purpose is to **keep
  users away from `Any`**: when a slot must hold "one of the basic
  types", it is a `Primitives`, a closed sum you can `switch` over
  exhaustively (§7) — not the anything-goes escape hatch.

  ```swiftalk
  let mixed: [Primitives] = [1, "one", 2.0]
  for x in mixed {
      switch x {
      case .Int(let i):    print("integer \(i)")
      case .String(let s): print("string \(s)")
      case .Double(let d): print("double \(d)")
      // ... a closed set — the switch can be exhaustive
      }
  }
  ```

  *(Case spelling above is provisional; see OPEN below.)*
* **`Primitives` is a flat union** — the same model as `T?` (§3a).
  There is no box: a value in a `Primitives` slot *is* itself, and
  **`x.Type` reports `Int`, not `Primitives`**:

  ```swiftalk
  let mixed = [1, "one", 2.0]   // [Primitives]
  mixed[0].type                 // Int — the lift is invisible at runtime
  ```

  `switch`'s `case .Int(let i)` *classifies* rather than unwraps —
  `i` binds the value itself. swiftalk's two built-in unions are thus
  the same animal: `T?` is the union of `T` with `Nil`; `Primitives`
  is the union of the SION types. (User-defined enums with associated
  values remain real, boxing enums — flatness is a property of these
  built-in unions, not of `enum` in general.)
* **`Primitives` is SION-complete** — and therefore JSON-complete,
  since SION is upper-compatible with JSON.
  [SION](https://github.com/dankogai/swift-sion) is to swiftalk what
  JSON is to JavaScript: the native serialization format. The case
  roster mirrors SION's value space (indirect where needed):

  * `nil`, `Bool`, `Int` (64-bit, distinct from `Double` — exactly
    §3b), `Double`, `String`, `Data`, `Date`,
  * `Array` of `Primitives`, `Dictionary` of `Primitives` keys *and*
    values (SION allows non-`String` keys, as does swiftalk).

  A parsed SION (or JSON) document *is* a `Primitives` value, and any
  `Primitives` value serializes to SION losslessly.
* Consequence for §3b: **`Date` joins the basic-type roster** (SION
  has it natively; a serialization-complete `Primitives` needs it).
  Representation and literal syntax **OPEN** (SION spells it
  `.Date(x)` with a Unix-epoch `Double`).
* User-defined enums remain the idiom for richer unions.
* The long-term hope is that reaching for `Any` is rare; unions are
  spelled as enums, and `element.Type` / pattern matching handle the
  dispatch when iterating mixed sequences.
* **Lifting is implicit, and inference prefers `Primitives` —
  DECIDED**: a heterogeneous literal of basic types **infers
  `[Primitives]`**, auto-wrapping each element:

  ```swiftalk
  let mixed = [1, "one", 2.0]     // [Primitives] — NOT [Any]
  var a: [Any] = []               // Any exists when and only when
                                  // explicitly written
  ```

  `Any` never arises from inference; it appears in a program exactly
  where the programmer typed it. (Homogeneous literals still infer
  their element type: `[1, 2, 3]` is `[Int]`.)
* **OPEN — remaining `Primitives` details**: SION's `Ext` (MsgPack
  extension type) — mirror it or leave it to the serializer?
  `BigInt` (not in SION today)? case naming (`.Int` mirroring the
  type name vs. Swift-lowercase `.int`; the `nil` case vs. the
  keyword).

## 3a. Optionals & nil — DECIDED

**The full Optional suite survives — on a flat model.** `nil` is *not*
a member of every type; `T?`, `if let`, `guard let`, `??`, and optional
chaining `?.` all work. This is Swift's most recognizable feature and
precisely the cure for the `undefined`/`null` chaos of the scripting
tradition. But unlike Swift, **`T?` is not a wrapper**:

* **Flat union: `T?` means "a `T`, or `nil`".** There is no
  `Optional<T>` box, no `.some`/`.none`. A `2` sitting in an `Int?`
  slot is a plain `Int`:

  ```swiftalk
  var maybe: Int? = nil
  maybe = 2
  maybe.Type        // Int — not Optional<Int>
  maybe = nil
  maybe.Type        // Nil
  ```

* Consequently **optionals do not nest**: `Int??` ≡ `Int?`. There is
  exactly one absence, `nil`.
* **`nil` is the sole value of type `Nil`** — an honest `.Type`, never
  JS's `typeof null === 'object'` lie.
* **Bare `var x = nil` is an error** — there is nothing to infer; write
  `var x: Int? = nil`. (Consistent with §2.2's mandatory declarations
  and §3's type locks: `x` must know what it is.)
* Type locks and optionals compose the obvious way: `var x: Int? = 1`
  accepts `Int`s and `nil`, never a `String`.
* **Postfix `?` is unified with §8**: `expr?` unwraps the value or
  early-returns the "empty" case from the enclosing function — `nil`
  for optionals, `.failure` for `Result`s (exactly Rust's `?` on
  `Option`/`Result`). `?.` remains member-access short-circuit; `??`
  remains defaulting.
* **Postfix `!` survives**: force-unwrap, trapping on `nil` (and on
  `.failure` for `Result`s) — for when the scripter is sure.
* `x == nil` is a valid question of anything; on a binding that can
  never be `nil` it is simply `false` (a best-effort compile-time
  diagnostic may point out the tautology, per §2.4's philosophy).
* **Dictionary *reads* collapse; presence stays a distinct fact**
  *(revised round 35)*: `d[k]` is `nil` for a missing key *and* for a
  stored `nil` — but the two are semantically distinct, and
  **`d.has(k)`** tells them apart (`true` for a key holding `nil`,
  `false` for a missing key). **`d[k] = nil` does NOT delete — it
  stores `nil`**: `nil` is a right value for a key. This is a
  deliberate divergence from Swift's subscript-assignment-deletes.
  Removal is explicit — **`d.remove(k)`** (round 37): mutating,
  returning the removed value (or `nil`).

## 4. Value vs reference semantics — DECIDED

**Collections are COW values, as in Swift.** `Array`/`Dictionary`/`String`
have value semantics with copy-on-write; assignment and argument passing
copy (logically). This kills the shared-mutation aliasing bugs endemic to
Python/Ruby/JS, and COW keeps it affordable in an interpreter.

**User-defined types get the full Swift menu**: `struct` (COW value,
consistent with the built-in collections), `class` (reference, with
inheritance), plus `enum` (§7). The Swift mental model carries over
wholesale: value types by default, classes when identity matters.

**swiftalk's first reference type arrived as the `actor`, not the
`class`** (round 54, §12): state that is *shared* must be an actor —
serialized by construction; state that isn't stays a value.

**`class` — DECIDED and implemented (round 55): the open reference,
and indeed the smaller step** — an actor minus the serialization and
minus the isolation, plus **single inheritance**. `class Dog: Animal`
merges the superclass's properties (shadowing is an error), resolves
methods up the chain at call time (override = redeclare; **dynamic
dispatch**: a superclass method calling `.speak()` gets the
subclass's override), and satisfies annotations up the chain (`let
pet: Animal = Dog(...)`). No init inheritance.

**`super` — DECIDED and implemented (round 56), class-only by
construction**: `super` goes wherever *override* goes; override
exists only where inheritance does; inheritance is class-only (actors
deliberately don't inherit, values have no hierarchy, extensions
can't override — there is never a covered-up method anywhere else).
`super.m(...)` calls the implementation the override covered;
`super.init(...)` runs a *declared* superclass init on self
(multi-dispatch; with none declared it errors — memberwise prefill
already ran). Resolution starts at the **declaring** class's
superclass — a hidden lexical `@superclass` binding in each class's
method-closure chain (the `@callee` trick) — never at self's dynamic
type, so a three-level chain (`C().who()` → `"C>B>A"`) cannot loop;
and `self` stays dynamic inside the super-dispatched body, as in
Swift. Class extensions get the binding too, so their methods may use
`super`; a class nested in another class's method does NOT inherit
the outer `@superclass` (bound-to-nil sentinel). `super.prop` is a
guided error — properties are never overridden; bare `super` is not
a value.
Everything else is round 54's reference machinery verbatim: aliasing,
identity equality, in-place mutation stopping the COW write-back,
memberwise/multi-dispatch init, implicit self, extensions (one on a
superclass reaches every subclass), the `Name { prop: v }` echo —
which, now that cycles are constructible, elides re-visited
references (`N { next: N { ... } }`) instead of recursing forever.

**Computed properties — DECIDED and implemented (round 57)**, closing
round 50a's OPEN (`var getset { ... }`, glimpsed in the user's own
round-50 message). Three quarters existed already: builtins have had
paren-less computed reads since round 40 (`.count`, `.Type`), and
`let m = { ... }` methods are getters spelled with `()`. The last
quarter: **`var name { getter-body }`** (bare block = getter,
read-only) and **`var name { get { ... } set { ... } }`** (implicit
`newValue`, or `set(v)` to name it), with an optional `: Type`
annotation runtime-checked on both read and write. Reads run the
getter every time; assignment runs the setter — through the normal
write paths, so **struct value semantics hold** (the setter's
mutations write back COW-style) and get-modify-set paths
(`s.list[1] = 42` through a computed `list`) work. Scope: struct,
class, and actor bodies; `extension` on user types (get/set) and on
builtins (**read-only** — a builtin receiver is a value, there is no
storage for a setter to reach; refused at declaration). Classes
inherit computed properties up the chain, override by redeclaring,
and `super.prop` now reaches a computed implementation the override
covered. On an **actor**, getter and setter are the actor's own code:
callable from anywhere and serialized like any method — so
`b.dollars = 250` works from outside while `b.balance = 1` stays
isolated; the round-54 story holds. OPEN: computed properties on
enums; computed setters on builtins; `willSet`/`didSet` observers.

*When do you actually need it?* Rarely — and that's the design. If
state is shared across tasks: `actor`. If it isn't shared: `struct`.
`class` earns its place exactly where neither fits: **object graphs
values cannot express** — cycles and shared nodes (a tree with parent
pointers, a doubly-linked anything, an observer registry, a cache
whose entries alias) — when you want *identity without concurrency
semantics*: no baton, no isolation, callable even where no scheduler
context exists (inside a §2.4 coroutine body, where actor calls
error). And inheritance, for when a hierarchy genuinely is one. The
cost is the classic one, demonstrated in the test suite: the round-54
lost update returns the moment the shared state is a class. Classes
give identity; actors give safety; pick on purpose.

## 5. Implementation — LEANING (goal DECIDED)

* **The core implementation must be as small as possible — Lua is the
  benchmark.** Features that can be detachable are packaged detachably
  (first confirmed case: `BigInt`, §3b). The swiftalk : Swift ::
  Lua : C analogy is now explicit: a small, embeddable scripting layer.
* Reference implementation in **Swift** (the repo already carries a Swift CI
  workflow). An interpreter first; compilation strategies later.

## 6. Dispatch & overloading — DECIDED (core)

**One name, one function.** No overloading of free functions (Python/JS
style): redefining a name in the same scope is a redefinition/error, and
APIs that would be Swift overload families merge into one function via
optionals, defaults, or enum/`Any` parameters.

With §2.4 (functions are `let`-bound closure values, no `func`), this
stops being a rule and becomes a theorem: a `let` binds once, so a
second definition of the same name is just an ordinary rebinding error.
And `$`-based variadics absorb what Swift uses arity overloads for.

Clarifications (not overloading):

* *Methods* on different types may share a name — `Int` and `String` can
  both have `+` or `description`; a call dispatches on the runtime type
  of the receiver. This is ordinary method lookup, and it's how operators
  work across types.
* Default parameter values (presumably supported) cover most of what
  Swift uses arity overloads for.
* **OPEN**: user-defined operators / per-type operator definitions —
  presumably "an operator is a method on its left operand's type," but
  the exact story (and protocols like `Equatable`) is TBD (§10).

## 7. Enums & pattern matching — DECIDED (core)

**Full Swift enums**: associated values, `switch` with `case let`
destructuring, `if case`, `guard case`.

**Exhaustiveness is enforced at runtime**: a `switch` over an enum that
reaches a value no case matches (and has no `default`) is a runtime
error at that moment — not silently skipped. (A best-effort static
lint at parse/load time may come later; it is not a language guarantee.)

## 8. Error handling — DECIDED (core)

**Result-first. No exceptions.** Fallible functions return
`Result<T, E>` (or `Optional<T>` when the failure carries no
information). There is no `throw`/`do-catch` control flow — errors are
values, and the call stack never unwinds invisibly.

* **Propagation is Rust-style postfix `?`**: `let x = parse(s)?` unwraps
  the success value, or returns the failure from the enclosing function.
  It composes naturally with optional chaining `?.` and defaulting `??` —
  one family of "short-circuit on absence/failure" operators.
  **Unified with Optionals (§3a)**: the same `?` early-returns `nil`
  from an Optional, and postfix `!` force-unwraps either kind, trapping
  on `nil`/`.failure`.
* No `throw`, no `do`/`catch` keywords; handling a failure is pattern
  matching on the `Result` (`switch`, `if case .failure(let e)`).
* **OPEN**: what genuinely unrecoverable failures do (index out of
  range, type-lock violation from §3, non-exhaustive switch from §7) —
  presumably trap/abort like Swift's `fatalError`, not a catchable value.
* **OPEN — mixed error types under `?`**: if `f` returns
  `Result<T, IOError>` and `g` returns `Result<U, ParseError>`, what does
  a function using both with `?` declare as its error type? Candidates:
  Rust-style implicit conversion (an `Error` protocol every error
  conforms to, `?` upcasts to it); require a common declared supertype
  (`Result<T, Error>` and you switch on `e.type` at the catch site);
  an enum-of-errors per module, hand-rolled.

## 9. Non-goals — TODO

To be filled in. Candidates: manual memory control, `unsafe` anything,
ABI stability, Objective-C interop.

## 10. Protocols, extensions, generics — DECIDED (core)

* **Protocols, Swift-style but coarse-grained**: declaration,
  conformance, protocol-typed variables — checked at runtime (no
  static checker to do it earlier). swiftalk does **not** reproduce
  Swift's fine-grained protocol tower (no `Int: SignedInteger:
  BinaryInteger: ...` taxonomy). The roster is small and pragmatic;
  at minimum there is **`Sequence`**, and **`String`, `Array`, and
  `Dictionary` all conform** (per-`Character`, per-element, and
  per-key/value-pair, presumably — which is what `for`-`in` iterates,
  and what §2.4's coroutines can feed).
* **`Equatable`, `Hashable`, `Comparable` exist as protocols, and
  built-in types conform natively.** `Hashable` is what gates
  dictionary keys — and since SION dictionaries admit any `Primitives`
  key (§3c), every `Primitives` type hashes natively. (**OPEN**:
  exact per-type coverage — `Function` equality (identity?),
  which types are `Comparable` (`Int`/`Double`/`String`/`Date`
  surely; `Array` lexicographically?); whether user types conform by
  declaration + definition as in Swift, or get synthesis.)
* **Types are constructor `Function`s.** Like Swift, `Type()`
  constructs — and so a type is itself a first-class value of type
  `Function`: `Int.Type == Function`. This retroactively answers §3's
  "is `x.Type` first-class?": yes — `x.Type` yields the constructor,
  comparable (`x.Type == Int`), storable, callable.
* **`.conforms(to:)`** — a method on types, the runtime conformance
  test, playing roughly the role of JS's `instanceof`:

  ```swiftalk
  Array.conforms(to: Sequence)          // true
  "abc".type.conforms(to: Sequence)     // true — via the type
  ```
* **Extensions, Swift-style**: methods can be added to any type,
  including built-ins. (Yes, this is monkey-patching territory; the
  Swift discipline of `extension` blocks at least keeps it declared and
  greppable.)
* **Generics: full `<T>` syntax — *for the time being, subject to
  change*.** User functions and types may declare type parameters,
  resolved at runtime. Acknowledged as great-but-expensive; if the
  implementation cost proves too high, the fallback is "built-ins
  parameterized + types as ordinary values" (pass a `Type` argument).

## 11. Strings — DECIDED (core)

**Swift-faithful graphemes.** `Character` is an extended grapheme
cluster; `count` is user-perceived character count; correctness over
O(1) indexing.

* Encoding views: `.utf8` and `.utf32`, available optionally.
  **There is no `.utf16` view.** (Swift carries UTF-16 for
  NSString/JS/Java interop; swiftalk owes that legacy nothing.)
* Binary data is **`Data`**, not `String` (§3b) — no latin-1-ish
  "binary string" abuse.
* **OPEN**: whether to relax Swift's index-type dance
  (integer subscripts at O(n)?), regex literals.

## 12. Concurrency — `async`/`await`, colorless (round 53)

**DECIDED (round 53): swiftalk has `async`/`await` — and functions are
colorless.** Swift and JS mark declarations `async` and forbid `await`
outside them — the famous two-color split. Swiftalk does not: just as
`func` and `mutating` proved unnecessary, **`async` as a function
color is unnecessary** — *any* function may `await`, the way any
function may `yield` (round 52's dynamic rule). Asynchrony is a
property of the *running context*, not of the function.

* **`Task { ... }`** (equivalently `Task(f)` — and `f.Task()`, the
  round-47 law) spawns the body as a concurrent task and returns a
  first-class `Task` value (`.Type == Task`, identity equality like
  Function). **`async { ... }` is sugar for `Task { ... }`** — the
  word survives at the spawn site, not as a color.
* **Spawn is eager, the JS way**: the newborn runs at once, until *it*
  suspends or completes; the spawner resumes next. A task with no
  suspension point completes synchronously at the spawn.
* **`await t`** joins: returns the task's value, memoized (awaiting
  a settled task never re-runs it; every awaiter gets the value). A
  prefix at unary precedence, the JS way: `await t1 + await t2` is
  `(await t1) + (await t2)`. Awaiting a non-Task is a type error.
  **Top-level `await` is allowed** — eval drives the loop (JS
  retrofitted exactly this; a REPL without it is misery).
* **Errors are the awaiter's problem**: a task-body error settles the
  task as failed and rethrows at *every* `await` of it; a failed task
  nobody awaits takes its error to the grave. `return` from the body
  is the task's value.
* **`sleep(seconds)`** (builtin, Int or Double) suspends only the
  current context — parked tasks run meanwhile. At the top level it
  doubles as "run the loop for a while".
* **Cooperative, deterministic**: a single baton; tasks interleave
  *only* at suspension points (`await`, `sleep`) — no preemption, no
  data races, the interpreter stays single-threaded in effect. An
  `await` that can never complete (all contexts parked, no timers) is
  **detected and thrown as a deadlock error**, not hung.
* Tasks live in an `Interpreter`'s scheduler: they persist — parked —
  across a REPL's lines, and are cancelled (threads unwound) at
  interpreter teardown.

(Implementation: round 52's substrate generalized — every task is a
green thread, a real pthread parked on a condvar; `await`/`sleep`/
`Task{}` find the current context through a thread-local, which is
what colorless costs. **OPEN**: `await` inside a §2.4 coroutine body
(the two baton systems don't compose yet — it errors); structured
concurrency (task groups, cancellation as API); whether `Task` gets
members like `.done`.)

### Actors — DECIDED (round 54)

**`actor Name { ... }` — serialized mutable state, and swiftalk's
first REFERENCE type** (§4 amended: it arrived ahead of `class`).
Even round 53's cooperative world has interleaving hazards — a task
that reads-modifies-writes shared state across a suspension point can
interleave with another task (the classic lost update). Actors remove
them:

* **The body grammar is a struct's** (rounds 46/48 machinery reused):
  `var`/`let` properties with annotations and defaults, `let m = {}`
  methods with implicit self, multi-dispatch `init { }`, memberwise
  init last, `extension` works. The difference is what instances ARE.
* **References**: `let b = a` aliases; equality is identity (like
  Function); mutation is in place, visible through every name — a
  `let`-bound actor mutates fine, since the *reference* never changes.
* **Colorless calls**: `counter.inc()` reads like any call, from
  anywhere; if the actor is busy the caller cooperatively parks until
  its turn. No `await` at actor call sites — serialization, like
  asynchrony, is a property of the running context, not the syntax.
* **Isolation — reads open, writes sealed**: `a.count` reads from
  anywhere (atomic under the baton); `a.count = 1` outside the
  actor's own methods is an error ("mutated only by its own
  methods"), including through paths (`a.list.append(x)`). Inside,
  the properties' `var`/`let` still governs, round-50a style.
* **Held to the end — a deliberate divergence from Swift**: a method
  call owns the actor from entry to exit, *suspensions included* —
  the state cannot be interleaved mid-method, the guarantee people
  think actors give (Swift's reentrancy is a documented gotcha we
  decline). Self-calls re-enter freely (an ownership depth count); a
  circular wait is caught by round 53's deadlock detector and thrown,
  not hung; an error inside a method releases on the way out.
* Extracted methods keep the guarantee: `let f = a.inc; f()` runs
  through a serializing wrapper, queueing like a direct call.
* Echo form: `Counter { count: 1 }` — an informative placeholder in
  the Function family (a reference's identity can never round-trip;
  a re-entered spelling would be a *new* actor).

(**OPEN**: actor methods inside a §2.4 coroutine body (no context
there — errors, same as `await`); nonisolated escape hatches;
`class`.)

## 13. Milestones

0. **Implement `eval()`** — the core evaluator: source string in, value
   out. Everything else is a client of this. Doubles as the embedding
   API's heart (§5: swiftalk-as-Lua) and, potentially, a user-visible
   `eval()` in the language itself (**OPEN** whether to expose it, and
   how it interacts with the §5 minimal-core goal).
1. **Implement REPL** — a read–`eval`–print loop around milestone 0.
   This is where §2.2's relaxed mode (bare `x = 1` allowed) first
   matters, and where `.String()`-on-everything (§3d) pays off for
   printing results. **DONE (first cut)**: `swift run swiftalk` —
   relaxed mode on, echo in `.String()` source form (every echo obeys
   the round-trip law), multi-line continuation while brackets are
   open, prompts suppressed when stdin is not a TTY (pipe-friendly).
2. *(TBD — script runner, embedding API, stdlib growth...)*

∞. **Make swiftalk self-hosting** *(added round 43; not necessarily
   the next milestone)* — a swiftalk interpreter written in swiftalk
   itself. Distinct from milestone 0: today's `eval()` is implemented
   in Swift; self-hosting means `eval.swt` — the metacircular moment
   where the language is complete enough to describe itself. Also the
   ultimate integration test: it will demand mature strings, enums
   (the AST wants them), user-defined types, `Data`, and honest
   performance from the Swift host underneath.

**File extension — DECIDED**: `.swt` (as in `hello.swt`). Short,
reads as **sw**if**t**alk; the only notable prior claim (Adobe Flash
"Generator template") died with Flash.

## 14. swiftalk by example

A taste of the language as decided so far (§§1–11):

```swiftalk
// bindings: type-locked at first assignment (§3), Int is 64-bit (§3b)
let fact20 = (1...20).reduce(1) { $0 * $1 }   // 2432902008176640000: still fits
var n = 42
// n = "42"                                   // runtime error: n is Int
// n = 1.5                                    // runtime error: Double ≠ Int

// dictionaries are [Key: Value] (§2.1); collections are COW values (§4)
var langs = ["swift": 2014, "smalltalk": 1972]
let snapshot = langs                          // logical copy
langs["swiftalk"] = 2026                      // snapshot unaffected

// optionals, full suite on the flat model (§3a)
if let year = langs["smalltalk"] {
    print("smalltalk: \(year)")
}
let y = langs["perl6"] ?? 2015
var maybe: Int? = langs["swift"]              // Int-or-nil, no box
maybe.Type                                    // Int (or Nil when nil)

// functions are closure literals (§2.4); labels optional & reorderable (§2.3)
let move = { x, y in x + y }
move(x: 1, y: 2)
move(y: 2, x: 1)                              // same call
move(1, 2)                                    // same call
let sum = { $.reduce(0) { $0 + $1 } }         // $ = the arguments (§2.4)
sum(1, 2, 3, 4)                               // 10; $.count was 4
let fac = { n in n < 2 ? 1 : n * $(n - 1) }   // $() = recurse (§2.4)
fac(20)                                       // 2432902008176640000

// enums with associated values, runtime-exhaustive switch (§7)
enum Shape {
    case circle(r: Double)
    case rect(w: Double, h: Double)
}
let area = { s in
    switch s {
    case .circle(let r):    3.14159265358979 * r * r
    case .rect(let w, let h): w * h
    }   // a future third case reaching here without a match: runtime error
}

// Result-first errors, postfix ? to propagate (§8)
let readConfig = { path in
    let text = File.read(path)?               // failure returns early
    let json = JSON.parse(text)?              // (see §8 note on error types)
    return .success(Config(json))
}

// runtime type queries (§3) and obj.TypeName conversion (§3d)
let mixed = [1, "one", 2.0]                   // infers [Primitives] (§3c)
for x in mixed {
    print("\(x.String()): \(x.Type)")         // .String() is universal (§3d)
}
let answer = "42".Int() ?? 0                  // failable conversion + default
let hex    = 255.String(.hex)                 // "0xff"; radix: 16 for bare "ff"
let bytes  = "café".Data()                    // infallible; UTF-8 default
let text   = bytes.String(.utf8)              // String? — bytes may not be text
let src    = bytes.String()                   // source form; eval(src) == bytes
```

---

## Dialogue log

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
