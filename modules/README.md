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
