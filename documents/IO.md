# IO

**Prelude** — the `IO` module, preimported by the CLI (`--no-prelude` skips it); `import from "IO"` otherwise, or `Interpreter.preimport(["IO"])`.

Output, input, and files (round 191; `print` and `debugPrint` alone
from round 185, the core's before). `IO` is both the module and a
**type**: a handle on a file descriptor. `import from "IO"` binds
`print`, `debugPrint`, `readLine`, and the type; `import IO from "IO"`
binds the namespace, whose `IO.IO` is the type. Where `print` goes is
the host's — `Interpreter.output`, stdout by default; `debugPrint`
goes to `Interpreter.errorOutput`, **stderr** by default.

| Function | Meaning |
|---|---|
| `print(x, ...)` | each value's display text, space-separated, newline-terminated, to the output; `nil`. A String is bare, everything else is its `.String()` — a type's own `String` member speaks (round 152). `print()` writes an empty line |
| `debugPrint(x, ...)` | the same with each value's `debugDescription` — quoted Strings, signed hex numbers, a struct's memberwise form — to the **error output** (round 191) |
| `readLine()` | the next line of stdin without its `\n` or `\r\n`, `nil` at EOF — `IO.stdin.readLine()` |

| Handle | Meaning |
|---|---|
| `IO(path: p)`, `IO(path: p, mode: .read)` | a handle on the file at `p`, open to read. Modes: `.read` (the default), `.write` (create or truncate), `.append` (create, write at the end), `.readWrite` (create, both ways). The writing modes open read-write underneath, so `.data` reads back; a missing file, a bad mode, is an **error** — a handle is an object you hold, not a Result (POSIX has the descriptor-level answers, [POSIX.md](POSIX.md)) |
| `IO.stdin`, `IO.stdout`, `IO.stderr` | the three standard handles, statics; never closed |
| `fh.data` | the **whole content**, a Data, from the start (`fh.data.String(.utf8)` for its text); an error when the descriptor is not seekable — read a pipe or stdin with `.lines` or `.read(size)` |
| `fh.data = x` | **replaces** the content: truncate, then write `x` (a Data or a String); an error when not seekable or not writable |
| `fh.lines` | a lazy Sequence of the lines without their newlines, **from where the handle is** — `for line in fh.lines { }`, `.Array()`, `.map`, `.prefix`; iterating it twice reads on, not again |
| `fh.read(size)`, `fh.read()` | a lazy Sequence of Data chunks of `size` bytes (the last shorter; 65536 by default), from where the handle is |
| `fh.readLine()` | one line, `nil` at EOF |
| `fh.write(x)` | writes a Data or a String at the current position; the bytes written |
| `fh.append(x)` | the same at the end of the file |
| `fh.print(x, ...)` | `print`'s text to the handle — `IO.stderr.print("careful")` |
| `fh.close()`, `fh.isClosed` | closes the descriptor (the standard three are only marked); a closed handle refuses everything else |
| `fh.fd`, `fh.path`, `fh.mode` | the descriptor (Int), the path (`nil` for the standard three), the mode's name |
| `fh.Type`, `fh == g`, `fh.String()` | `IO`; identity — two handles on one file are two; `IO(path: "notes.txt", mode: .read)` or `IO.stdin` |

A handle **owns its descriptor and closes it when the value dies** —
the Swift object behind it goes away with its last reference. Reads
are buffered per handle, so `lines`, `read`, and `readLine` may be
mixed on one handle.

```swift
var fh = IO(path: "notes.txt", mode: .write)
fh.write("one\ntwo\n")                          // 8
fh.append("three\n")                             // 6
fh.data.String(.utf8)                            // "one\ntwo\nthree\n"
IO(path: "notes.txt").lines.Array()              // ["one", "two", "three"]
for chunk in IO(path: "notes.txt").read(5) { print(chunk.count) }   // 5 5 4
fh.data = "replaced\n"
IO.stderr.print("to stderr")
let name = readLine()                            // a line of stdin, or nil
IO.stdin.data                                    // error: not seekable — read it with .lines or .read(size)
```

The module is a hundred lines of Swift over the module API
([module.md](module.md)): a `HostValue` for the handle with
`setMember` for `data =`, `Swiftalk.sequence` for `lines` and `read`,
`Module.static` for the three handles, `Swiftalk.output` and
`errorOutput` for the two prints.
