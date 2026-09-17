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
    /// Tab (round 164): given the line up to the cursor, where the word
    /// being completed starts and what it could become. nil: Tab is a
    /// tab.
    var completer: ((String) -> (start: Int, candidates: [String]))? = nil

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
            emit(prompt)
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
            emit(prompt)
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
            emit(out)
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
                emit("\n")
                return buffer.isEmpty ? .eof : .line(String(buffer))
            }
            switch byte {
            case 13, 10:                              // Enter
                emit("\n")
                return .line(String(buffer))
            case 3:                                   // ^C — cancel
                emit("^C\n")
                return .interrupted
            case 4:                                   // ^D — EOF when empty, else delete
                if buffer.isEmpty {
                    emit("\n")
                    return .eof
                }
                if cursor < buffer.count { buffer.remove(at: cursor) }
            case 127, 8:                              // Backspace
                if cursor > 0 {
                    cursor -= 1
                    buffer.remove(at: cursor)
                }
            case 9:                                   // Tab — complete (round 164)
                guard let completer else {
                    buffer.insert("\t", at: cursor)
                    cursor += 1
                    break
                }
                let (start, candidates) = completer(String(buffer[..<cursor]))
                guard !candidates.isEmpty, start <= cursor else { break }
                let word = String(buffer[start..<cursor])
                let shared = LineEditor.commonPrefix(candidates)
                if shared.count > word.count {
                    // one candidate, or the part they all share
                    buffer.replaceSubrange(start..<cursor, with: Array(shared))
                    cursor = start + shared.count
                } else if candidates.count > 1 {
                    // nothing more to insert: show the choices, then the line again
                    emit("\n" + LineEditor.columns(candidates) + "\n")
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
                emit("\u{1B}[H\u{1B}[2J")
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

    /// The longest prefix every candidate shares.
    static func commonPrefix(_ candidates: [String]) -> String {
        guard var prefix = candidates.first else { return "" }
        for candidate in candidates.dropFirst() {
            while !candidate.hasPrefix(prefix) { prefix.removeLast() }
            if prefix.isEmpty { break }
        }
        return prefix
    }

    /// Candidates laid out in columns, 80 wide.
    static func columns(_ names: [String], width: Int = 80) -> String {
        let cell = (names.map(\.count).max() ?? 0) + 2
        let perLine = max(1, width / cell)
        var lines: [String] = []
        for row in stride(from: 0, to: names.count, by: perLine) {
            lines.append(names[row..<min(row + perLine, names.count)]
                .map { $0.padding(to: cell) }.joined().trimmingTrailingSpaces())
        }
        return lines.joined(separator: "\n")
    }

    /// Writes straight to fd 1 — Glibc's `stdout` is a shared
    /// mutable var Swift 6 refuses to touch, and raw fd writes need
    /// no flushing anyway.
    private func emit(_ s: String) {
        let bytes = Array(s.utf8)
        _ = bytes.withUnsafeBufferPointer { write(1, $0.baseAddress, $0.count) }
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

private extension String {
    func padding(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
    func trimmingTrailingSpaces() -> String {
        var s = self
        while s.hasSuffix(" ") { s.removeLast() }
        return s
    }
}
