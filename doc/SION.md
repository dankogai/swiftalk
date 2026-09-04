# SION

[SION](https://github.com/dankogai/swift-sion) — JSON in Swift's
literal syntax — is swiftalk's native data format, and since round 97
a built-in: **a "SION value" is any value SION can carry** (§3b: `nil`,
Bool, Int, Double, String, Data, Date, and Arrays/Dictionaries of
them, with *any* key). There is no box. `SION(text)` returns the Array
or Dictionary itself, and every such value's `.String()` *is* its
SION text — the round-trip law `eval(x.String()) == x` (§3d) and
"SION reads what swiftalk writes" are the same fact.

| Form | Meaning |
|---|---|
| `SION(text)`, `text.SION()` | read a SION document: one value; comments, `0x`/`_` numbers, hex floats, Swift's escapes, `"""` — swiftalk's own lexer reads it, and only literal forms are admitted, so a document is data, never code |
| `SION(v)` | a value SION can carry, as it is; a Function, Task, Regex… is a type error |
| `v.String()`, `v.String(.sion)` | the SION text (what the REPL echoes) |
| `SION(json: text)` | read JSON (RFC 8259): `null` → nil, numbers → Int when they fit and have no fraction or exponent, else Double; objects → Dictionaries with String keys |
| `v.String(.json)` | write JSON — canonical (keys sorted), **lossy where JSON is poorer**: Data → a base64 String, Date → the epoch as a number, a non-String key → its `String()`; an infinite or NaN Double is an error |
| `SION(propertyList: text)` | read an XML property list (`<plist>`, `<dict>`/`<key>`, `<array>`, `<string>`, `<integer>`, `<real>`, `<true/>`, `<false/>`, `<date>` ISO 8601, `<data>` base64; entities; comments) |
| `v.String(.propertyList)` | write one, Apple's layout — keys sorted, tabs; **nil and non-String keys are errors** (property lists have neither) |
| `SION(propertyList: data)` | read Apple's binary form, `bplist00` |
| `v.Data(.propertyList)` | write it |
| `let x: SION = ...` | the annotation (round 59) still names the union — a mixed-key Dictionary, say, needs it under strict inference |

A document that does not parse is a **type error with a position**,
not `nil`: `nil` is itself a legal SION value, so it cannot mean
"failed". Each format refuses what it cannot carry rather than
dropping it silently — `[nil].String(.propertyList)` is an error, not
an empty list.

```swift
let doc: SION = SION("""
    ["name": "swiftalk", "when": .Date(0x0p+0), "bytes": .Data("AQID"),
     nil: "any key", 1.0: "goes"]     // comments too
    """)
doc.String()                          // the same document back, keys sorted
doc.String(.json)                     // {"1.0":"goes","bytes":"AQID","name":"swiftalk","nil":"any key","when":0.0}
let p: SION = ["n": 42, "tags": ["a", "b"]]
SION(propertyList: p.String(.propertyList)) == p     // true
SION(propertyList: p.Data(.propertyList)) == p       // true — bplist00, plutil-verified
```

msgPack and YAML: later.
