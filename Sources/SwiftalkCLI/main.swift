import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The CLI's module loader (round 100): files through the core's POSIX
/// read; `http://`/`https://` through `curl -fsSL`, spawned without
/// Foundation — "urls like https:// are okay so long as CORS allows".
func loadModule(_ spec: String) throws -> String {
    guard spec.hasPrefix("http://") || spec.hasPrefix("https://") else {
        return try Swiftalk.Interpreter.readModule(at: spec)
    }
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { throw Swiftalk.Error.type("cannot fetch '\(spec)': pipe failed") }
    #if canImport(Darwin)
    var actions: posix_spawn_file_actions_t? = nil      // an opaque pointer on Darwin
    #else
    var actions = posix_spawn_file_actions_t()
    #endif
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
    posix_spawn_file_actions_addclose(&actions, fds[0])
    posix_spawn_file_actions_addclose(&actions, fds[1])
    var argv: [UnsafeMutablePointer<CChar>?] = []
    for a in ["curl", "-fsSL", spec] { argv.append(strdup(a)) }
    argv.append(nil)
    defer { for p in argv { free(p) } }
    var pid: pid_t = 0
    let rc = posix_spawnp(&pid, "curl", &actions, nil, argv, nil)
    posix_spawn_file_actions_destroy(&actions)
    close(fds[1])
    guard rc == 0 else {
        close(fds[0])
        throw Swiftalk.Error.type("cannot fetch '\(spec)': curl is not available (\(rc))")
    }
    var data: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = read(fds[0], &chunk, chunk.count)
        guard n > 0 else { break }
        data.append(contentsOf: chunk[0..<n])
    }
    close(fds[0])
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    guard status == 0 else { throw Swiftalk.Error.type("cannot fetch '\(spec)' (curl exit \(status >> 8))") }
    return String(decoding: data, as: UTF8.self)
}

// Milestone 1: the REPL — a read–eval–print loop around eval()
// (Design.md §13). Relaxed mode is on: bare `x = 1` declares a var
// (§2.2). The printer is .String() source form, so every echo obeys
// the round-trip law (§3d): what you see re-enters as what it was.

// Script mode (round 66): `swiftalk file.swt` evaluates the whole
// file as ONE strict program (§2.2 file mode — no relaxed bare
// assignment), echoes nothing, and outputs only what print() prints.
if CommandLine.arguments.count > 1 {
    let path = CommandLine.arguments[1]
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
let isTTY = isatty(0) != 0
// On a terminal, LineEditor (round 64) supplies raw-mode editing,
// arrow-key history, and ~/.swiftalk_history; pipes keep plain reads.
let editor: LineEditor? = isTTY ? LineEditor() : nil

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
