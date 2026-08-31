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
