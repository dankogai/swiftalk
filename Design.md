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
  { 42 }.type       // Function
  { 42 }().type     // Int
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
* **Methods / `init` without `func`** — **deferred until milestone 0**
  (`eval()` needs free functions only; method syntax can wait for user
  types to land).

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
* Types are runtime-queryable: `x.type` (cf. Ruby's `x.class`,
  Swift's `type(of: x)`). This is what makes iterating a sequence of
  mixed types easy — inspect `element.type` as you go.

**OPEN** details:

* Presumably annotations are allowed and enforced: `var x: Int = 1`.
* Is `x.type` a first-class value? (`x.type == Int`, usable in `switch`,
  storable in variables?) Do `is` / `as?` / `as!` survive alongside it?

### 3b. Basic types — DECIDED (core)

*(Revises round 2: `Int` was to be arbitrary-precision; it is now fixed
64-bit, with bignum demoted to a possible separate `BigInt` type.)*

Primitives:

* **`nil`** — the absence value, the sole inhabitant of type **`Nil`**
  (`nil.type == Nil`). Never again JS's `typeof null === 'object'`.
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
  `String`**. Bytes are bytes; text is text.
* **`Date`** — joined the roster in round 17 as a consequence of
  `Primitives`' SION-completeness (§3c): SION carries dates natively,
  so swiftalk does too. Representation/literals **OPEN**.
* **`Function`** — the **one** type of every function/closure (§2.4):
  `{ 42 }.type == Function`, `{ 42 }().type == Int`. Signatures are
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
* **`.String()` round-trips — the general law.** Its output is
  swiftalk source that restores the value when fed back to the
  runtime:

  ```swiftalk
  eval(x.String()) == x           // for every value x, every type
  (0.1 + 0.2).String()            // "0.30000000000000004" — not "0.3"
  ```

  `Double` stringifies as the shortest decimal that parses back to
  the same bits (JS/Ryū-style); `Array`/`Dictionary` emit literal
  syntax (`[1, 2, 3]`, `["a": 1]`); `nil` emits `nil`. For
  `Primitives` values this *is* SION emission (§3c) — the native
  serializer and `.String()` are one mechanism.
* Consequences of the law (flagged, not yet confirmed):
  * A `String`'s own `.String()` must **quote and escape**
    (`"foo".String()` is `"\"foo\""`) — identity would not round-trip.
    Whether `print` / `\(...)` interpolation use `.String()` (quoted)
    or a raw display form is **OPEN**.
  * **`Data.String()` argument-less must emit source form** (e.g.
    SION's base64 spelling), *infallibly* — which squares nicely with
    ".String() is mandatory". The *failable decode* moves to the
    format-argument variant: `data.String(.utf8) → String?`. (This
    revises the round-6 example where bare `data.String()` decoded.)
  * `Function.String()` — source text of the function (JS can;
    Lua punts)? **OPEN**.
* Nice symmetry with §3: lowercase `.type` *queries* the type
  (a property), Capitalized `.TypeName(...)` *converts* to it
  (a method).
* Replaces Swift's initializer-style `String(42)` / `Int("42")`
  conversions as the idiom. (**OPEN**: whether initializer style also
  exists, or `obj.TypeName()` is the only spelling; which conversions
  are failable, per pair; the format-argument vocabulary per pair.)

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
  **`x.type` reports `Int`, not `Primitives`**:

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
  spelled as enums, and `element.type` / pattern matching handle the
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
  maybe.type        // Int — not Optional<Int>
  maybe = nil
  maybe.type        // Nil
  ```

* Consequently **optionals do not nest**: `Int??` ≡ `Int?`. There is
  exactly one absence, `nil`.
* **`nil` is the sole value of type `Nil`** — an honest `.type`, never
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
* **Dictionary lookups collapse**: with `[K: V?]`, `d[k]` is `nil` for
  a missing key *and* for a stored `nil` — the flat model's honest
  consequence (JS lives fine with this). When the difference matters,
  ask explicitly: `d.has(k)` / `d.keys.contains(k)`. Presumably
  Swift-compatible on the write side too — `d[k] = nil` deletes the
  key (**OPEN** to confirm).

## 4. Value vs reference semantics — DECIDED

**Collections are COW values, as in Swift.** `Array`/`Dictionary`/`String`
have value semantics with copy-on-write; assignment and argument passing
copy (logically). This kills the shared-mutation aliasing bugs endemic to
Python/Ruby/JS, and COW keeps it affordable in an interpreter.

**User-defined types get the full Swift menu**: `struct` (COW value,
consistent with the built-in collections), `class` (reference, with
inheritance), plus `enum` (§7). The Swift mental model carries over
wholesale: value types by default, classes when identity matters.

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

* **Protocols, Swift-style**: declaration, conformance
  (`Equatable`/`Hashable`/`Comparable`/`CustomStringConvertible`...),
  protocol-typed variables. Conformance is checked at runtime (no static
  checker to do it earlier).
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

## 12. Concurrency — OPEN (probably defer)

`async`/`await`? Actors? Or single-threaded like classic scripting, with
concurrency added later?

## 13. Milestones

0. **Implement `eval()`** — the core evaluator: source string in, value
   out. Everything else is a client of this. Doubles as the embedding
   API's heart (§5: swiftalk-as-Lua) and, potentially, a user-visible
   `eval()` in the language itself (**OPEN** whether to expose it, and
   how it interacts with the §5 minimal-core goal).
1. **Implement REPL** — a read–`eval`–print loop around milestone 0.
   This is where §2.2's relaxed mode (bare `x = 1` allowed) first
   matters, and where `.String()`-on-everything (§3d) pays off for
   printing results.
2. *(TBD — script runner, embedding API, stdlib growth...)*

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
maybe.type                                    // Int (or Nil when nil)

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
    print("\(x.String()): \(x.type)")         // .String() is universal (§3d)
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
