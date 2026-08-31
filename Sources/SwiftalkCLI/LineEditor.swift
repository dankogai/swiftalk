#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A minimal readline (round 64): raw-mode line editing with emacs
/// keys, arrow-key history, and a persistent history file — the
/// linenoise approach, in pure Swift on termios, which Darwin/Glibc
/// already expose. Nothing beyond Swift: no readline (GPL), no
/// libedit (a system dependency), no Foundation.
final class LineEditor {
    enum ReadResult {
        case line(String)
        case interrupted      // ^C — cancel whatever is pending
        case eof              // ^D on an empty line, or the stream ended
    }

    private var history: [String] = []
    private let historyPath: String?
    private let maxHistory = 1000

    init() {
        if let home = getenv("HOME") {
            historyPath = String(cString: home) + "/.swiftalk_history"
        } else {
            historyPath = nil
        }
        loadHistory()
    }

    // MARK: history

    private func loadHistory() {
        guard let historyPath else { return }
        let fd = open(historyPath, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var data: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            data.append(contentsOf: chunk[0..<n])
        }
        history = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }

    /// Adds a submitted line to history (skipping blanks and
    /// immediate repeats) and appends it to the history file.
    func remember(_ line: String) {
        guard !line.allSatisfy({ $0 == " " || $0 == "\t" }), history.last != line else { return }
        history.append(line)
        if history.count > maxHistory { history.removeFirst() }
        guard let historyPath else { return }
        let fd = open(historyPath, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let bytes = Array((line + "\n").utf8)
        _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
    }

    // MARK: the editor

    func readLine(prompt: String) -> ReadResult {
        var original = termios()
        guard tcgetattr(0, &original) == 0 else {
            // not a terminal after all — plain buffered reading
            fputs(prompt, stdout)
            fflush(stdout)
            return Swift.readLine().map { .line($0) } ?? .eof
        }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL)
        withUnsafeMutableBytes(of: &raw.c_cc) {
            $0[Int(VMIN)] = 1
            $0[Int(VTIME)] = 0
        }
        // TCSANOW, deliberately: FLUSH discards queued input (eating
        // type-ahead and multi-line paste at line boundaries) and DRAIN
        // blocks until the reader drains output (hanging on an idle
        // pty). NOW applies immediately and touches neither queue.
        guard tcsetattr(0, TCSANOW, &raw) == 0 else {
            fputs(prompt, stdout)
            fflush(stdout)
            return Swift.readLine().map { .line($0) } ?? .eof
        }
        defer { tcsetattr(0, TCSANOW, &original) }

        var buffer: [Character] = []
        var cursor = 0
        var historyIndex = history.count
        var draft = ""

        func refresh() {
            var out = "\r\u{1B}[2K" + prompt + String(buffer)
            let tail = buffer.count - cursor
            if tail > 0 { out += "\u{1B}[\(tail)D" }
            fputs(out, stdout)
            fflush(stdout)
        }
        func recall(_ index: Int) {
            if historyIndex == history.count { draft = String(buffer) }
            historyIndex = index
            buffer = Array(historyIndex == history.count ? draft : history[historyIndex])
            cursor = buffer.count
        }

        refresh()
        while true {
            guard let byte = readByte() else {
                fputs("\n", stdout)
                return buffer.isEmpty ? .eof : .line(String(buffer))
            }
            switch byte {
            case 13, 10:                              // Enter
                fputs("\n", stdout)
                return .line(String(buffer))
            case 3:                                   // ^C — cancel
                fputs("^C\n", stdout)
                return .interrupted
            case 4:                                   // ^D — EOF when empty, else delete
                if buffer.isEmpty {
                    fputs("\n", stdout)
                    return .eof
                }
                if cursor < buffer.count { buffer.remove(at: cursor) }
            case 127, 8:                              // Backspace
                if cursor > 0 {
                    cursor -= 1
                    buffer.remove(at: cursor)
                }
            case 1:  cursor = 0                       // ^A
            case 5:  cursor = buffer.count            // ^E
            case 2:  if cursor > 0 { cursor -= 1 }    // ^B
            case 6:  if cursor < buffer.count { cursor += 1 }   // ^F
            case 11: buffer.removeSubrange(cursor...) // ^K — kill to end
            case 21:                                  // ^U — kill to start
                buffer.removeSubrange(0..<cursor)
                cursor = 0
            case 23:                                  // ^W — kill word back
                var start = cursor
                while start > 0, buffer[start - 1] == " " { start -= 1 }
                while start > 0, buffer[start - 1] != " " { start -= 1 }
                buffer.removeSubrange(start..<cursor)
                cursor = start
            case 16: if historyIndex > 0 { recall(historyIndex - 1) }              // ^P
            case 14: if historyIndex < history.count { recall(historyIndex + 1) }  // ^N
            case 12:                                  // ^L — clear screen
                fputs("\u{1B}[H\u{1B}[2J", stdout)
            case 27:                                  // ESC sequences
                guard let b1 = readByte() else { break }
                if b1 == UInt8(ascii: "[") {
                    guard let b2 = readByte() else { break }
                    switch b2 {
                    case UInt8(ascii: "A"): if historyIndex > 0 { recall(historyIndex - 1) }
                    case UInt8(ascii: "B"): if historyIndex < history.count { recall(historyIndex + 1) }
                    case UInt8(ascii: "C"): if cursor < buffer.count { cursor += 1 }
                    case UInt8(ascii: "D"): if cursor > 0 { cursor -= 1 }
                    case UInt8(ascii: "H"): cursor = 0
                    case UInt8(ascii: "F"): cursor = buffer.count
                    case UInt8(ascii: "1"), UInt8(ascii: "3"),
                         UInt8(ascii: "4"), UInt8(ascii: "7"), UInt8(ascii: "8"):
                        guard readByte() == UInt8(ascii: "~") else { break }
                        switch b2 {
                        case UInt8(ascii: "3"):                       // Delete
                            if cursor < buffer.count { buffer.remove(at: cursor) }
                        case UInt8(ascii: "1"), UInt8(ascii: "7"): cursor = 0
                        default:                                   cursor = buffer.count
                        }
                    default: break
                    }
                } else if b1 == UInt8(ascii: "O") {   // ESC O H/F (some terminals)
                    switch readByte() {
                    case UInt8(ascii: "H"): cursor = 0
                    case UInt8(ascii: "F"): cursor = buffer.count
                    default: break
                    }
                }
            default:
                if byte >= 32, let character = readCharacter(first: byte) {
                    buffer.insert(character, at: cursor)
                    cursor += 1
                }
            }
            refresh()
        }
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        return read(0, &byte, 1) == 1 ? byte : nil
    }

    /// Completes a UTF-8 sequence whose first byte arrived (multibyte
    /// input: café, 🍰). Per-scalar, not per-grapheme — good enough
    /// for a minimal editor.
    private func readCharacter(first: UInt8) -> Character? {
        if first < 0x80 { return Character(UnicodeScalar(first)) }
        let extra = first >= 0xF0 ? 3 : first >= 0xE0 ? 2 : first >= 0xC0 ? 1 : 0
        guard extra > 0 else { return nil }
        var bytes = [first]
        for _ in 0..<extra {
            guard let b = readByte() else { return nil }
            bytes.append(b)
        }
        return String(decoding: bytes, as: UTF8.self).first
    }
}
