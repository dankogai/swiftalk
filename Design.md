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
error). **A tuple is a rigid Array of arguments (round 73, revising
72's narrower splat)**: a sole Tuple argument IS the argument list —
`$` holds its elements, so in `d.map { }` `$0` is k and `$1` is v,
and declared parameters bind to them with arity checked against
them (`{ t in }` given a 2-tuple is an error; wrap as `((1, 2),)` to
pass a tuple whole). Builtins are exempt (`print((1, 2))` prints the
tuple). **`.enumerated()`** (round 73) yields `(offset:, element:)`
tuples — lazily on a Sequence value, as an Array on the eager
conformers. **Labels — DECIDED (round 74)**: `(x: 1, y: 2)` with
`.x`/`.y` (and `.0`/`.1` still) — labels *name positions*, so they
are cosmetic: equality, hashing, destructuring, and the splat ignore
them; source form keeps them; `(x: 1)` is a 1-tuple. Dictionary pairs
are `(key:, value:)`, enumerated `(offset:, element:)`. **Labeled
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

```swiftalk
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

  ```swiftalk
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

  ```swiftalk
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
`|` is a syntax error — bitwise operators are undecided.

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
labels. Still OPEN: String subscripts.

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
Findings from the experiment, each OPEN: `%`; `"""` literals;
newline continuation after a trailing binary operator; a strict
`let` refusing `nil` (and `let` destructuring refusing a nil
element); implicit-self `.name` shadowing format tags inside a type
body; error messages without line numbers; Data's source form
`Data([...])` vs SION's `.Data("base64")`; and **no recursion
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

Moved to [README.md](README.md) — the front page is the example
page now (round 65).

---

## Dialogue log

Moved to [Dialogue.md](Dialogue.md) (round 65) — append-only and
chronological, one entry per round, as ever.
