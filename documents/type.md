# type

What a `struct` and an `enum` share: the type as a value, the members
a body takes, extensions, the printed form, equality and order,
modules, the REPL. The two kinds have their own pages —
[struct.md](struct.md) for stored and computed properties, observers,
inits and COW; [enum.md](enum.md) for cases, accessors and `switch` —
and the built-in types one page each in [README.md](README.md);
[toplevel.md](toplevel.md) has the type *values* of the builtins
(`[Int]`, `Set<Int>`, `Int?`, `.Element`).

## A type is a value (§3, round 39)

A declaration binds the name to the type object, and the type object
is its own constructor — a `Function`, as in JavaScript. Everything
that holds of a value holds of a type: it is stored, passed, compared,
hashed, and called.

```swift
struct Point { var x: Int = 0; var y: Int = 0 }
enum Shape { case dot; case circle(r: Double) }
Point.Type                                  // Function — a type is its constructor
Point(x: 1, y: 2).Type == Point             // true
Shape.dot.Type == Shape                     // true
Point.name                                  // "Point"
let P = Point                               // a binding is an alias (round 111)
P(x: 1, y: 1) == Point(x: 1, y: 1)          // true
[Point: "struct", Shape: "enum"][Shape]     // "enum" — types hash by identity
switch Point().Type { case Point: "a Point" default: "other" }   // "a Point"
```

| Form | Meaning |
|---|---|
| `T.Type` | `Function`, for every struct and enum (and every builtin: `Int.Type == Function`) |
| `x.Type == T`, `x.Type.name` | the runtime type test, and its name — there is no `is` or `as` (never built, Design.md §3); `x.Type == T` asks, and `switch x.Type { case T: }` dispatches |
| `T == U`, `[T: v]`, `Set([T, U])` | types compare and hash by identity; a type is a Dictionary key |
| `let T2 = T` | an alias — the same type, so `T2(x: 1) == T(x: 1)` and `extension T2 { }` extends `T` |
| `let p: T = ...`, `[T]`, `T?`, `Any` | a user type is an annotation like any other (§3): the lock holds (`let z: Point = 1` is a type error), containers carry it (`[Point]`), `Point?` is a Point or nil |
| `print(T)`, `T.String()` | the name — `Point` |
| `T.conforms(to: P)` | protocol conformance, below; the argument must be a protocol |

## The body

A body is a brace of members, one per line (or `;`). What both kinds
take:

| Member | Meaning |
|---|---|
| `let m = { ... }` | a **method**: `let` + a closure literal, nothing else (no `func`, no `mutating`, round 50a). `self` is bound; a leading dot (`.x`) is `self.x`; `x.m(args)` calls, `x.m` is the Function bound over a copy of `x` |
| `static let s = value`, `static let f = { ... }` | a **static** (round 143), read off the type: `T.s`; a Function is a static method, `T.f(args)`. Evaluated on first read, in the type's scope, then kept (round 149) — statics may refer to one another in any order |
| `static var g { ... }` | a static getter, run on each read; no setter and no stored `static var` — a type is a value, not storage |
| `infix(+) = { a, b in ... }`, `prefix(-) = { x in ... }`, `postfix(!) = { x in ... }` | **operators** (round 146): existing operators at their existing precedence; either operand's type answers an infix. `infix(<)` makes the type Comparable, `infix(==)` replaces structural equality |
| `let String = { ... }`, `let Int = { ... }`, `let Double = { ... }` | **conversion members** (rounds 47, 151–152): `T(x)` and `x.T()` both run them; a `String` member owns the value's text wherever it prints, and must return a String on every spelling (round 233) |
| `Self` | the type itself, inside the body and its extensions: `Self(x: 1)`, `Self.origin`, `Self.circle(r: 1.0)` |
| *the leading dot* | inside a body a leading dot names `self`'s member first, so a member spelled like a format word shadows it: with `var hex { 1 }` declared, `255.String(.hex)` inside a method is a type error (`.hex` is the member, `1`). Name members otherwise |

What only one kind takes: a struct's stored properties (`var x: Int =
0`, `let tag = "pt"`), computed properties (`var c { get set }`),
observers and `init`s — [struct.md](struct.md); an enum's `case`s and
their accessors — [enum.md](enum.md). An enum has no `init` and, so
far, no computed property (OPEN). A body holds members, not types:
there is no nesting, though a type may be declared inside a function
and is scoped there. No generics (`struct Box<T>` was never built —
types are values, so pass the type), no inheritance (values have no
hierarchy; `class` and `actor` are shelved, round 62), no user
protocols.

A type's name is an identifier — capitalized by convention, as the
builtins and the modules are, though `struct point` parses. Keywords
are refused, and so is a second declaration of the same name in the
same scope (`redeclaration of 'Point'`); at the REPL `:r struct Point
{ ... }` redefines (round 141).

## Extensions (§10)

Members are added after the fact, to a struct, an enum, or a builtin,
by an `extension` body or one at a time (round 228); the two spellings
are one declaration underneath, with one set of rules.

```swift
struct Point { var x: Int = 0; var y: Int = 0 }
extension Point { let norm2 = { .x * .x + .y * .y } }
var Point.swapped { Self(x: .y, y: .x) }
static let Point.origin = Self()
Point(x: 3, y: 4).norm2()                   // 25
Point(x: 1, y: 2).swapped                   // Point(x: 2, y: 1)
Point.origin                                // Point(x: 0, y: 0)
let Int.doubled = { self * 2 }
21.doubled()                                // 42
```

| Form | Meaning |
|---|---|
| `extension T { let m = { } ; var c { } ; static let s = ... ; infix(+) = { } }` | methods, computed properties (structs), statics, operators |
| `let T.m = { }`, `var T.c [: Type] { }`, `static let T.s = v`, `static var T.g { }` | the same, one member each (round 228); one dot, the type's name first |
| *not overwritten* | an existing method or computed property is an error (`T already has a member 'm'`), a stored property or a case always is; `:r extension T { }` and `:r let T.m = { }` overwrite at the REPL (round 141) |
| *program-wide* | an extension of a builtin reaches every scope, a module's included (round 147) — `Double.pi.i` from `modules/Complex.swt` means something to the importer |
| *nothing to export* | the member goes to the type; `export let T.m` is refused |

## Printing and re-entry (§3d)

`.String()` is a value's source form, and for a user type that is its
constructor as written — `Point(x: 3, y: 4)`, `Shape.circle(r: 2.5)` —
which `eval` reads back wherever the type is declared. `print`,
interpolation, the REPL, and a container's elements all show that
text; `.String(.pretty)` breaks it one member per line (round 118).

```swift
struct Point { var x: Int = 0; var y: Int = 0 }
Point(x: 3, y: 4).String()                  // "Point(x: 3, y: 4)"
eval(Point(x: 3, y: 4).String())! == Point(x: 3, y: 4)   // true
[Point(x: 1, y: 1)].String()                // "[Point(x: 1, y: 1)]"
Point(x: 3, y: 4).String(.sion)             // "Point(x: 3, y: 4)" — SION is the same source text
```

A `String` member takes the text over (rounds 151–152) — everywhere
the value prints, as Swift's `description` would — while
`.description` and `.String(.canonical)` stay the builtin memberwise
text, so a member may fall back on them (round 153). The data formats
stop at the language's own values: `.String(.json)` and
`.String(.propertyList)` on a user type are type errors (`a Point has
no JSON form`), since JSON has no Point.

## Equality, hashing, order

Every struct and enum is Equatable and Hashable from birth: `==` is
structural (case and payloads for an enum, every property for a
struct), and a value is a Dictionary key or a Set element by the same
rule (round 149's Rational is one). Order is not synthesized — `<`
between two Points is a type error until the type declares `infix(<)`,
and then `>`, `<=`, `>=` follow (Swift's derivation), as do `sorted()`,
`min()`, `max()` and `.conforms(to: Comparable)`. `==` across types is
a type error, not `false`: `Point() == 1` does not compare.

```swift
struct V { var n: Int = 0; infix(<) = { a, b in a.n < b.n } }
V.conforms(to: Equatable)                   // true — every type does
V.conforms(to: Comparable)                  // true — by its <
[V(n: 2), V(n: 1)].sorted() == [V(n: 1), V(n: 2)]   // true
V(n: 1) >= V(n: 1)                          // true — derived from <
Set([V(n: 1), V(n: 1)]).count               // 1
V.conforms(to: Sequence)                    // false — no user type is a Sequence
```

The protocols are the four of [toplevel.md](toplevel.md) — `Equatable`,
`Hashable`, `Comparable`, `Sequence` — and a user type conforms to the
first two always, to the third by `infix(<)`, to the fourth never; there
is no protocol declaration of one's own.

## Across modules

`export struct` and `export enum` make a type importable
([module.md](module.md), round 100); the importer's `Point` is the
module's, so values cross and `.String()` round-trips on either side.
`import M from "..."` binds `M` as a type whose statics are the exports
(round 184): `M.Type` is `Function`, `M.area(3.0, 4.0)` calls through,
and `extension M { static let ... }` adds to it. An extension of a
builtin declared in a module is the importer's too (round 147); an
extension of the module's own struct is the type's wherever the type
goes.

## At the REPL

`:r struct T { ... }` and `:r enum T { ... }` redefine a type in place,
`:r extension T { ... }` and `:r let T.m = { ... }` overwrite members,
`:d T` undefines (round 141); completion knows a type's properties,
methods, cases and statics. The transcripts are in Status.md.
