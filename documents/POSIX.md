# POSIX

The process environment and file I/O — a native module (round 188;
the `Env` module of rounds 182–183 grown up), `modules/POSIX`, built as
`libPOSIX.dylib` beside the CLI. **Not in the prelude**: `import from
"POSIX"` binds every function, `import POSIX from "POSIX"` the
namespace (`POSIX.open`), `import (readFile) from "POSIX"` a few.
Every function keeps its C name. **What can fail answers a `Result`**
— `.success(value)` or `.failure("open(x): No such file or directory")`,
strerror's words — so `open(path)!` traps, `?` propagates, `??`
defaults, `.then`/`.catch` chain, exactly as `fetch`'s answer does
([Net.md](Net.md), [Result.md](Result.md)). Wrong arguments to the
call itself are the caller's type errors. Flags are Ints; since `|` is
swiftalk's Set operator, `open` and `mkdir` take **an Int or an Array
of Ints** ORed together: `open(path, [O_WRONLY, O_CREAT, O_TRUNC])`.

| Function | Result |
|---|---|
| `getenv(name)` | the variable's value, or `nil` when unset (no Result: nil is the answer) |
| `setenv(name, value)`, `unsetenv(name)` | `.success(nil)` |
| `environ()` | every variable, a `[String: String]` |
| `getpid()` | the process id (cannot fail) |
| `getcwd()`, `chdir(path)` | the working directory; `.success(nil)` |
| `uname()` | `.success` of a Dictionary: `sysname` (`"Darwin"`, `"Linux"`), `nodename`, `release`, `version`, `machine` |
| `exit(code)` | ends the process, `code` defaulting to 0 — no return |
| `open(path)`, `open(path, flags)`, `open(path, flags, mode)` | a descriptor (Int); flags default to `O_RDONLY`, mode to `0o644` |
| `close(fd)` | `.success(nil)` |
| `read(fd)`, `read(fd, count)` | `.success` of a Data — up to `count` bytes (65536 by default), empty at EOF |
| `write(fd, data)` | `data` a Data or a String (its UTF-8); `.success` of the bytes written |
| `lseek(fd, offset)`, `lseek(fd, offset, whence)` | the new position; `whence` defaults to `SEEK_SET` |
| `readFile(path)` | the whole file, a Data — `readFile(p)!.String(.utf8)` for its text |
| `writeFile(path, contents)` | creates or truncates, writes a Data or a String; `.success` of the bytes written |
| `stat(path)` | `.success` of a Dictionary: `size`, `mode` (the permission bits), `uid`, `gid`, `nlink`, `mtime`/`atime`/`ctime` (Dates), `isFile`, `isDirectory`, `isSymlink` |
| `readdir(path)` | the entries' names, a `[String]` without `.` and `..` |
| `mkdir(path)`, `mkdir(path, mode)` | `.success(nil)`; mode defaults to `0o755` |
| `rmdir(path)`, `unlink(path)`, `rename(from, to)` | `.success(nil)` |
| `O_RDONLY` `O_WRONLY` `O_RDWR` `O_CREAT` `O_TRUNC` `O_APPEND` `O_EXCL` | open flags, the platform's values |
| `SEEK_SET` `SEEK_CUR` `SEEK_END` | for `lseek` |
| `STDIN_FILENO` `STDOUT_FILENO` `STDERR_FILENO` | 0, 1, 2 |

```swift
import from "POSIX"
writeFile("notes.txt", "hello\n")!               // 6
let fd = open("notes.txt", [O_WRONLY, O_APPEND])!
write(fd, "world\n")
close(fd)
readFile("notes.txt")!.String(.utf8)             // "hello\nworld\n"
stat("notes.txt")!["size"]                       // 12
readdir(".")!.contains("notes.txt")              // true
readFile("nowhere.txt")                          // Result.failure("readFile(nowhere.txt): No such file or directory")
readFile("nowhere.txt") ?? Data()                // .Data("")
let text = { path in readFile(path)?.String(.utf8) }   // ? hands the failure up
```

The namespace is a type (round 184): `extension POSIX { static let
home = { POSIX.getenv("HOME") } }` adds to it. Not (yet): `fcntl`,
`dup`, pipes and `posix_spawn`, symlinks and `lstat`, `chmod`,
`utimes`, sockets — each a function away, in `modules/POSIX`.
