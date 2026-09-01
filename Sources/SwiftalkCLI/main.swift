import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
        _ = try Swiftalk.Interpreter().eval(String(decoding: data, as: UTF8.self))
    } catch let error as Swiftalk.Error {
        let msg = "\(path): \(error.description)\n"
        _ = Array(msg.utf8).withUnsafeBufferPointer { write(2, $0.baseAddress, $0.count) }
        exit(1)
    }
    exit(0)
}

let interpreter = Swiftalk.Interpreter(relaxed: true)
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
        do {
            let value = try interpreter.eval(buffer)
            // nil echoes are suppressed (the Python way): statements —
            // loops, if, print(...) — all evaluate to nil; echoing it
            // is noise.
            if value != .nil {
                print(value.sourceString())
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
