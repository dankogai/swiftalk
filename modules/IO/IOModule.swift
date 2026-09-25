import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// `IO` — output, input, and files (round 191; `print` and `debugPrint`
// alone from round 185, the core's before). Preimported by the CLI.
//
//     print(1, "two")                    // stdout — Interpreter.output
//     debugPrint("two")                  // stderr — Interpreter.errorOutput (round 191)
//     let name = readLine()              // one line of stdin, nil at EOF
//     IO.stdin, IO.stdout, IO.stderr     // the three handles
//     var fh = IO(path: "notes.txt")     // .read by default; .write, .append, .readWrite
//     fh.data                            // the whole file, a Data
//     fh.data = "replaced\n"             // truncate and write (a seekable file)
//     for line in fh.lines { }           // lazily, from where the handle is
//     for chunk in fh.read(4096) { }     // Data chunks
//     fh.append("more\n"); fh.write(x); fh.print(x, y); fh.readLine(); fh.close()
//     IO.stderr.print("careful")
//
// A handle owns its descriptor and closes it when the value dies; the
// three standard handles are never closed. Failures are errors — a
// missing file, an unseekable `data` — not Results: a handle is an
// object you hold, and POSIX has the descriptor-level answers.

final class Handle: Swiftalk.HostValue {
    let fd: Int32
    let path: String?
    let mode: String
    let type: Swiftalk.Value
    private let owned: Bool
    private var closed = false
    private var buffer: [UInt8] = []

    init(fd: Int32, path: String?, mode: String, owned: Bool, type: Swiftalk.Value) {
        self.fd = fd; self.path = path; self.mode = mode; self.owned = owned; self.type = type
    }
    deinit { if owned && !closed { close(fd) } }

    var typeName: String { "IO" }
    private var label: String { path.map { "IO(path: \"\($0)\")" } ?? "IO.\(["stdin", "stdout", "stderr"][Int(fd)])" }

    private func live() throws {
        if closed { throw Swiftalk.Error.type("\(label) is closed") }
    }
    private func fail(_ call: String) -> Swiftalk.Error {
        .type("\(label).\(call): \(String(cString: strerror(errno)))")
    }

    // ---- reading ----

    /// One raw read into the buffer; false at EOF.
    private func fill(_ size: Int = 65536) throws -> Bool {
        try live()
        var chunk = [UInt8](repeating: 0, count: size)
        let n = read(fd, &chunk, size)
        guard n >= 0 else { throw fail("read") }
        guard n > 0 else { return false }
        buffer.append(contentsOf: chunk[0..<n])
        return true
    }

    /// The next line without its newline (`\n` or `\r\n`), nil at EOF.
    func readLine() throws -> Swiftalk.Value? {
        while true {
            if let nl = buffer.firstIndex(of: 10) {
                var line = Array(buffer[..<nl])
                buffer.removeSubrange(...nl)
                if line.last == 13 { line.removeLast() }
                return .string(String(decoding: line, as: UTF8.self))
            }
            if try !fill() {
                guard !buffer.isEmpty else { return nil }
                let line = buffer; buffer = []
                return .string(String(decoding: line, as: UTF8.self))
            }
        }
    }

    /// The next `size` bytes (fewer at the end), nil at EOF.
    func readChunk(_ size: Int) throws -> Swiftalk.Value? {
        while buffer.count < size {
            if try !fill(max(size, 65536)) { break }
        }
        guard !buffer.isEmpty else { return nil }
        let n = min(size, buffer.count)
        let chunk = Array(buffer[..<n])
        buffer.removeFirst(n)
        return .data(chunk)
    }

    /// The whole content, from the start — a seekable file's.
    func wholeData() throws -> Swiftalk.Value {
        try live()
        guard lseek(fd, 0, SEEK_SET) >= 0 else {
            throw Swiftalk.Error.type("\(label).data: not seekable — read it with .lines or .read(size)")
        }
        buffer = []
        var out: [UInt8] = []
        while try fill() { out.append(contentsOf: buffer); buffer = [] }
        return .data(out)
    }

    // ---- writing ----

    private func writeAll(_ bytes: [UInt8], _ call: String) throws -> Int {
        try live()
        var written = 0
        while written < bytes.count {
            let n = bytes[written...].withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
            guard n >= 0 else { throw fail(call) }
            written += n
        }
        return written
    }

    private func bytes(_ v: Swiftalk.Value, _ call: String) throws -> [UInt8] {
        switch v {
        case .data(let d):   return d
        case .string(let s): return Array(s.utf8)
        default: throw Swiftalk.Error.type("\(label).\(call) takes a Data or a String, not \(v.typeName)")
        }
    }

    func setMember(_ name: String, to value: Swiftalk.Value) throws -> Bool {
        guard name == "data" else { return false }
        try live()
        let content = try bytes(value, "data")
        guard lseek(fd, 0, SEEK_SET) >= 0 else {
            throw Swiftalk.Error.type("\(label).data: not seekable — write it with .write or .append")
        }
        guard ftruncate(fd, 0) == 0 else { throw fail("data") }
        buffer = []
        _ = try writeAll(content, "data")
        return true
    }

    func member(_ name: String, args: [Swiftalk.Value], called: Bool) throws -> Swiftalk.Value? {
        switch (name, called) {
        case ("fd", false):    return .int(Int64(fd))
        case ("path", false):  return path.map { .string($0) } ?? .nil
        case ("mode", false):  return .string(mode)
        case ("data", false):  return try wholeData()
        case ("lines", false):
            return Swiftalk.sequence { { try self.readLine() } }
        case ("read", true):
            var size = 65536
            if let first = args.first {
                guard args.count == 1, case .int(let n) = first, n > 0 else {
                    throw Swiftalk.Error.type("\(label).read(size) takes one positive Int")
                }
                size = Int(n)
            }
            return Swiftalk.sequence { { try self.readChunk(size) } }
        case ("readLine", true):
            guard args.isEmpty else { throw Swiftalk.Error.type("\(label).readLine() takes no arguments") }
            return try readLine() ?? .nil
        case ("write", true):
            guard args.count == 1 else { throw Swiftalk.Error.type("\(label).write(data) takes one Data or String") }
            return .int(Int64(try writeAll(try bytes(args[0], "write"), "write")))
        case ("append", true):
            guard args.count == 1 else { throw Swiftalk.Error.type("\(label).append(data) takes one Data or String") }
            try live()
            guard lseek(fd, 0, SEEK_END) >= 0 else { throw fail("append") }
            return .int(Int64(try writeAll(try bytes(args[0], "append"), "append")))
        case ("print", true):
            _ = try writeAll(Array((try args.map(Swiftalk.display).joined(separator: " ") + "\n").utf8), "print")
            return .nil
        case ("close", true):
            guard args.isEmpty else { throw Swiftalk.Error.type("\(label).close() takes no arguments") }
            if !closed, owned { close(fd) }
            closed = true
            return .nil
        case ("isClosed", false): return .bool(closed)
        default: return nil
        }
    }

    func isEqual(to other: any Swiftalk.HostValue) -> Bool { (other as? Handle) === self }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    func sourceString(debug: Bool) -> String {
        path.map { "IO(path: \"\($0)\", mode: .\(mode))" } ?? label
    }
}

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "IO")
    final class TypeBox { var value: Swiftalk.Value = .nil }
    let box = TypeBox()

    /// `IO(path)`, `IO(path: p, mode: .read)` — `.read` (the default),
    /// `.write` (create or truncate), `.append` (create, write at the
    /// end), `.readWrite` (create, both ways). A missing file is an error.
    /// The writing modes open read-write underneath, so `.data` reads
    /// back what was written; `.read` alone refuses to write.
    box.value = m.type("IO") { args in
        guard (1...2).contains(args.count), case .string(let path) = args[0] else {
            throw Swiftalk.Error.type("IO(path: String, mode: .read | .write | .append | .readWrite)")
        }
        var mode = "read"
        if args.count == 2 {
            guard case .string(let m) = args[1] else {
                throw Swiftalk.Error.type("IO(path:mode:) — mode is .read, .write, .append, or .readWrite, not \(args[1].typeName)")
            }
            mode = m
        }
        let flags: Int32
        switch mode {
        case "read":      flags = O_RDONLY
        case "write":     flags = O_RDWR | O_CREAT | O_TRUNC       // read-write underneath: .data reads back
        case "append":    flags = O_RDWR | O_CREAT | O_APPEND
        case "readWrite": flags = O_RDWR | O_CREAT
        default: throw Swiftalk.Error.type("IO(path:mode:) — mode is .read, .write, .append, or .readWrite, not .\(mode)")
        }
        let fd = open(path, flags, 0o644)
        guard fd >= 0 else {
            throw Swiftalk.Error.type("IO(path: \"\(path)\", mode: .\(mode)): \(String(cString: strerror(errno)))")
        }
        return .host(Handle(fd: fd, path: path, mode: mode, owned: true, type: box.value))
    }
    let stdin = Handle(fd: 0, path: nil, mode: "read", owned: false, type: box.value)
    m.static("IO", "stdin", .host(stdin))
    m.static("IO", "stdout", .host(Handle(fd: 1, path: nil, mode: "write", owned: false, type: box.value)))
    m.static("IO", "stderr", .host(Handle(fd: 2, path: nil, mode: "write", owned: false, type: box.value)))

    /// `print(x, ...)` — each value's display text, space-separated, a
    /// newline, to the Interpreter's output (stdout).
    m.function("print") { args in
        Swiftalk.output(try args.map(Swiftalk.display).joined(separator: " ") + "\n")
        return .nil
    }
    /// `debugPrint(x, ...)` — `.debugDescription` for everything, to the
    /// Interpreter's error output (stderr, round 191).
    m.function("debugPrint") { args in
        Swiftalk.errorOutput(args.map { $0.sourceString(debug: true) }.joined(separator: " ") + "\n")
        return .nil
    }
    /// `readLine()` — the next line of stdin without its newline, nil at
    /// EOF: `IO.stdin.readLine()`.
    m.function("readLine") { args in
        guard args.isEmpty else { throw Swiftalk.Error.type("readLine() takes no arguments") }
        return try stdin.readLine() ?? .nil
    }
    return m
}

/// The entry point the interpreter calls after dlopen.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
