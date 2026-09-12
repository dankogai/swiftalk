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

  ```swift
  let langs = ["swift": 2014, "smalltalk": 1972, "javascript": 1995]
  let empty = [:]
  ```

* Array literals are `[element, ...]`; empty array is `[]`.
* Consequence (inherited from Swift's own rationale): `{ }` is **never** a
  collection literal. Braces are free to mean blocks/closures exclusively,
  which keeps trailing-closure syntax unambiguous.

**Tuples — DECIDED (round 70): a grab bag.** `(v0, v1, ...)` is a
`Tuple` — one type for every arity and mix, **not** Swift's
`(T0, T1, ...)` typing ("not as strict as Swift's"). `.0`/`.1`
read (and, on a `var`, write) elements; `.count` is the arity; a
tuple is a value (equality, keys, round-tripping source form) and a
Sequence conformer. `(x,)` is a 1-tuple, `()` empty, `(x)` grouping.
**Dictionaries yield `(key, value)` tuples** in `for`-`in`, `map`,
`filter`, and `reduce` — replacing the `[key, value]` Array stand-in
of round 41. **Destructuring — DECIDED (round 71)**: `let (a, b) = t`
/ `var (a, b) = t` bind by position (arity checked at runtime, `_`
discards, patterns nest, each name takes its own §3 lock, no
annotation on the pattern); `(a, b) = (b, a + b)` is destructuring
*assignment* — the right side evaluates whole before any element
lands, so the swap idiom works and targets may be subscript/property
paths; `for (k, v) in dict` destructures loop elements — and, since
round 72, so does `for k, v in dict` (parentheses optional) and
`if let (a, b) = t` (nil is the only "no"; a shape mismatch is an
error). **The parentheses are optional where a comma can mean nothing
else — DECIDED (round 99)**: `let a, b = t` / `var a, b = t` (as `for
k, v in d` since round 72, and `{ k, v in }` always) and, in a switch,
`case let w, h = .rect:` — the `let` is what makes the comma a list.
Not in `if`/`while`, whose comma is the condition list (`if let a, b =
t` stays two conditions), not in assignment (`a, b = b, a` would need
bare tuple expressions — OPEN), and not with labels (`let x: a, y: b`
would read as annotations; label patterns keep their parentheses). **A tuple is a rigid Array of arguments (round 73, revising
72's narrower splat)**: a sole Tuple argument IS the argument list —
`$` holds its elements, so in `d.map { }` `$0` is k and `$1` is v,
and declared parameters bind to them with arity checked against
them (`{ t in }` given a 2-tuple is an error; wrap as `((1, 2),)` to
pass a tuple whole). Builtins are exempt (`print((1, 2))` prints the
tuple). **`.enumerated()`** (round 73) yields index/element tuples —
lazily on a Sequence value, as an Array on the eager conformers —
labeled `(key:, value:)` since **round 128** ("Change
`.enumerated()`'s tuple tags from `(offset:element)` to
`(key:value:)`"), a divergence from Swift's `offset:`/`element:`
taken so that a Dictionary's pairs and an enumerated Array's are one
shape: a function written over `p.key`/`p.value` serves both, and an
Array is, after all, the Dictionary whose keys are `0..<count`. The
converse closed in **round 129** ("`dict.enumerated()` should return
a stream of `(key,value)` rather than `(key, (key,value))`… just a
no-op, returning just itself"): a Dictionary's `enumerated()` is the
Dictionary — its pairs are `(key:, value:)` already, and numbering
them would nest a pair inside a pair, which no caller wants. So
`enumerated()` means "the pairs, keyed" on every conformer: by
position where there are no keys, by the keys where there are. **Labels — DECIDED (round 74)**: `(x: 1, y: 2)` with
`.x`/`.y` (and `.0`/`.1` still) — labels *name positions*, so they
are cosmetic: equality, hashing, destructuring, and the splat ignore
them; source form keeps them; `(x: 1)` is a 1-tuple. Dictionary pairs
are `(key:, value:)`, and enumerated too (round 128). **Labeled
destructuring — DECIDED (round 75)**: `let (x: a, y: b) = t` binds by
label (patterns reorder freely), an unlabeled element by position,
arity rigid, a missing label an error — in `let`/`var`, `if let`,
`for`, and destructuring assignment alike.

### 2.2 Declarations — DECIDED

* `var` / `let` distinction as in Swift.
* **Mandatory in files, relaxed in the REPL**: a script that assigns to an
  undeclared name is an error; the interactive REPL allows bare `x = 1`
  (which implicitly declares — still type-locked per §3).

### 2.3 Calling conventions — DECIDED (core)

A deliberate divergence from Swift: **argument labels are optional
keyword arguments, and labeled arguments may be reordered.**

```swift
let move = { x, y in ... }      // functions are closure literals (§2.4)
move(x: 1, y: 2)   // fine
move(y: 2, x: 1)   // also fine — labels shuffle
move(1, 2)         // fine — labels are optional (positional)
```

* Exception: **a closure as the last argument stays last** — the
  trailing-closure slot is pinned, so trailing-closure syntax stays
  unambiguous.
* **A tuple is a rigid Array of arguments** (round 73, revising round
  72's splat): a sole Tuple argument IS the argument list — `$` = its
  elements, whether or not parameters are declared. Swift once had a
  narrower form (SE-0029 removed it); swiftalk's is broader and
  simpler because a Tuple is a grab bag, not a type.
* (Contrast: in Swift, labels are part of the function's *name* —
  `insert(_:at:)` — and order is fixed. swiftalk labels are closer to
  Python/OCaml keyword arguments.)
* **OPEN**: consequence for overloading — if labels aren't part of the
  name, can two functions share a base name at all? (See §7, dispatch.)

### 2.4 Functions: `{}` is the *only* function — DECIDED (core)

Swift eliminated `{}` dictionaries so `{}` could mean closures.
swiftalk goes a step further: **there is no `func`. A function is a
closure literal, bound like any other value.**

```swift
let add = { x, y in x + y }
add(2, 3)                       // 5
```

* **`$` is the universal placeholder**: inside a function body, `$` is
  the array of actual arguments. `$0` is shorthand for `$[0]`, `$1` for
  `$[1]`, and so on. Swift's `$0` shorthand thus stops being a special
  case — it falls out of `$` + subscript sugar.
* **Arity is `$.count`** — the number of arguments actually passed,
  available at runtime. Variadic functions come for free:

  ```swift
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

  ```swift
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

  ```swift
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

  ```swift
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
* **One declaration notation — `let f = { x, y in body }` (round 61,
  REVERTING round 58a's `let f(x:y:) { body }` sugar)**: "swiftalk is
  getting too close to Swift; let's simplify." The declared names are
  the labels and the bindings at once: `f(x: 3, y: 4)` ≡
  `f(y: 4, x: 3)` ≡ `f(3, 4)` — omitted labels are positional
  (`x = $0, y = $1`), mixed calls fill remaining slots in order, and
  an **undefined label raises**. **`_` is a positional-only
  parameter**: `{ _, x, y in }` is invoked `g(5, x: 4, y: 3)` — the
  `_` slot takes no label (`g(_: 5)` is a syntax error), binds no
  name (the value reaches the body as `$0` alone), and may repeat.
  (Named recursion is back to `.todo`, round 44 — the 58a bonus died
  with the sugar.)
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

  ```swift
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
  Swift's custom-init-removes-memberwise; flagged). **Round 150**
  ("Add `init(arg:abs)` to `Complex`") tested this rule and kept it: a
  same-arity labeled alternative — `Complex(abs:arg:)` beside
  `Complex(1.0, 2.0)` — is had by declaring the primary init first
  (`init { real, imag in }`) and the alternative after, since the
  first match wins and labels that name only the second reach it. A
  rule tried and taken back the same round: "a positional call of
  the properties' arity is memberwise" — it would have made
  `Rational(3, 4)` skip its normalizing init, which is the whole
  point of a declared init of that shape. Declaration order is the
  disambiguator, and no rule beats it. A stored
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

  ```swift
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
  (A bare *variable* as a condition asks the question its value
  answers — a Bool its value, anything else "not nil"; round 80, §7.)
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
  `.Data("base64")` source form since round 97 — SION's own (hex bytes
  under debug); `Data(base64)` ≡ `base64.Data()` (failable); the text's
  bytes are `str.Data(.utf8)` (infallible);
  `data.String(.utf8)` decodes failably (`nil` on invalid bytes);
  `.count` and read-only byte subscripts; `Hashable`.
* **`Byte`** — **round 116**: Data's element type, Swift's `UInt8`, and
  the user's decision on how it meets `Int`: *interoperate* — "a
  Byte is an Int that fits a byte": `Byte op Byte` a Byte (trapping),
  `Byte op Int` an Int, comparison and equality by value (`Byte(33)
  == 33`, hashing to match), while type locks keep them apart
  (`x.Type == Byte`; no Byte lands in an Int slot). Chosen over
  Swift's strict `UInt8`, which relies on literal inference swiftalk
  does not have — a strict Byte would have broken `d.filter { $0 >
  127 }` the day after round 115 made Data a Sequence. `Byte.min`/
  `max`/`bitWidth`/`zero`/`isSigned`; the bitwise methods on a Byte
  give a Byte, masked; `Data.random(n)` beside the other randoms. A
  bare Byte is not SION (no spelling); JSON and plists write it as a
  number.
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

```swift
data.String(.utf8)  // Data → String?  (failable: bytes may not be valid text)
data.String()       // Data → String   (infallible: source form, round-trips)
string.Data(.utf8)  // String → Data   (infallible: text always has bytes; bare Data(s) is base64, round 97)
"42".Int()          // String → Int?   (failable, presumably)
42.String()         // Int → String    ("42")
255.String(.hex)    // Int → String    ("0xff") — format via arguments
```

* Failable conversions return an Optional; infallible ones return the
  type directly.
* Arguments select formats/options per conversion — and **the enum
  form and the `radix:` form are deliberately not the same**:

  ```swift
  255.String(.hex)        // "0xff"       — prefixed, literal-ready
  255.String(.oct)        // "0o377"        — "+0o377" under .sign (round 125)
  255.String(.bin)        // "0b11111111"
  255.String(radix: 16)   // "ff"         — bare digits, any radix
  ```

  `.hex`/`.oct`/`.bin` emit what the lexer accepts back, and
  **prefixed strings round-trip — as a language invariant**:

  ```swift
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

  ```swift
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

  ```swift
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
  **Round 151** ("Add Rational.Double()") found the law stopping at
  the builtins: `Rational(3, 4).Double()` ran the module's `let
  Double` member, `Double(Rational(3, 4))` was "cannot convert
  Rational to Double". Now a struct or enum that declares `let T = {
  ... }` answers `T(x, formats...)` with that member bound over `x`,
  formats as its arguments — the two spellings are one operation for
  user types too. Inside such a member `.description` is the builtin
  text; `String(self)` would be the member again. (Round 152: the
  `String` member's reach — print, interpolation, containers — is
  under `.pretty`'s paragraph in §3d.)

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

  ```swift
  let mixed: [Primitives] = [1, "one", 2.0]
  for x in mixed {
      switch x {
      case let i = .Int:    print("integer \(i)")
      case let s = .String: print("string \(s)")
      case let d = .Double: print("double \(d)")
      // ... a closed set — the switch can be exhaustive
      }
  }
  ```

  *(Case spelling above is provisional; see OPEN below.)*
* **`Primitives` is a flat union** — the same model as `T?` (§3a).
  There is no box: a value in a `Primitives` slot *is* itself, and
  **`x.Type` reports `Int`, not `Primitives`**:

  ```swift
  let mixed = [1, "one", 2.0]   // [Primitives]
  mixed[0].type                 // Int — the lift is invisible at runtime
  ```

  `switch`'s `case let i = .Int` *classifies* rather than unwraps —
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
* **Inference is homogeneous-or-annotate — REVISED (round 59,
  revising round 18/21's implicit `[Primitives]` inference)**: a
  homogeneous literal infers its element type — `let ary = [0, 1, 2,
  3]` is `[Int]`, `[0: "zero", 1: "one"]` is `[Int: String]`
  (recursively: `[[1, 2], [3]]` is `[[Int]]`). A heterogeneous
  literal is an **error at binding** — `let bad = [0.0, 1, 2, 3]`
  does not infer; you must say what you mean:

  ```swift
  let ok: [Primitives] = [0.0, 1, 2, 3]   // the closed SION-ish sum
  let s: SION = [1, "one", Data([255])]   // full SION roster, Data/Date included
  var a: Any = [0.0, 1, {}]               // the escape hatch, spelled out
  ```

  The annotation vocabulary (round 59): **`Primitives`** admits the
  scalar roster plus Arrays/Dictionaries thereof; **`SION`** is
  Primitives plus `Data` and `Date` (the full serialization roster);
  **`Any`** admits everything — and an `Any` binding may retype
  (`var a: Any = 1; a = "s"` holds; the §3 lock is `Any`). All three
  are annotation vocabulary only for now — not values (OPEN: reify).
  `Any` still never arises from inference. Mixed literals as bare
  *expressions* still evaluate — dynamism intact; only inference
  refuses to guess. Inferred locks **enforce**: `var a = [1, 2]`
  rejects `a.append("x")`, element-deep. Dictionary values are
  implicitly optional per round 35 (nil stores fine and shapes no
  inference); arrays are dense — nil elements need `[Int?]`, and a
  **sparse array is a Dictionary**, like JS and PHP. Annotations are
  now structural and recursive: `[T]`, `[K: V]`, `[String: [Int?]]?`.
* **OPEN — remaining `Primitives` details**: SION's `Ext` (MsgPack
  extension type) — mirror it or leave it to the serializer?
  `BigInt` (not in SION today)? case naming (`.Int` mirroring the
  type name vs. Swift-lowercase `.int`; the `nil` case vs. the
  keyword).

**Logical operators — DECIDED (round 69)**: `&&`, `||`, and prefix
`!`, exactly Swift's — Bool operands only (nothing is truthy),
short-circuit on the right, precedence `!` > comparison > `&&` >
`||` > ternary, with `??` above comparison. Prefix `!` and postfix
`!` (force unwrap) coexist; position tells them apart. A lone `&` or
`|` is a syntax error — bitwise operators are undecided. *(Round 135:
a lone `&`, `|`, or `^` is a Set operator now, a type error elsewhere
— bitwise stayed methods, per round 105, so the symbols were free.)*

**Prefix `+`, a signed `.hex`, and `===` / `!==` — DECIDED (round 121)**
("Looks like prefix `+` to Int and Double are missing. I got a syntax
error for `+1.0`. Implement it. Also explicitly prefix `+` for
positive values when `.String(.hex)`. Also implement `===` and `!==`
where `+0 !== -0` and `nan === nan`"). Prefix `+` is Swift's: the
number itself, on Int, Double, and Byte, a type error elsewhere; after
an operand, `a +1` stays binary. `.String(.hex)` wrote the sign both
ways from this round, `.oct`/`.bin` from **round 124** — **revised in
round 125** ("Let's add `String(.sign)` instead. With that positive
values are prefixed with `+`. Without it it is omitted. And
`.debugDescription` for Int and Double are defined as `.String(.sign,
.hex)`"): the always-on sign was a format's business made the reader's,
so it is a modifier now, the second after `.pretty`. `.sign` rides
beside any number format — none (`"+42"`), `.hex`/`.oct`/`.bin`,
`radix:` — and writes the `+` a positive number otherwise omits; a
negative is `-` either way; `nan` alone has no sign, `+inf` does. The
formats are unsigned again, as rounds 20–21 had them. What keeps the
sign always is the **debug form**: `debugDescription` for Int and
Double is `.String(.sign, .hex)` — `+0xff`, `+0x1.8p0`, `-0x0p0` beside
`+0x0p0` — through collections and Ranges; a Data's bytes and a
Date's epoch stay in SION's own unsigned spelling. `===` and `!==` are JS's
`Object.is`, not Swift's reference identity (which the shelved
classes give under `==` already): the same type and the same value bit
for bit — `Double.nan === Double.nan`, `+0.0 !== -0.0`, `1 !== 1.0`,
`Byte(1) !== 1` — recursive through containers, keys included, and
never a type error: values of different types are simply not the same
value, where `==` asks a question with no answer. Same precedence as
`==`, unchained, continuing a line. **Round 140** ("Give the *true*
`===` and `!==` operators to String as well"): Strings had fallen to
`==`, which is Swift's canonical equivalence, so `"た\u{3099}ん" ===
"だん"` said true; `===` now compares scalar for scalar, through
containers and keys as the rest does — the same-bits rule the Doubles
already had, and the reason `isNormalized` compares scalars too.

**`eval()` in the language — DECIDED (round 122)** ("Toplevel `eval()`
in Swiftalk is missing. It is DIFFERENT from Swift's interpreter").
Milestone 0's evaluator, exposed: `eval(source)` takes a String, runs
it as a program, and returns its last statement's value. Swift has no
such thing — it is a recorded divergence, JavaScript's, and the law
§3d had been stating since round 21 (`eval(x.String()) == x`) is now
a sentence the language can say about itself. Where it runs was the
one decision: **at the program's top level**, the file's scope — it
sees every top-level name and type, its declarations land there as a
line typed at the REPL would, and a caller's locals are invisible to
it (JavaScript's indirect eval, not its direct one — a closure's
environment is not something a string should reach into). Errors are
the ordinary ones, thrown; `break`/`return` in evaluated source are
the syntax errors they are at the top. A Function value, so `map(eval)`
works. **Round 123** ("Also add `eval` to the module's own top
level"): a module's `eval` runs at the module's top level, and the
mechanism is lexical rather than dynamic — `eval` is not a builtin
but a `let` installed in every file scope, closing over that scope,
so it resolves through the closure chain like any name. A function a
module exports therefore evaluates in the module it came from,
seeing its unexported names and never the importer's; the program's
`eval` is the program's. No caller-tracking, no stack, no cost on the
call path; what a file's top level means is settled by where the
text was written.

**`??` and `!!` — DECIDED (round 130)** ("Let's implement `??` and
`??=` on Dictionary. Also `!!` and `!!=`. `(d0 !! d1) == (d1 ?? d0)`").
Round 126's `merge` without a function overwrote, and the user wanted
the other direction with an operator; `+=` was rejected as
dishonest — it is lossless on Arrays and would be lossy here — and
`!!=` proposed as `??=`'s shouting sibling. So: **`??` on two
Dictionaries is per key**, `d0[k] ?? d1[k]` over the keys of both —
`d0`'s values kept, the missing filled from `d1`, a stored `nil`
counting as absent exactly as `d[k] ??= v` has treated it since
round 103 — which makes the right side evaluated where a Dictionary
on the left had made it a tautology. **`!!` is defined by the user's
own equation, on every value**: `a !! b` is `b ?? a` — the right
side's value when it has one, both sides evaluated, left first — so
on Dictionaries `d1` overrides and a `nil` in `d1` does not, and on
scalars `x !!= y` is "update if provided". `merge` without a function
stays the lossier cousin, writing `nil`s too. One lexing rule, the
fourth spacing-sensitive one: `!!` is infix only after an operand
with whitespace before it, so `x!!` is still two force-unwraps and
`!!b` two nots. Same level as `??`, right-associative, continuing a
line.

**`Set` — DECIDED (round 132)** ("Let's implement Set. We already have
Dictionary and Array but unlike Array, Set is unordered so
`dict0.keys()` may not equal `dict1.keys()` even if `dict0 ==
dict1`"). Swift's, the third collection: unordered, unique, any value
an element since every value is Hashable, a COW value like the other
two. **No literal** — Swift has none, and `[...]` is spoken for — so
`Set([...])` constructs from any finite Sequence and the constructor
*is* the source form, elements sorted by their source form, which
makes two equal Sets print alike and keeps the round-trip law —
written `Set(1, 2)` since **round 134** ("`set.String()` should yield
`Set(elem0, elem1, ...)`, not `Set([elem0, elem1, ...])`"), the
variadic form round 133 added, with one guard for the law: a
one-element Set whose element is a Sequence prints `Set([x])`, since
`Set(x)` would spread it. **The annotation is
Swift's generic spelling**, `Set<Int>`, parsed for any name (`[T]`
and `[K: V]` stay Array's and Dictionary's); inference and locks
treat the element as an Array's. Members are Swift's names: `insert`
(a Bool, new or not) and `remove` mutate on a `var` path like
`append`; `union`/`intersection`/`subtracting`/`symmetricDifference`
and the five `is…` predicates take a Set or any Sequence; `filter`
gives a Set and `map` an Array, as Swift's do; a slice or
`enumerated()` is an Array, an order having been imposed; no
subscript. **`d.keys` is a Set** — the user's own motivation — revising
round 127's Array: `d0 == d1` now implies `d0.keys == d1.keys`;
`values` stays an Array. A Set is not a SION value (no literal) and
writes to JSON and property lists as a sorted array, lossy as Data's
base64 is. OPEN: a Set in SION (`first`/`min`/`max` came in round
139, on every Sequence). **Round 133**
("Unlike Dictionary, Set is 'keys only'"): so `merge` takes no
function — nothing collides — and `??`/`!!` get no Set meaning of
their own, "keep mine" and "take theirs" being the same union; the
operators were **`+` for union and `-` for subtraction** (round 136
removed `+`: "`|` is enough" — one spelling, and `+` had read as
concatenation everywhere else), both sides Sets, `-=` following by
round 104's rule, with `merge` and
`delete` as their in-place methods (a Set or any Sequence on the
right). `delete` reached Dictionary too, by the user's spelling
`d0.delete(d1)`: the listed keys removed. **Round 135** ("More
operators to Set: `s.union(t) == s | t`, `s.intersection(t) == s &
t`, `s.subtracting(t) == s - t` — rename `.delete()` to `.subtract()`
as well — `s.symmetricDifference(t) == s ^ t`") spelled Swift's
SetAlgebra as operators: `|`, `&`, `^` beside `+` and `-`, at Swift's
levels (`&` with `*`, `|` and `^` with `+`), `|=` `&=` `^=` by round
104's rule, and a type error off Sets — the three symbols had stayed
free precisely because round 105 made bitwise operations methods.
`delete` became `subtract`, Swift's mutating name, on Dictionary too.
Compound assignment now carries its operator as a String, the doubled
and single forms no longer sharing a character. And `Set(a, b, ...)` lists
its elements when given two or more, and a single non-Sequence is
the singleton (`Set(3)`); a single Sequence stays Swift's
`Set(sequence)`, so `Set("one")` is graphemes and `Set(["one"])` the
singleton — the one edge, recorded, not hidden.

**Unicode normalization, `escaped`/`unescaped` — DECIDED (round 137)**
("implement Unicode normalization on String. NFC, NFD, NFKC and NFKD.
Swift Foundation's `precomposedStringWithCanonicalMapping` and friends
are too cumbersome. `.normalize(with: .nfc)`, maybe? Also implement
`.escaped()` which escapes non-ASCII range codepoints… `.unescaped()`
does the opposite"). One method, four forms, the `with:` label
optional as Swift's labels are — **`normalized`, from round 138**
("rename `.normalize()` to `.normalized()` since it does not mutate.
Swift's naming conventions apply"), Swift's rule that a non-mutating
method is the past participle (`sorted`, `reversed`), with
**`isNormalized(.nfc)`** beside it answering whether normalizing would
change anything. **Foundation-free, by tables**: the
standard library keeps its normalizer private and exposes only the
combining class, so the core carries the UCD's decomposition mappings
(Unicode 17.0: 2,081 canonical, 3,833 compatibility, the
Full_Composition_Exclusion ranges) as text parsed on first use — some
77 KB of generated source, `Tools/gen-unicode-tables.py` regenerating
it from the UCD — with Hangul by algorithm and canonical ordering and
composition per UAX #15. Verified against Foundation in the test
target, and against the UCD's own `NormalizationTest.txt` (18,000
lines, Parts 0–3) when the file is supplied. The alternative — an
embedder-supplied normalizer, as `moduleLoader` supplies URL fetching
— was rejected: a String method that works only when something is
installed is not a String method. **`escaped()`** writes every
non-ASCII scalar as `\u{hex}` and doubles a backslash, leaving the rest
of ASCII as it is (a newline stays a newline), so the text is a string
literal's body; **`unescaped()`** reads a literal's escapes back,
`\u{}` and the seven short ones, and refuses anything else rather than
guessing.

**`first`, `min()`, `max()` — DECIDED (round 139)** ("Let's implement
Sequences' `first`, `min`, and `max`. No reason to limit it to Set.
`min` and `max` applies only when its elements are Comparable. Error
if not"). Swift's three, on every conformer through the one
`iterator(of:)`: `first` a property (Swift's), one pull, so an
infinite Sequence answers and a Set's or Dictionary's first is in its
own order; `min()`/`max()` methods (Swift's), drained so finite only,
`nil` when empty, and bare they let `<` decide — Int, Double, String,
Date, Byte compare, and anything else is `<`'s type error, as the
user asked and as `sorted()` has done since round 83. With a Function
they take Swift's areInIncreasingOrder, `by:` optional as the labels
are; `min` keeps the first of equals and `max` the last, as Swift's
do. Not added: `last` — O(n) on a lazy Sequence and undefined on an
infinite one — OPEN.

**`**` — DECIDED (round 142)** ("Implement `**` operator for Int and
Double. `base ** ex` meaning `base powered by ex`, of course"). A
symbol spent, but on the one arithmetic operation the keyboard's
four cannot spell, and the one Swift users miss most (Swift has
`pow` and no operator). Right-associative and above `*`, as Python's
and JavaScript's: `2 ** 3 ** 2` is 512, `2 * 3 ** 2` is 18. The
prefix question is settled Python's way — `-2 ** 2` is `-(2 ** 2)` —
because the prefix operators already bind looser than the postfix
ones and `**` sits between; the right side takes a sign freely, `2.0
** -1.0`. Types follow §3's rule for every arithmetic operator: two
Ints give an Int, by square-and-multiply, trapping on overflow as `*`
does, a negative Int exponent a type error since there is no Int
answer; two Doubles give libm's `pow`; a mix is a type error. `**=`
by round 104's rule.

**Static members and `Self` — DECIDED (round 143)** (the user, meeting
"an extension body holds 'let' methods and 'var' computed
properties": "Then how do we extend static properties?"). Until now a
type value was a Function with nothing behind it but a name, and the
only statics were the builtin hooks of rounds 108–116. Now a struct
or enum body, and an extension of one or of a builtin, may say
**`static let name = value`** — any value; a Function is a static
method, so `Point.plus(a, b)` calls and `Point.plus` is the Function
— and **`static var name { getter }`**, a computed property of the
type, read on each access. They live on the type object (a hidden
`@ext:T:static:` binding for a builtin, the scheme extension methods
use) in their own namespace, so `Point.origin` and `p.origin` do not
collide, and an enum's statics may not take a case's name. **`Self`**
is bound in the type's scope for the body and every extension:
`Self(x: 0, y: 0)`, `Self.origin`, and an instance method's `Self(...)`
all read as in Swift; `static` and `Self` are contextual, not
keywords. Left out on purpose: a stored `static var` (a global by
another name) and a setter on a static var. `:r extension` overwrites
statics as it does methods. One implementation note worth its line:
a `static let` may read an earlier static (`static let zero =
Self.origin`), which means the type's table must not be under a write
while initializers run — the first draft was, and Swift's exclusivity
check caught it.

**Operators are Functions — DECIDED (round 144)** ("Like Swift,
operators are functions. `(+)(2,4) == 6`, `(*)(2,4)==8` and
`(**)(2,4)==16`"). Swift's spelling, `(op)`, and Swift's meaning: the
parenthesized operator is the very Function the infix form applies —
one FunctionObject per operator, made on first use and kept, so `(+)
== (+)` holds by the identity rule Functions have always had, and
`(+).String()` is `"(+)"`, which re-enters. Two arguments apply the
binary operator with its own type rules (`(+)(1, 2.0)` is the infix
form's type error); one argument is the prefix form for `-`, `+`,
`!`. Every binary operator qualifies — arithmetic, `**`, the eight
comparisons, the Bool three, `??`/`!!` (per key on Dictionaries),
the Set three — except the assignments and `...`/`..<`, which are not
functions of two values. The short-circuiting ones cannot, both
arguments having been evaluated by the call; that is what a function
is. **Swift's bare form** — `reduce(0, +)` without parentheses — came
in **round 145** ("Implement the bare form too"), and narrower than
the fear: not a primary expression anywhere, but a *call argument*
that is nothing but an operator token — the token after it is `,` or
`)` — so `reduce(0, +)`, `sorted(by: <)`, `map(-)`, `f(**, 2, 3)`
read, while `(1 + 2)` and `f(-1)` are what they were. One corner is
the regex rule's: `/` before `,` opens a literal (`split(/,/)` is a
regex of a comma, and must stay one), so `f(/, x)` is spelled `f((/),
x)`; before `)` it is the operator.

**Operators on structs and enums — DECIDED (round 146)** ("Swift has
one of the most elaborate system to implement that but Swiftalk will
go lighter. Will not tweak precedence (yet); existing operators only
(yet); … we simply say `prefix(-)`, `postfix(-)` and `infix(-)`.
They are always static so you don't have to say so … `infix(*) =
{ lhs, rhs in ... }`"). The user's spelling, exactly: a member of a
struct, an enum, or an extension of one, `fixity(op) = closure`,
with no `static` and no `func` — an operator is the type's by
definition. Existing operators at their existing precedence: infix
`+ - * / % ** == != < <= > >= | & ^`, prefix `- + !`, postfix `! ?`;
not the short-circuiting `&& || ^^`, not `?? !!` (a struct is never
absent), not `=== !==` (identity is not a question a type answers),
and not on builtin types (`extension Int { infix(+) }` is refused —
Int keeps its `+`). **Dispatch is by operand, inside the same
functions every spelling already calls** — `binary`, `compare`,
`power`, the prefix and postfix evaluations — so `a * b`, `a *= b`,
`(*)(a, b)`, `reduce(z, *)`, and `sorted()` reach a type's operator
without knowing it exists; the first operand whose type implements
the operator answers, so `2 * z` and `z * 2` both reach `Complex`'s
`*` and the closure dispatches on `$0.Type` as the language always
has. **Derivation, Swift's**: a comparison must return a Bool; `!=`
comes from `==`, and `>`, `<=`, `>=` from `<`, so one `<` makes a type
Comparable — `sorted()`, `min()`, `max()`, and `.conforms(to:
Comparable)` follow. OPEN, as the user said: new operators, and
precedence.

**`modules/Complex.swt` — DECIDED (round 147)** ("Let's implement
`Complex` as a module. We should now have all the basis to do so
*within* swiftalk … cover C++ functionalities … add `var i {
Self(-.imag, .real) }` so you can go `Double.pi.i`"). The first
library written in the language, and the test of rounds 143–146
together: a struct with `infix(+ - * / ** ==)` and `prefix(- +)`,
either side a scalar (the closure lifts Int and Double through
`$0.Type`), `abs`/`arg`/`norm`/`conj`/`proj`/`i` as properties and
the whole of `<complex>`'s free functions as statics, `Complex.exp(z)`
the way `Double.exp(x)` reads. Two decisions came out of writing it.
**An extension of a builtin type is program-wide** — the module's
`extension Double { var i }` had landed in the module's own scope,
invisible to the importer, while a struct's extension was already
global by mutating the type object; now the hidden `@ext:` bindings
live in the root scope, which is Swift's rule (an extension is
visible wherever its module is) and the only one under which
`Double.pi.i` can mean anything. **The inverse functions follow C99
Annex G**, computed as CPython's `cmath` computes them — `asin`
through `asinh`, `atan` through `atanh`, with sign-preserving
rotations — because the textbook formulas put `asin(2 + 0i)` on the
wrong side of the cut; the module agrees with `cmath` on 304 points
including the cuts. Doubles only, as `std::complex<double>`; no
`<iostream>`, no order (`<` is not defined on Complex, as in C++).

**`import from` — DECIDED (round 148)** (the user, having typed `import
Complex from "modules/Complex.swt"` and got "cannot call a Tuple":
"WHY? … implement a simple `import from where` without `import
(what)`"). Round 100's two forms left a trap: `import Complex from`
is the namespace form, so a module named after its one export gives
`Complex.Complex`. The third form is the plain one — `import from
"..."`, every export bound by its own name, JavaScript's `import *`
and Python's `from m import *` without a star to spell — and it is
what the sentence "import Complex" means when the file is
`Complex.swt`. A clash with a name already bound is the ordinary
redeclaration error, which is the right amount of protection for a
form that imports a module's whole face. The namespace and named
forms stay for the cases they serve.

**`modules/Rational.swt`; `static let` is lazy — DECIDED (round 149)**
("Let's implement `Rational` as a module too"). The second library:
exact fractions of Ints, normalized on every construction through a
two-argument `init` (reduced by gcd, the sign carried by `num`), so
the synthesized structural equality is the right one and a Rational
is a Dictionary key; one-argument inits dispatch on `$0.Type` — an
Int, a Double converted *exactly* through `frexp` (so `Rational(0.1)`
is the binary fraction the Double is, 3602879701896397/2⁵⁵, which is
the honest answer), a `"n/d"` String, a Rational; Ints lift into the
arithmetic and a Double on either side makes the result a Double,
Ruby's rule. Zero denominators and overflow are Int's own errors — a
module cannot yet raise its own (OPEN). Writing it changed one
decision of round 143: **`static let` is lazy**, evaluated on first
read in the type's scope and then kept, which is Swift's rule too.
The module's `static let zero = Self(0, 1)` ran the init, which
reached for `Self.gcd`, declared later and not yet installed; eager
evaluation in declaration order would only have moved the problem.
A thunk per static, removed before its expression runs, means statics
depend on one another in any order, a self-reference fails instead of
recursing, and a failed initializer is retried — and the type's
tables are never held open while an initializer reads them, a
discipline Swift's exclusivity checker enforced twice this round.
Statics on builtin types, hidden bindings in the root scope, stay
eager.

**SION as a built-in — DECIDED (round 97)**. The user's spec: "`SION(string)`
parses string to SION. `sion.String()` stringify. `SION(json:string)`
treats the string as JSON. `sion.String(.json)` emits a JSON string.
`SION(propertyList:)` and `sion.String(.propertyList)` behaves
accordingly and `sion.Data(.propertyList)` emits binary form. msgPack
and YAML later." **A SION value is any value SION can carry — there
is no box**: `SION(text)` returns the Array or Dictionary itself, and
`.String()` of such a value is its SION text, so the round-trip law
and "SION reads what swiftalk writes" are one fact. Reading reuses
swiftalk's own lexer and parser, admitting only literal forms and the
spellings `.Date(epoch)` / `.Data("base64")` — a document is data,
never code. Two decisions taken with the user: **Data's literal is
SION's** (`.Data("base64")` is the source form, `Data(s)` decodes
base64 failably, and the text's bytes moved to `s.Data(.utf8)`,
mirroring `d.String(.utf8)`), and **JSON is lossy but useful** (Data
→ base64 String, Date → epoch number, a non-String key → its
`String()`; `nil` → `null`). Property lists refuse what they cannot
carry — `nil`, non-String keys — as errors, never a silent loss; XML
in Apple's layout, binary as `bplist00`, both verified against
`plutil`. A malformed document is a type error with a position, not
`nil`, since `nil` is itself a SION value. `SION` stays an annotation
name too (round 59). Foundation-free throughout: base64, JSON, an XML
subset, civil dates, and bplist are hand-written in `Formats.swift`.
**OPEN**: msgPack, YAML; `Any`-lock inference so `let doc = SION(text)`
binds a mixed document without an annotation (the strict `let` of
round 59 refuses mixed keys and values — the next round's subject).

**`.pretty` — DECIDED (round 117)** ("Add `.pretty` option to
(Array|Dictionary|SION).String()"). One more word in `.String()`'s
format vocabulary, and the first that combines: `.String(.pretty)`
is the source form laid out one element per line, two spaces a level
— Arrays and Dictionaries open up, everything else prints as it
does on its own line — and `.String(.json, .pretty)` (either order)
is the same layout for JSON, `"key": value` with a space. Alone,
`.pretty` means `.sion`, since SION is the source form; with
`.propertyList` it is accepted and changes nothing, that text being
laid out already; with a number format (`.hex`, `radix:`) it is an
error. Not a new format: the text is the same document — `SION(v.
String(.pretty)) == v` — with whitespace SION and JSON both ignore.
Empty containers stay `[]`, `[:]`, `{}`. **Round 118** extends the
opening-up to every composite with a literal source form: tuples
(labels kept, `(7,)` keeping its comma), structs (memberwise, one
property per line), and enum cases with payloads; a payload-less
case, an empty tuple or struct, and the leaves — Data, Date, Regex,
Range, the Function-family placeholders — stay on one line. The
pretty text is still the source form, re-entering wherever its types
are declared. **Round 151** ("`rat.String(.pretty)` goes
`"(num/den)"`") first let a type's `let String = { ... }` member
speak only for its `.pretty` text, the plain form of a container
staying the builtin's; **round 152 — DECIDED** ("`"(num/den)"` as
default `.String()`") widened it to the rule Swift's
`CustomStringConvertible` has: **a struct or enum whose type declares
`let String = { ... }` owns its text wherever a value of it prints**
— `x.String()` and `x.String(format)` (the member sees its format
arguments as `$`), `String(x)`, `print(x)`, `"\(x)"`, the REPL's
echo, and inside any container, plain or `.pretty`, keys included:
`[Rational(1, 2): 1]` prints `[(1/2): 1]`. Two forms never ask the
member: **`.description`/`.debugDescription`**, which are the
builtin memberwise text — so a member can say `.description` for the
builtin form without recursing (`String(self)` would be the member
again) — and **the data formats** `.sion`, `.json`, `.propertyList`
on a container, whose text is SION's, not a type's to change. A type
that takes this offer trades the round trip of its text for
legibility — `(1/2)` re-enters as an Int — which is its choice to
make, as Swift's `description` is; Rational's own init reads its
text back, `Rational("(3/4)")`. Builtins do not take part: an
`extension Int { let String }` is not consulted for a nested Int.
**Round 153** ("Add `rat.String(.canonical)`") names the escape hatch
as a format word: **`.String(.canonical)`** is the builtin memberwise
source form — `.description`'s text — with no type's `String` member
asked at any depth, so `[r].String(.canonical)` is
`[Rational(num: 1, den: 3)]` where `[r].String()` is `[(1/3)]`. It
combines with `.pretty` and with nothing else; on a builtin value it
is the source form as ever. The word is the interpreter's, not the
member's: a `String` member never receives `.canonical`, so a type
cannot hide its memberwise form. Asked for Rational, given to every
type — one rule is cheaper than one member per module.

**`nil` infers `Any` — DECIDED (round 101)**. Round 59's inference
refused to bind a strict `let`/`var` from `nil` ("cannot infer a type
from nil — annotate it"), which bit every failable conversion — `let
v = Int(text)` could not even be tested for nil — and every SION
document with a `nil` in it (round 85's first finding, met again in
round 97). Now `nil` says nothing about the type, so the lock is
`Any`: `let v = Int(text)` binds and `v == nil` asks; `var x = nil`
takes anything later, as an `Any` does. Inside a container a `nil`
beside typed elements makes that element lock optional — `[1, nil]`
is `[Int?]`, still refusing a String — and a container of nothing
but `nil` is `[Any]`; a Dictionary's values were optional already
(round 35). A tuple element that is `nil` destructures. What stays:
round 59's homogeneous-or-annotate rule for *mixed* literals —
`[1, "a"]` and a mixed-key Dictionary still want `[Primitives]`,
`SION`, or `Any` spelled out, the user's decision then, not
revisited here.

**Compound assignment — DECIDED (round 102)**: `+= -= *= /= %=`,
Swift's, on whatever the operator takes — Ints and Doubles, `+=` on
Strings and Arrays. `x op= y` reads, combines with the same `binary`
the operator uses (so the type lock, zero-division, and overflow
answers are the operator's), and writes through the same path
machinery as `=`: `a[f()] += 1` evaluates `f()` once, `p.x *= 2`
rebuilds the struct copy-on-write, a `let` refuses, the REPL does
not implicitly declare through `op=`. Its value is the value
written, as an assignment's is. A tuple pattern is not a target.
**`??=` — DECIDED (round 103)**, a divergence from Swift, which has
none: `x ??= y` writes `y` only when `x` is what `??` steps over —
nil, or a Result failure — and leaves `y` unevaluated otherwise;
`d["k"] ??= 0` is the set-a-default idiom. The write goes through the
lock, so a failed Result takes a Result (`r ??= .success(0)`), not a
bare payload. **`&&=` and `||=` — DECIDED (round 104)**, closing the
family ("any binop `a = a op b`"): Bool targets and Bools only, with
the operators' short-circuit — `false &&= x` and `true ||= x` never
evaluate `x`. The `op=` set is now every binary operator that can
spell one: `+ - * / % ?? && ||`. The comparisons cannot (their
spellings already end in `=`), the range operators make no assignable
value, and `=` itself is assignment — so the family is complete, not
open-ended.

**Bitwise operations are methods — DECIDED (round 105)**. The user:
"They are rarer than ever especially in modern languages yet needed
sometime. I am a little reluctant to implement operators for that
since symbols are so precious." Kotlin's answer, then: `a.bitAnd(b)`,
`a.bitOr(b)`, `a.bitXor(b)`, `a.bitNot()` (round 107 gave them the
`bit` prefix; round 105 had spelled them bare), `a.shifted(by: n)` —
one name, a
positive `n` shifting left and a negative one right (the user's
refinement; Swift's smart shift underneath, so an overshift is 0 or
-1, never a trap), `a.bit(i)`, and the `[Bool]` the user first
proposed as a *view*: `a.bits` (64, bit 0 first) and `Int(bits:)`.
Not the carrier — elementwise `[Bool]` operations would need the
vocabulary anyway and `&&` on Arrays would break "Bools only";
width and sign have no natural answer; and the real uses (packing,
checksums, base64) want a word, not 64 allocations. `Bool(Int)` is
`false` for 0 and `true` otherwise — a conversion, which leaves §3b
untouched: nothing is truthy in a condition. A recorded divergence
from Swift and JavaScript both; `& | ^ ~ << >>` stay free — `|` in
particular for a type union, `Int | String`, should annotations ever
want one. **Round 106**: the four bare names on a *Bool* are the
logical operations — `b.not()`, `b.and(c)`, `b.or(c)`, `b.xor(c)` for
`!`, `&&`, `||`, and the new **`^^`**. **Round 107** then gave the
Int set the `bit` prefix — `bitNot`, `bitAnd`, `bitOr`, `bitXor` —
so each name has one meaning and one receiver, and an Int asked for
`.and()` is told about `.bitAnd()`. The methods are eager (a method
evaluates its argument; `&&`/`||` short-circuit), a difference worth
one sentence in the docs and no more. `^^` is logical xor, Bools
only, both sides evaluated, with a precedence level of its own
between `&&` and `||` (C's `^` sits between `&` and `|` for the same
reason); `^^=` joins the `op=` family by round 104's rule. A lone `^`
is a syntax error that names both spellings — the symbol is still
unspent.

**Math is built in, as `Double.`'s static members — DECIDED (round
108)**. The user: "Math constants and functions should be built-in as
well since they are there at (Darwin|Glibc) yet `.swt`
implementations are expected to be slow. Add them as static
constants|functions of `Double.` all real functions in `libm`.
coverage as full as JS `Math`." So `Double.pi`, `Double.sqrt(x)`,
`Double.pow(x, y)`… — every real function libm has and everything
JS's `Math` has (bar `clz32`/`imul`, which are Int's), Swift's names
where Swift has them and lowerCamel for JS's constants. Decisions:
Int arguments promote, since the type is named in the call, and
results are Doubles (an Int from `ilogb`, Bools from the predicates,
labeled tuples from `modf`/`frexp`/`remquo`); a function member
taken uncalled is a Function value, so `xs.map(Double.sqrt)` reads;
`round` is C's and Swift's half-away-from-zero, not JS's half-up —
recorded; `random()` is the system generator in [0, 1). The first
static members on a builtin type; the mechanism is one hook in
member dispatch on the type's constructor Function. **Round 109**
added `Int.random(in:)` the same way — Swift's, on a bounded,
non-empty Range (empty traps in Swift, errors here; `0...` is
refused); a `Double.random(in:)` cannot be spelled while Ranges are
Int-only — so **round 112** made the bounds arguments: `Double.random()`
in [0, 1), `random(max)` in [0, max), `random(min, max)` in [min, max),
finite and non-empty, the user's own three-line spec. **Round 119**
named them: `random()`, `random(to:)`, `random(from:to:)`, half-open
([0, 1), [0, to), [from, to) — finite, from < to); the labels may be
omitted — positional is (from, to), so round 112's spellings still
read — but a wrong label is an error. Round 119 had given `Int` the
same three shapes, closed; **round 120 took them back** ("Int has
range. Forget about Int.random. Just limit to .random(f..<t) and
.random(f...t)"): a Range already says half-open or closed itself,
`Int.min...Int.max` is the whole line, and a second spelling of the
same thing is exactly the kind of vocabulary the small core refuses.
So `Int.random(in:)` — round 109's, the `in:` optional — is Int's only
form, and Double has the labeled bounds only because Range is
Int-only. **Round 113**
added Swift's static properties: `Int.min`, `Int.max`, `Int.bitWidth`,
`Int.zero`, `Int.isSigned`, and `Double.zero`/`radix`/
`exponentBitCount`/`significandBitCount` — constants, read bare.
**Round 114**, for `String`, which has no static properties of its own:
`String.fromCodePoint(n, ...)` (JS's name; Swift's `String(UnicodeScalar)`;
a surrogate or out-of-range Int is an error), and §11's views on
instances — `unicodeScalars`/`utf32` as the scalar values and `utf8`
as the bytes, each `[Int]`, no `.utf16`. Round 85's hand-rolled UTF-8
encoder in `eg/sion.swt` is thereby optional; it stays as the
bitwise demonstration.

**`typealias` — DECIDED (round 110)** ("We haven't implemented
typealias yet"). Swift's, for the annotation vocabulary: `typealias
Name = Type` where `Type` is anything an annotation can say — a
builtin, a user struct or enum, `[T]`, `[K: V]`, `T?`, `Any`/`SION`/
`Primitives`, or another alias. Resolution happens once, where the
annotation is used (a declaration, a struct property, an enum
payload), and locks are stored resolved, so the rest of the type
discipline never meets an alias. An alias to a plain type is bound to
that type's value as well, so `Number("7")` constructs and `x.Type ==
Number` holds; an alias to a parameterized or optional type is
annotation-only. Scoped like a binding. One more keyword, Swift's own.
OPEN: exporting an alias across modules (exports are values; a
parameterized alias has none).

**RETRACTED in round 111** — the user: "Unlike types in Swift, Types
in swiftalk are also a Function object so a simple `let I = Int`
does the same as `typealias` (I've tried). Retract `typealias` and
document the workaround. And make `42.S()` work if we have `let S =
String`." So: no keyword; a binding is the alias. What round 110's
machinery had given annotations survives in a smaller form — an
annotation naming a binding that holds a type means that type (a
declaration's, a struct property's, an enum payload's, nested in
`[...]`), resolved once and stored resolved — and the round-47 law
gained its last step: `x.S()` with `let S = String` is `x.String()`,
failing by the real name when the conversion does not exist. A
parameterized or optional annotation has no value to bind and so no
alias; that is the one thing `typealias` did that a binding cannot,
and it is not worth a keyword.

## 3a. Optionals & nil — DECIDED

**The full Optional suite survives — on a flat model.** `nil` is *not*
a member of every type; `T?`, `if let`, `guard let`, `??`, and optional
chaining `?.` all work. This is Swift's most recognizable feature and
precisely the cure for the `undefined`/`null` chaos of the scripting
tradition. But unlike Swift, **`T?` is not a wrapper**:

* **Flat union: `T?` means "a `T`, or `nil`".** There is no
  `Optional<T>` box, no `.some`/`.none`. A `2` sitting in an `Int?`
  slot is a plain `Int`:

  ```swift
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
* **`d.merging(e) { current, new in }` and `d.merge(e) { }`** (round
  126): Swift's pair, the first a new Dictionary, the second in place
  on a `var` path — the combine function called as (current, new),
  `uniquingKeysWith:` accepted and dropped as Swift's labels are. One
  divergence, recorded: **the function is optional, and without it
  the new value wins** — the spread's rule (`{...a, ...b}`), where
  Swift insists on the function. `merge` returns `nil`, like
  `append`; the target's lock is checked on the way back in.
* **`d.keys` and `d.values`** (round 127): Swift's properties, read
  bare like `count`, giving Arrays rather than Swift's lazy views —
  a view type would be one more thing, and an Array already has
  every member a view offers. **Revised in round 132**: `keys` is a
  Set, once there was one — a key list has no order to promise, and
  `d0 == d1` should give `d0.keys == d1.keys`; `values` stays an
  Array in the Dictionary's own order, the one `for k, v in d`
  walks. The called spelling is an error that names the property.

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
**(SHELVED, round 62 — both reference types are off the surface for
now; swiftalk is values + coroutines + tasks until they earn their
way back.)**

**`class` — DECIDED and implemented (round 55), SHELVED (round 62): the open reference,
and indeed the smaller step** — an actor minus the serialization and
minus the isolation, plus **single inheritance**. `class Dog: Animal`
merges the superclass's properties (shadowing is an error), resolves
methods up the chain at call time (override = redeclare; **dynamic
dispatch**: a superclass method calling `.speak()` gets the
subclass's override), and satisfies annotations up the chain (`let
pet: Animal = Dog(...)`). No init inheritance.

**`super` — DECIDED and implemented (round 56), SHELVED (round 62) with class, class-only by
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
enums; computed setters on builtins.

**Property observers — DECIDED and implemented (round 58b)**:
**`willSet`/`didSet` on stored `var` properties** of struct, class,
and actor — `var x = 0 { willSet { ... } didSet { ... } }`, or on an
annotated property with no default. willSet runs before the store
(self still old, the incoming value as `newValue` or `set`-style
custom name); didSet after (self new, the replaced value as
`oldValue`/custom). Swift's rules carried over: **silent during
init** (memberwise and declared alike); **didSet may reassign its own
property without recursing** (the canonical clamp — a per-context
re-entrancy guard, keyed by identity for references and by type for
structs, cuts the loop); path writes (`s.list[1] = v`) fire the
container property's observers. Classes inherit observers with their
inherited properties. Observers are for STORED properties only —
a computed property puts that code in its setter (round 57). The
disambiguation that made the syntax parseable: a brace opening with
`willSet`/`didSet` is never a trailing closure. OPEN: observers on
globals/locals.

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

**Multi-dispatch exists in exactly one place: Type `init`s** (round
48, bounded so by round 61 — "limit multi dispatch to Type inits").
Methods, free functions, and everything else stay one-name-one-body.

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

**Full Swift enums**: associated values, `switch` with runtime-enforced
exhaustiveness, and **case accessors** (round 46) in place of Swift's
`.circle(let r)` patterns. **Binding a case — DECIDED (round 78,
completing 77)**: the accessor is the one mechanism everywhere —
`if let r = s.circle`, `while let (w, h) = next().rect`, and in a
`switch`, `case let r = .circle:` / `case let (w, h) = .rect:`, where
`.circle` is the subject's case. Nil is the only "no"; a pattern that
does not fit a non-nil payload is an error. Several payloads come as a
tuple labeled as the case declares, so labeled patterns work (`case
(h: h, w: w) = .rect:`); bare `case .circle:` matches any payload;
`case var p = .point:` binds mutably. Swift's `if case` and
`.circle(let r)` are **gone** — syntax errors with a hint (the user's
verdict, round 78: "`.casename(let v)` should be `let v =
.casename`"). **`let` is optional in a binding — DECIDED (round 78)**:
assignment is a statement in swiftalk, so an `=` inside a condition
or a `case` can only mean "bind" — `if v = opt`, `while x = d[i]`,
`case r = .circle:`, `if (a, b) = t`; `var` is still spelled out for
a mutable binding, explicit `let` remains fine. `==` is untouched:
`if (a, b) == t` compares. **`where` guards — DECIDED (round 81)**:
`case let r = .circle where r > 1.0:` — a Bool expression after the
pattern, seeing its bindings; false is a non-match, on to the next
alternative (and, with no `default`, to the exhaustiveness error).
`where` is contextual, not a keyword (`let where = 3` is legal). The
guard belongs to the pattern it follows — Swift's rule, kept because
each alternative binds in its own scope: `case 1 where c, 2 where c:`
guards both, `case 1, 2 where c:` only the 2. `if`/`while` need no
`where`: the comma list already is one. **`for x in s where c` —
DECIDED (round 82)**: `for x in s where c { }` is `for x in s.filter({
... }) { }` with the loop's own names in the condition — the same
elements in the same order (a Dictionary's order being its own, as
ever), decided element by element as the
iteration pulls them, so an infinite lazy Sequence filters lazily and
`break`/`continue` are untouched (`filter` exists on every Sequence
conformer, §10; `where` is the human spelling — "note `{}` is omitted"
— and the only spelling with a trailing closure, since `for` headers
refuse them). A non-Bool condition is the §3b type error; `where`
stays contextual. **`if o { }` — DECIDED
(round 80, revising 78's "a bare `if x { }` is a Bool test")**: a
bare *variable* as a condition asks the question its value answers —
a Bool is tested (false included), nil is "no", anything else is
"yes" — and inside the block `o` is simply itself: optionals are flat
(§3a), so there is nothing to strip and **no shadow is made**, which
is why `while node { node = node.next }` drains a list (the write
reaches the variable; Swift's `while let node` shorthand would bind a
copy). Only a bare variable gets this: `if Int(s) { }` or `if d[k] {
}` is still the §3b type error — capture it, `if x = Int(s) { }`. **`switch` is an expression — DECIDED (round 79, Swift
5.9's)**: its value is the chosen branch's last statement's value —
the rule a closure body (and the REPL) already follow — so `let x =
switch ...`, `return switch ...`, `1 + switch ...`, and the implicit
return in `{ s in switch s { ... } }` all yield; §14's `area` runs
verbatim. A branch may hold several statements (Swift restricts a
branch to one expression; swiftalk does not need to — the last-value
rule already exists); a branch ending in a non-expression yields
`nil`. Statement-level `switch` is simply an expression statement, so
there is one `switch`, not two. Exhaustiveness is unchanged. **`if` is an expression too — DECIDED
(round 80, SE-0380's other half)**, `if let` and `else if` included:
the taken branch's last statement's value, `nil` when no branch
runs — `let x = if o { o * 2 } else { 0 }`, `{ n in if n > 0 { 1 }
else { -1 } }`, `1 + if c { 1 } else { 2 }`. `while` stays a
statement (its value is nil). Statement-level `if` is an expression
statement — one `if`, as with `switch`.

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
  matching on the `Result` (`switch`, `if let e = r.failure`).
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

## 9. Non-goals — the keyword graveyard, and more

Keywords swiftalk has PROVEN unnecessary, each killed in dialogue:

* **`func`** (round 8): `{}` is the only function form.
* **`mutating`** (round 50a): mutation permission is the properties'
  `var`/`let` and the receiver's var-ness.
* **`async`** as a function color (round 53): any function may
  `await`; the word survives only as spawn-site sugar for `Task {}`.
* **`guard`** (round 60): "it is only `if not`" — the user's own
  words, wanting as few keywords as possible. `if let ... { } else
  { return ... }` covers the pattern; `guard` never became a keyword,
  and `let guard = 1` is legal swiftalk (the test suite proves it).
* **`if case` and `case .name(let x)`** (round 78, after 77's "one of
  the ugliest designs of Swift"): the case accessor is a plain
  optional, so binding a case is `if let r = s.circle` and, in a
  switch, `case let r = .circle:`. Both Swift forms are syntax errors
  that point at the replacement.

Also non-goals: manual memory control, `unsafe` anything, ABI
stability, Objective-C interop.

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

  ```swift
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

**`sorted` and `contains` — DECIDED (round 83)**, on every Sequence
conformer. `s.sorted()` is always an Array (a String's graphemes, a
Dictionary's `(key:, value:)` pairs, a lazy Sequence drained — so it
must be finite, like `.Array()`); bare, the elements must be
Comparable among themselves (Int, Double, String, Date — `<` decides,
and its type error is the answer for a mixed or non-Comparable
Array, which is why a Dictionary needs the closure); `sorted { a, b
in }` / `sorted(by:)` takes Swift's areInIncreasingOrder. `contains(x)`
asks by equality — everything is Equatable, tuples included, so
`d.contains((k, v))` asks about a pair; `contains { }` /
`contains(where:)` by predicate; a String looks for a substring, as
Swift's does (`"hello".contains("ell")`); the search short-circuits,
so an infinite Sequence answers on the first hit. Swift's labels
`by:` and `where:` are accepted and dropped — the only builtins
besides `conforms(to:)` that take a label. **`reversed` and `joined`
— DECIDED (round 84)**: `reversed()` is always an Array (as
`sorted()`: graphemes, pairs, a drained finite Sequence);
`joined()` / `joined(separator:)` concatenates Strings into a String
or flattens Arrays into an Array — the separator, or without one the
first element, says which, and every element must agree (a mix is a
type error; "map it to a String first"); empty joins to `""`, or `[]`
under an Array separator; a String's own graphemes join too, so
`"abc".joined("-")` is `"a-b-c"`. `separator:` joins the accepted
labels. **`a...` and `prefix { }`/`dropFirst { }` — DECIDED (round 88)**:
`0...` is the unbounded range, Swift's `PartialRangeFrom` as a
first-class value — infinite and lazy, printed as written, a
Sequence conformer whose `map`/`filter`/`enumerated`/`prefix { }`/
`dropFirst { }` defer (the same laziness a `Sequence` value has) and
whose eager terminals (`count`, `reduce`, `sorted`, `reversed`,
`joined`, `Array()`) refuse it with the same message a Sequence's
`.count` gives; `for i in 0...` with `break`, `(0...).prefix(n)`,
`(1...)[i]`, `case 40...:` all work; the element after `Int.max` is
an overflow error, not a wrap; `a..<` has no unbounded form. The
parser reads `a...` as unbounded when nothing that could be a bound
follows (`) ] } , : ; {` or a line end). `prefix { }` /
`dropFirst { }` take the leading elements while a predicate holds /
everything from its first miss, the predicate never asked again
after it — lazy on a Sequence value and on `a...`, eager and shaped
like `filter` (String → String, Dictionary → Dictionary) elsewhere.
(Round 88 named them `takeWhile`/`dropWhile`; **round 98 folded them
into `prefix`/`dropFirst`**, Swift's `prefix(while:)` way — the
argument's type dispatches, an Int counting and a Function deciding,
Swift's `while:` label accepted; a keyword may be an argument label
since this round, as in Swift. The user's principle: swiftalk's
methods are not multi-dispatch, but their arguments are untyped, so
one name switches on `$0.Type`. Swift's `drop(while:)` is a second
name for the drop; swiftalk keeps one, `dropFirst`, with both
argument kinds — the recorded divergence.) **The slicing
family — DECIDED (round 89)**: `suffix(n)`, `dropFirst(n = 1)`,
`dropLast(n = 1)`, and `split` on every Sequence conformer, Swift's
names and semantics — `n` clamps to the count, a negative `n` is an
error; `split(x)` / `split { }` (`separator:` / `whereSeparator:`
accepted) cuts at elements equal to a value or accepted by a
predicate, empty pieces omitted as Swift's default. **Shape rule,
now uniform**: every slice is shaped like its receiver — a String's
is a String, a Dictionary's a Dictionary, anything else an Array —
which is Swift's SubSequence rule and what `filter`/`prefix { }` did
already; `prefix` joins it (round 41 had it return an Array for a
String — revised, the one behavior change). `dropFirst` is lazy where
`map` is (a Sequence value, `a...`); `suffix`, `dropLast`, and
`split` must see the end and refuse an infinite source. This closes
round 85's "index-free slicing" leaning: with `prefix`/`suffix`/
`dropFirst`/`dropLast`/`split`/`prefix { }`/`dropFirst { }` and `Array()`
+ `joined()` for random access, **String subscripts are not coming**
— decided, not OPEN. **The Array Range subscript — DECIDED (round
90)**: `a[1..<3]`, `a[1...2]`, `a[1...]` give a new Array of those
positions (a value, never a view — no ArraySlice, per §4), under
Swift's bounds rule `0 ≤ from ≤ to ≤ count`, so `a[a.count...]` is
`[]` and anything past the end is the same error `a[i]` gives.
**Assignment through it — DECIDED (round 91)**: `a[0..<1] = [9]` is
Swift's `replaceSubrange` — the positions in the range are replaced
by the right side's elements, however many, so `a[1...] = []`
truncates and `a[a.count...] = xs` appends; the right side must be
an Array ("RHS must be an array of the same element type, otherwise
fatal error" — the user), and the element types are the variable's
lock, checked as the rebuilt Array lands, so `a[0..<1] = ["x"]` on
a `[Int]` is the same error `a[0] = "x"` is. Bounds as for reading.
**`Data` follows (round 92)**: `d[1..<3]` / `d[1...]` read a Data,
`d[0..<1] = Data([...])` is the same `replaceSubrange` with a Data on
the right, and `d[i] = byte` writes one byte (an Int in 0...255 —
Data's "element type", checked at the write, since a Data has no
per-element lock to land through). One bounds helper serves Array
and Data, reading and writing. Strings stay without a subscript
(round 89). **Data is a Sequence (round 115)**, of its bytes as Ints —
the last conformer the roster of §10 lacked; its slices are Datas and
its `map`/`sorted`/`reversed` Arrays, Swift's shapes.

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

**String subscripts, slicing, and RegExp — LEANING (round 85)**. The
user's question: "Both JavaScript and Swift screwed hard on
subscripting String. Should we consider adding RegExp?" — and then,
before deciding, "I want to know how far we can go WITHOUT RegExp.
It is powerful but heavy on footprint. I am considering making it a
module (oh, we haven't even talked about `import`)". The experiment
is `eg/sion.swt` + `eg/sion.md`: a complete SION parser in swiftalk,
no RegExp, no String subscripts — it went all the way on graphemes
via `.Array()`, labeled tuples, and `Result` + `?`. Positions:
**no integer subscripts on String** (that is the mistake both
languages made — UTF-16 units in JS, `String.Index` pain in Swift);
`s.Array()` is the honest random-access form and `.joined()` the way
back. LEANING next: the index-free slicing family on every Sequence
conformer (`suffix`, `dropFirst`, `dropLast`, `split`) plus a Range
subscript on Array; then RegExp **as a module**, which makes
`import` the prerequisite design — **OPEN**: modules and `import`
(shape, what a module is, whether builtins like Regex live in one).
Findings from the experiment, each OPEN (`%` landed in round 93 —
Swift's remainder, Int only, `% 0` a zero-division and `Int.min % -1`
an overflow, both as `/`; `"""` and raw `#"..."#` literals landed in
round 94, Swift's rules — indentation stripped to the closing
delimiter, `\#(...)` the raw interpolation):
newline continuation after a trailing binary operator (landed in
round 95: the newline after `+ - * / % =`, a comparison, `&& || ??`
is not a separator — not after postfix `!`/`?`, and not after `...`,
which round 88 gave a meaning at a line's end; the leading form
landed in round 96 by Swift's whitespace rule — an operator leading
a line with whitespace after it is infix and continues, `-x`/`!x`
with none is a prefix; a leading `.` is excluded, since `.x = 1` at
a line's start is implicit self); a strict `let` refusing `nil` (and `let` destructuring refusing a nil
element); implicit-self `.name` shadowing format tags inside a type
body; error messages without line numbers; Data's source form
`Data([...])` vs SION's `.Data("base64")` (settled in round 97: SION's);
and **no recursion
guard** — the recursion budget is the thread's stack and nothing
checks it, so a deep program on a small-stack thread is a SIGBUS,
not an error (the SION test had to move to a 64 MB pthread).

**Regex is a core type — DECIDED (round 86, revising 85's module
leaning)**. The user: "I now think Regex needs to be part of the
standard type because `//` is a part of the grammar. Of course we can
go like Python `import re; rx = re("exp")` but it is pain in the arse
(Of course `Regex("string")` is a valid constructor, BTW)." So:
`/pattern/flags` is a literal, `Regex(pattern)` / `Regex(pattern,
flags)` the constructor, `Regex` the type name (Swift's, over JS's
`RegExp`); the engine is Swift's stdlib `Regex` (Foundation-free; the
package now targets macOS 13 for it). A `/` starts a regex where an
operand cannot end — JavaScript's rule, which a lexer that tracks the
previous token applies without Swift's `#/.../#` hedge; `\/` is the
one escape the lexer interprets. Flags `i m s x`, applied as an
inline `(?flags)` prefix. **A match** is the matched String when
there are no captures and a labeled tuple when there are — `.0` the
whole, then the groups, named ones labeled, nil where absent —
Swift's own shape, which means rounds 74/75/78 do the rest: `if let
(_, y, m, d) = s.firstMatch(/.../)`, `.year` on a named group, `case
let (_, u, v) = /(\w+)@(\w+)/:` (round 78's binding with a Regex
source, whole-match as Swift's `~=`), `case /\d+/:` by whole match,
`where m.1 != nil`. The String API is Swift's, labels accepted:
`contains`, `firstMatch(of:)`, `wholeMatch(of:)`, `matches(of:)`,
`replacing(_:with:)` (a String or a Function of the match — which
splats, per round 73), `split(separator:)`; `Regex` is Equatable and
Hashable by pattern and flags, and re-enters through its source form.
**A character is a grapheme (round 87)**: the engine matches extended
grapheme clusters, `count`'s unit — `.` and `\X` take one, comparison
is canonical, and a scalar range `[\u{X}-\u{Y}]` matches a grapheme
only when it *is* a single scalar in the range (so `か\u{309A}` needs
`\p{Hiragana}`, and a flag never matches a Regional-Indicator range);
the stdlib has no scalar mode today (`(?u)` refused). **OPEN**: `=~`;
`$1` templates; match ranges; a `u` flag for scalar semantics if the
stdlib's API switch is ever wanted; the slicing family and the Array
Range subscript stay LEANING; `import` is still undesigned (Regex no
longer waits on it).

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

### Actors — DECIDED (round 54), SHELVED (round 62)

> **SHELVED (round 62)** with `class`: "When we implemented actor,
> we resorted to implement class. Let us shelve them for the time
> being." The design below stands as recorded; the machinery stays
> in-tree, dormant; the surface keywords are gone (and are plain
> identifiers again).

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
   `eval()` in the language itself — **exposed in round 122**, at the
   program's top level; the §5 core grew by one function.
1. **Implement REPL** — a read–`eval`–print loop around milestone 0.
   This is where §2.2's relaxed mode (bare `x = 1` allowed) first
   matters, and where `.String()`-on-everything (§3d) pays off for
   printing results. **DONE (first cut)**: `swift run swiftalk` —
   relaxed mode on, echo in `.String()` source form (every echo obeys
   the round-trip law), multi-line continuation while brackets are
   open, prompts suppressed when stdin is not a TTY (pipe-friendly).
   **Commands (round 131)**, `swift repl`'s style, a line starting with
   `:` — three at first: `:h` help, `:r let x = ...` redefines a
   top-level binding (the old one replaced whatever its type or
   mutability, restored if the new declaration fails), `:d x`
   undefines one. The REPL's business, not the language's: a script
   has no `:r`, and `redefine`/`undefine` live on the Interpreter for
   any embedder's REPL. **Round 141** extends `:r` to `struct` and
   `enum` (the name rebound; values made under the old type keep it,
   as a redefined closure keeps its captures) and to `extension T { }`,
   which at the prompt **overwrites** methods and computed properties
   of the same name where a file's extension refuses them — stored
   properties and enum cases never give way. `:d` removes a type as
   it removes any binding.
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

Moved to [README.md](README.md) — the front page is the example
page now (round 65).

---

## 15. Modules — DECIDED (round 100)

The user's spec, before the strict-`let`-with-`Any` round: "It will be
more like JS than Swift because we want to load `.swt`. `from` is
necessary. `where` is usually a path but urls like `https://` are
okay so long as CORS allows. `import M from "./mod.swt"` imports all
symbols under the `M` namespace. `import (foo, bar) from ...` imports
`foo` and `bar` into the top level. Note it is not `import {foo,
bar}`. only `export`ed symbols are importable."

* **A module is a file**, evaluated once per Interpreter, strict, in a
  scope whose parent is the builtins — it sees `print` and `Int`,
  never the importer's globals (the builtins moved to a scope of
  their own for this). Loading is cached by resolved path, so every
  importer shares one instance; a circular import is an error.
* **The namespace is a labeled tuple of the exports** — no new type.
  `M.x` reads, `M.f(1)` calls through (round 70's rule), `M.Point(x:
  1.0)` constructs. Exports are values copied at import, imported
  names are `let`s; module-private state lives in the closures that
  export it. Live bindings, re-export, and `M.Point` in an annotation
  are OPEN.
* **`export`** prefixes a declaration (`let`, `var`, `struct`, `enum`,
  a destructuring `let`) or names existing ones, `export (a, b)`.
  `import`/`export` belong at a file's top level. `from` is contextual;
  `import` and `export` are keywords (two more, for a feature that
  cannot be spelled without them).
* **Resolution** is beside the importing file — the CLI's script, or
  the module doing the importing — with `./` and `../` folded; the
  REPL resolves from the cwd; absolute paths and URLs as they are.
  **URLs**: the core stays Foundation-free, so it reads files through
  POSIX and *refuses* URLs unless the embedder supplies
  `Interpreter.moduleLoader`; the CLI supplies one that spawns `curl
  -fsSL` (posix_spawn, no Foundation). "So long as CORS allows" is
  the browser's concern, not the CLI's.

## Dialogue log

Moved to [Dialogue.md](Dialogue.md) (round 65) — append-only and
chronological, one entry per round, as ever.
