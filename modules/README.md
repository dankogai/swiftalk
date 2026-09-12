# modules

Libraries written *in* swiftalk, imported with `import from
"./modules/Name.swt"` — every export by its own name (round 148); or
`import (Name) from` for a named few, `import M from` for a namespace
(see [doc/module.md](../doc/module.md)). Each is checked by the test
suite.

* **[Complex.swt](Complex.swt)** — C++'s `std::complex<double>` (round
  147): a struct with the arithmetic operators (either side may be a
  scalar), `abs`/`arg`/`norm`/`conj`/`proj` as properties and as
  statics, `polar`, and the exponential, logarithmic, trigonometric,
  and hyperbolic functions as statics (`Complex.exp(z)`). `z.i` is
  `z * i`, and `extension Double { var i }` makes `Double.pi.i` read.
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
