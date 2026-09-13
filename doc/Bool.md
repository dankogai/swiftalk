# Bool

`true` and `false`. Nothing is truthy: `if`, `while`, `? :`, and
`filter` demand a Bool and reject everything else (§3b). The one
reading that is not a Bool test: a *bare variable* as an `if`/`while`
condition asks "not nil?" when it holds anything but a Bool — `if o {
o + 1 }` (round 80) — and inside, `o` is itself.

| Member / constructor | Result |
|---|---|
| `Bool()` | `false` |
| `Bool(b)` | `b` |
| `Bool("true")`, `Bool("false")` | the value; any other String → `nil` (failable) |
| `Bool(i)` for an Int | `false` for 0, `true` otherwise (round 105) — a conversion, not truthiness: `if 3 { }` is still an error |
| `Bool(x)` for other types | type error |
| `b == c`, `b != c` | equality |
| `b &&= c`, `b ||= c` | `b = b && c` / `b = b || c`, short-circuit: `c` is evaluated only when `b` does not decide (round 104) |
| `b ^^ c`, `b ^^= c` | logical xor (round 106): true when exactly one is; both sides evaluated; sits between `&&` and `||` |
| `b.not()`, `b.and(c)`, `b.or(c)`, `b.xor(c)` | `!`, `&&`, `||`, `^^` as methods (round 106) — eager: a method evaluates its argument, `&&`/`||` do not always. An Int's bitwise set is `bitNot`/`bitAnd`/`bitOr`/`bitXor` (round 107) |
| `c ? a : b` | ternary (the `?` must be spaced; unspaced `?` is postfix propagate) |
| `a && b` | logical and — short-circuit, Bool operands only (round 69) |
| `a \|\| b` | logical or — short-circuit, Bool operands only |
| `!a` | logical not (prefix; postfix `!` is force-unwrap) |
| `not a`, `a and b`, `a or b`, `a xor b` | **the word operators** (round 155) — the same operations as `!`, `&&`, `\|\|`, `^^` (short-circuit alike), at the bottom of the precedence table where Perl and Ruby put them: `not 1 == 2` is `not (1 == 2)`, `a or b and c` is `a or (b and c)`, `a ? b : c or d` is `(a ? b : c) or d`. Keywords: `let and = 1` is an error; `b.and(c)` the method is untouched |

```swift
1 < 2               // true
Bool("yes")         // nil
true ? "y" : "n"    // "y"
```

## Logical operations

Two spellings of one set of operations — Swift's symbols and Perl's
words (round 155). Every one takes Bools only: nothing is truthy, so
`1 && true`, `1 and true`, and `not 1` are type errors.

| Symbol | Word | Operation | Evaluation |
|---|---|---|---|
| `!a` | `not a` | negation | — |
| `a && b` | `a and b` | conjunction | `b` only when `a` is true |
| `a \|\| b` | `a or b` | disjunction | `b` only when `a` is false |
| `a ^^ b` | `a xor b` | exclusive or | both sides, always |
| `a &&= b`, `a \|\|= b`, `a ^^= b` | — | in place (round 104, 106) | as the operators |
| `a.not()`, `a.and(b)`, `a.or(b)`, `a.xor(b)` | — | as methods (round 106) | eager — a method evaluates its argument |

**Precedence**, tightest to loosest. The symbols are Swift's: `!`
is a prefix, then `??` and the comparisons, then `&&`, `^^`, `||`,
then the ternary `? :`. The words are Perl's and Ruby's: all of them
sit *below* the ternary — `not` first, `and` looser, `or` and `xor`
loosest, left-associative and on one level — so a word never needs
parentheses around a symbolic expression on either side:

```swift
not 1 == 2                     // not (1 == 2) — true; !1 == 2 would be a type error
a > 0 and b > 0 or c           // (a > 0 and b > 0) or c
true or true xor true          // (true or true) xor true — false; one level, left to right
x ?? false and y               // (x ?? false) and y
c ? a : b or d                 // (c ? a : b) or d — Perl's reading; the middle may hold anything
not c ? a : b                  // not (c ? a : b) — write (not c) ? a : b for the other
```

`!` and the words are the same operators inside — the same Expr, the
same errors (an error names the symbol). The words are keywords:
`let and = 1` is a syntax error, `b.and(c)` the method is not. A word
at a line's end continues the line, as `&&` does; a leading `and`/
`or`/`xor` with a space after it continues the line too, a leading
`not` begins a statement. There is no `and=`: the `op=` family is the
symbols'. A lone `&` or `|` is a Set operator (round 135), a type
error on Bools.

```swift
false && probe()          // probe never runs
false and probe()         // nor here
d["k"] != nil && d["k"]! > 0
!true == false            // true — (!true) == false
not true == false         // false — not (true == false)
```
