import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Runs curl with `args` (round 100's spawn, generalized in round 163):
/// stdout comes back as bytes; `input`, if any, goes to curl's stdin.
/// No Foundation — posix_spawn and pipes.
func runCurl(_ args: [String], input: [UInt8]? = nil) throws -> [UInt8] {
    var out: [Int32] = [0, 0]
    var inp: [Int32] = [0, 0]
    guard pipe(&out) == 0, pipe(&inp) == 0 else { throw Swiftalk.Error.type("curl: pipe failed") }
    #if canImport(Darwin)
    var actions: posix_spawn_file_actions_t? = nil      // an opaque pointer on Darwin
    #else
    var actions = posix_spawn_file_actions_t()
    #endif
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_adddup2(&actions, out[1], 1)
    posix_spawn_file_actions_adddup2(&actions, out[1], 2)      // curl's own message rides along; it is the error text on failure
    posix_spawn_file_actions_adddup2(&actions, inp[0], 0)
    for fd in [out[0], out[1], inp[0], inp[1]] { posix_spawn_file_actions_addclose(&actions, fd) }
    var argv: [UnsafeMutablePointer<CChar>?] = []
    for a in ["curl"] + args { argv.append(strdup(a)) }
    argv.append(nil)
    defer { for p in argv { free(p) } }
    var pid: pid_t = 0
    let rc = posix_spawnp(&pid, "curl", &actions, nil, argv, nil)
    posix_spawn_file_actions_destroy(&actions)
    close(out[1])
    close(inp[0])
    guard rc == 0 else {
        close(out[0]); close(inp[1])
        throw Swiftalk.Error.type("curl is not available (\(rc))")
    }
    if let input, !input.isEmpty {
        _ = input.withUnsafeBufferPointer { write(inp[1], $0.baseAddress, $0.count) }
    }
    close(inp[1])
    var data: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = read(out[0], &chunk, chunk.count)
        guard n > 0 else { break }
        data.append(contentsOf: chunk[0..<n])
    }
    close(out[0])
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    guard status == 0 else {
        let message = String(decoding: data, as: UTF8.self).split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).last.map(String.init) ?? ""
        throw Swiftalk.Error.type(message.isEmpty ? "curl exit \(status >> 8)" : message)
    }
    return data
}

/// The CLI's module loader (round 100): files through the core's POSIX
/// read; `http://`/`https://` through `curl -fsSL` — "urls like
/// https:// are okay so long as CORS allows".
func loadModule(_ spec: String) throws -> String {
    guard spec.hasPrefix("http://") || spec.hasPrefix("https://") else {
        return try Swiftalk.Interpreter.readModule(at: spec)
    }
    do {
        return String(decoding: try runCurl(["-fsSL", spec]), as: UTF8.self)
    } catch let error as Swiftalk.Error {
        throw Swiftalk.Error.type("cannot fetch '\(spec)': \(error.description)")
    }
}

// Milestone 1: the REPL — a read–eval–print loop around eval()
// (Design.md §13). Relaxed mode is on: bare `x = 1` declares a var
// (§2.2). The printer is .String() source form, so every echo obeys
// the round-trip law (§3d): what you see re-enters as what it was.

// Script mode (round 66): `swiftalk file.swt` evaluates the whole
// file as ONE strict program (§2.2 file mode — no relaxed bare
// assignment), echoes nothing, and outputs only what print() prints.
/// The directory the running executable lives in — where a dev build's
/// module libraries sit beside it (round 182). dladdr on this image's
/// own handle names its file on Darwin; Linux reads /proc/self/exe
/// (dladdr is a GNU extension Swift's Glibc does not expose).
func executableDirectory() -> String? {
    #if canImport(Darwin)
    var info = Dl_info()
    guard dladdr(#dsohandle, &info) != 0, let name = info.dli_fname else { return nil }
    let path = String(cString: name)
    #else
    var buffer = [CChar](repeating: 0, count: 4096)
    let n = readlink("/proc/self/exe", &buffer, buffer.count - 1)
    guard n > 0 else { return nil }
    let path = String(cString: buffer)
    #endif
    guard let slash = path.lastIndex(of: "/") else { return nil }
    return String(path[..<slash])
}

/// Where `import from "Name"` looks for `libName.dylib` (round 182):
/// `SWIFTALK_MODULE_PATH` (colon-separated) when set, else beside the
/// executable and in the `lib/` next to its `bin/`.
let defaultModulePath: [String] = {
    if let raw = getenv("SWIFTALK_MODULE_PATH") {
        return String(cString: raw).split(separator: ":").map(String.init)
    }
    guard let dir = executableDirectory() else { return [] }
    return [dir, dir + "/../lib"]
}()

/// The CLI's prelude (rounds 185–186): the core's IO and Net, then the
/// Regex module from the module path — without it the CLI still runs,
/// says so once, and `/re/` literals are errors when evaluated.
func installPrelude(_ interp: Swiftalk.Interpreter) throws {
    try interp.preimport()
    do {
        try interp.preimport(["Regex"])
    } catch {
        let msg = "swiftalk: no Regex module on the module path — /re/ literals will not evaluate (\(error))\n"
        _ = Array(msg.utf8).withUnsafeBufferPointer { write(2, $0.baseAddress, $0.count) }
    }
}

/// Options (round 187): `--no-prelude` starts the interpreter bare — no
/// IO, Net, or Regex; `import from "IO"` brings what a script wants.
/// `--help` says so. Options come before the script path; everything
/// after the path is the script's.
let usage = """
    usage: swiftalk [--no-prelude] [file.swt]
      --no-prelude   start without the prelude modules (IO, Net, Regex): only eval at the top level
      --help, -h     this message
    With no file, the REPL — :h for its commands.

    """
var loadPrelude = true
var scriptPath: String? = nil
var arguments = CommandLine.arguments.dropFirst()
while let arg = arguments.first {
    switch arg {
    case "--no-prelude":
        loadPrelude = false
        arguments = arguments.dropFirst()
    case "--help", "-h":
        print(usage, terminator: "")
        exit(0)
    case "--":
        arguments = arguments.dropFirst()
        scriptPath = arguments.first
        arguments = []
    default:
        if arg.hasPrefix("-"), arg.count > 1 {
            let msg = "swiftalk: unknown option '\(arg)'\n" + usage
            _ = Array(msg.utf8).withUnsafeBufferPointer { write(2, $0.baseAddress, $0.count) }
            exit(2)
        }
        scriptPath = arg
        arguments = []
    }
}

if let path = scriptPath {
    let fd = open(path, O_RDONLY)
    guard fd >= 0 else {
        let msg = "swiftalk: cannot open '\(path)'\n"
        _ = Array(msg.utf8).withUnsafeBufferPointer { write(2, $0.baseAddress, $0.count) }
        exit(1)
    }
    var data: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = read(fd, &chunk, chunk.count)
        guard n > 0 else { break }
        data.append(contentsOf: chunk[0..<n])
    }
    close(fd)
    do {
        let interp = Swiftalk.Interpreter()
        interp.scriptPath = path                     // `import` resolves beside the script (round 100)
        interp.moduleLoader = loadModule
        interp.modulePath = defaultModulePath         // round 182
        if loadPrelude { try installPrelude(interp) }  // rounds 185–186: IO, Net, Regex; --no-prelude skips
        _ = try interp.eval(String(decoding: data, as: UTF8.self))
    } catch let error as Swiftalk.Error {
        let msg = "\(path): \(error.description)\n"
        _ = Array(msg.utf8).withUnsafeBufferPointer { write(2, $0.baseAddress, $0.count) }
        exit(1)
    }
    exit(0)
}

let interpreter = Swiftalk.Interpreter(relaxed: true)
interpreter.moduleLoader = loadModule            // URLs via curl, files directly
interpreter.modulePath = defaultModulePath       // native modules beside the executable (round 182)
if loadPrelude {                                  // the prelude (rounds 185–186): IO, Net, Regex; --no-prelude skips
    do { try installPrelude(interpreter) } catch {
        let msg = "swiftalk: prelude failed: \(error)\n"
        _ = Array(msg.utf8).withUnsafeBufferPointer { write(2, $0.baseAddress, $0.count) }
        exit(1)
    }
}
let isTTY = isatty(0) != 0
// On a terminal, LineEditor (round 64) supplies raw-mode editing,
// arrow-key history, and ~/.swiftalk_history; pipes keep plain reads.
let editor: LineEditor? = isTTY ? LineEditor() : nil
editor?.completer = { interpreter.complete($0) }   // Tab (round 164)

// The continuation prompt is two quiet spaces (round 63) — dots were
// noise. (Recommended indent in .swt files is 4 spaces.)
let nextLine: (_ continued: Bool) -> LineEditor.ReadResult = { continued in
    guard let editor else {
        return readLine().map { .line($0) } ?? .eof
    }
    return editor.readLine(prompt: continued ? "  " : "swiftalk> ")
}

/// REPL commands (round 131), `swift repl`'s style: a line starting
/// with `:`. Three for now.
let help = """
    :h              this help
    :r let x = ...  redefine a top-level let or var — the old binding is replaced, whatever its type or mutability
    :r struct P {}  redefine a struct or enum (existing values keep the old type)
    :r extension T {}  add to a type, overwriting members of the same name
    :d x            undefine a top-level binding — a let, var, struct, or enum
    """
@MainActor func runCommand(_ line: String) {
    let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let command = String(parts[0])
    let rest = parts.count > 1 ? String(parts[1]).trimmed : ""
    do {
        switch command {
        case ":h":
            print(help)
        case ":r":
            guard !rest.isEmpty else { print("usage: :r let x = ..."); return }
            let value = try interpreter.redefine(rest)
            if value != .nil { print(try interpreter.sourceText(value)) }
        case ":d":
            guard !rest.isEmpty, !rest.contains(" ") else { print("usage: :d name"); return }
            try interpreter.undefine(rest)
        default:
            print("unknown command \(command) — :h for help")
        }
    } catch let error as Swiftalk.Error {
        print(error.description)
    } catch {
        print("error: \(error)")
    }
}

var buffer = ""
loop: while true {
    switch nextLine(!buffer.isEmpty) {
    case .eof:
        break loop
    case .interrupted:       // ^C cancels the whole pending statement
        buffer = ""
    case .line(let line):
        editor?.remember(line)
        buffer += buffer.isEmpty ? line : "\n" + line
        if buffer.trimmed.isEmpty {
            buffer = ""
            continue
        }
        if Swiftalk.needsMoreInput(buffer) {
            continue
        }
        if buffer.trimmed.hasPrefix(":") {             // a REPL command (round 131)
            runCommand(buffer.trimmed)
            buffer = ""
            continue
        }
        do {
            let value = try interpreter.eval(buffer)
            // nil echoes are suppressed (the Python way): statements —
            // loops, if, print(...) — all evaluate to nil; echoing it
            // is noise.
            if value != .nil {
                print(try interpreter.sourceText(value))
            }
        } catch let error as Swiftalk.Error {
            print(error.description)
        } catch {
            print("error: \(error)")
        }
        buffer = ""
    }
}

extension String {
    var trimmed: String {
        String(drop(while: { $0 == " " || $0 == "\t" }))
    }
}
