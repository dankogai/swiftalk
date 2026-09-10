# modules

Libraries written *in* swiftalk, imported with `import (Name) from
"./modules/Name.swt"` (see [doc/module.md](../doc/module.md)). Each is
checked by the test suite.

* **[Complex.swt](Complex.swt)** — C++'s `std::complex<double>` (round
  147): a struct with the arithmetic operators (either side may be a
  scalar), `abs`/`arg`/`norm`/`conj`/`proj` as properties and as
  statics, `polar`, and the exponential, logarithmic, trigonometric,
  and hyperbolic functions as statics (`Complex.exp(z)`). `z.i` is
  `z * i`, and `extension Double { var i }` makes `Double.pi.i` read.
  Written with rounds 143–146: statics, `Self`, and operator members.
