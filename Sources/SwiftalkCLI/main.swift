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

let interpreter = Interpreter(relaxed: true)
let isTTY = isatty(0) != 0

func prompt(continued: Bool) {
    guard isTTY else { return }
    print(continued ? "........ " : "swiftalk> ", terminator: "")
}

var buffer = ""
prompt(continued: false)
while let line = readLine() {
    buffer += buffer.isEmpty ? line : "\n" + line
    if buffer.trimmed.isEmpty {
        buffer = ""
        prompt(continued: false)
        continue
    }
    if needsMoreInput(buffer) {
        prompt(continued: true)
        continue
    }
    do {
        let value = try interpreter.eval(buffer)
        print(value.sourceString())
    } catch let error as SwiftalkError {
        print(error.description)
    } catch {
        print("error: \(error)")
    }
    buffer = ""
    prompt(continued: false)
}
if isTTY { print() }  // a tidy newline after ctrl-D

extension String {
    var trimmed: String {
        String(drop(while: { $0 == " " || $0 == "\t" }))
    }
}
