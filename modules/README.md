# modules

Libraries written *in* swiftalk, imported with `import from
"./modules/Name.swt"` — every export by its own name (round 148); or
`import (Name) from` for a named few, `import M from` for a namespace
(see [documents/module.md](../documents/module.md)). Each is checked by the test
suite. Since round 182 a directory here may instead be a **native
module** written in Swift — a target of the root package built as
`lib<name>.dylib` and imported by its bare name, `import from "env"`.

* **[env/](env/EnvModule.swift)** — the process environment, and the
  worked example of a native module (round 182): `get(name)` (nil
  when unset), `set(name, value)`, `unset(name)`, `all()` (a `[String:
  String]`), the constant `platform`; sixty lines showing functions
  over Values, an error, a constant, and the one C entry point.

* **[Complex.swt](Complex.swt)** — C++'s `std::complex<double>` (round
  147): a struct with the arithmetic operators (either side may be a
  scalar), `abs`/`arg`/`norm`/`conj`/`proj` as properties and as
  statics, `polar`, and the exponential, logarithmic, trigonometric,
  and hyperbolic functions as statics (`Complex.exp(z)`). `z.i` is
  `z * i`, and `extension Double { var i }` makes `Double.pi.i` read.
  A Complex prints as `(1.0-2.0.i)` (round 154) — an expression that
  re-enters as written — and `Complex("(1.0-2.0.i)")` reads it back, as
  do `"3.0"`, `"2.0.i"`, and `.String(.hex)`'s text; `z.description`
  and `z.String(.canonical)` are `Complex(real: 1.0, imag: -2.0)`.
  Written with rounds 143–146: statics, `Self`, and operator members.
* **[Rational.swt](Rational.swt)** — exact fractions of Ints (round
  149): normalized on construction (reduced, the sign in `num`), so
  equality is structural and a Rational is a Dictionary key; from two
  Ints, an Int, a Double (exactly — `Rational(0.1)` is the binary
  fraction the Double is), a `"n/d"` String, or a Rational; `+ - * /
  **`, `-`, `==`, `<` (Ints lift, a Double on either side makes a
  Double); `abs`, `sign`, `reciprocal`, `floor`, `ceil`, `rounded`,
  `truncated`, `mixed`, `fraction`, `isInteger`; `.Double()`/`Double(r)`,
  `.Int()`/`Int(r)` (round 151); a Rational prints as `(3/4)` wherever
  it appears — `print`, `"\(r)"`, `[r]`, the REPL (round 152) — and
  `.String(.hex)` is `(0x3/0x4)`, a format reaching both Ints;
  `Rational("(3/4)")` and `Rational("(0x3/0x4)")` read them back;
  `r.description` and `r.String(.canonical)` are the memberwise
  `Rational(num: 3, den: 4)`; `3.Rational()`, `1.over(3)` (round 153).
  Zero denominators and overflow are Int's own errors.
