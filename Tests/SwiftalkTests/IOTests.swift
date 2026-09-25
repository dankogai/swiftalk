import Testing
@testable import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Round 191: IO beyond print — handles (IO(path:mode:), IO.stdin/stdout/
// stderr), data, lines, read(size), append, readLine; debugPrint to stderr.
struct IOTests {
    private var scratch: String {
        let base = getenv("TMPDIR").map { String(cString: $0) } ?? "/tmp"
        return (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/swiftalk-io-\(getpid()).txt"
    }

    @Test("a handle: write mode creates, data reads the whole file, .data = replaces, append appends, lines and read(size) are lazy Sequences from where the handle is")
    func handles() throws {
        let i = try interpreter()
        let path = scratch
        _ = try i.eval("let path = \"\(path)\"")
        #expect(try i.eval("var w = IO(path: path, mode: .write)\nw.write(\"one\\ntwo\\r\\n\")") == .int(9))
        #expect(try i.eval("w.append(\"three\")") == .int(5))
        #expect(try i.eval("w.data.String(.utf8)") == .string("one\ntwo\r\nthree"))
        #expect(try i.eval("w.mode") == .string("write"))
        #expect(try i.eval("w.path") == .string(path))
        #expect(try i.eval("w.Type == IO") == .bool(true))
        #expect(try i.eval("w.close()\nw.isClosed") == .bool(true))
        #expect(throws: SwiftalkError.self) { try i.eval("w.write(\"x\")") }
        #expect(try i.eval("let r = IO(path: path)\nr.mode") == .string("read"))
        #expect(try i.eval("r.lines.Type == Sequence") == .bool(true))
        #expect(try i.eval("r.lines.Array()") == .array([.string("one"), .string("two"), .string("three")]))
        #expect(try i.eval("r.lines.Array()") == .array([]))                                  // read on, not again
        #expect(try i.eval("var out = []\nfor line in IO(path: path).lines { out.append(line.count) }\nout") == .array([.int(3), .int(3), .int(5)]))
        #expect(try i.eval("IO(path: path).read(4).Array().map { $0.count }") == .array([.int(4), .int(4), .int(4), .int(2)]))
        #expect(try i.eval("IO(path: path).read(4).Type == Sequence") == .bool(true))
        #expect(try i.eval("IO(path: path).read().Array().count") == .int(1))
        #expect(try i.eval("let h = IO(path: path)\nh.readLine()") == .string("one"))
        #expect(try i.eval("h.readLine()") == .string("two"))
        #expect(try i.eval("h.read(2).Array()") == .array([.data(Array("th".utf8)), .data(Array("re".utf8)), .data(Array("e".utf8))]))
        #expect(try i.eval("h.readLine()") == .nil)
        #expect(try i.eval("var rw = IO(path: path, mode: .readWrite)\nrw.data = \"new\"\nrw.data.String(.utf8)") == .string("new"))
        #expect(try i.eval("IO(path: path).data.String(.utf8)") == .string("new"))
        #expect(try i.eval("var a = IO(path: path, mode: .append)\na.write(\"!\")\nIO(path: path).data.String(.utf8)") == .string("new!"))
        #expect(try i.eval("a.print(1, \"x\")\nIO(path: path).lines.Array()") == .array([.string("new!1 x")]))
        #expect(try i.eval("IO(path: path).String()") == .string("IO(path: \"\(path)\", mode: .read)"))
        #expect(try i.eval("IO(path: path) == IO(path: path)") == .bool(false))                 // handles are objects
        #expect(throws: SwiftalkError.self) { try i.eval("IO(path: path).data = \"x\"") }         // read-only descriptor: ftruncate fails
        #expect(throws: SwiftalkError.self) { try i.eval("IO(path: path).fd = 3") }              // not assignable
        #expect(throws: SwiftalkError.self) { try i.eval("IO(path: \"/nonexistent/x\")") }
        #expect(throws: SwiftalkError.self) { try i.eval("IO(path: path, mode: .bogus)") }
        #expect(throws: SwiftalkError.self) { try i.eval("IO()") }
        #expect(throws: SwiftalkError.self) { try i.eval("IO(path: path).read(0)") }
        #expect(throws: SwiftalkError.self) { try i.eval("IO(path: path).write(1)") }
        unlink(path)
    }

    @Test("the standard handles are statics; debugPrint goes to the error output; readLine is IO.stdin's")
    func standard() throws {
        let i = try interpreter()
        #expect(try i.eval("[IO.stdin.fd, IO.stdout.fd, IO.stderr.fd]") == .array([.int(0), .int(1), .int(2)]))
        #expect(try i.eval("IO.stdin.String()") == .string("IO.stdin"))
        #expect(try i.eval("IO.stderr.Type == IO && IO.stdin == IO.stdin") == .bool(true))
        #expect(try i.eval("IO.stdin.path") == .nil)
        #expect(try i.eval("IO.stdin.close()\nIO.stdin.isClosed") == .bool(true))              // marked, never closed
        var out = "", err = ""
        i.output = { out += $0 }
        i.errorOutput = { err += $0 }
        _ = try i.eval("print(1)\ndebugPrint(\"a\", 255)")
        #expect(out == "1\n")
        #expect(err == "\"a\" +0xff\n")
        #expect(try i.eval("readLine.Type == Function") == .bool(true))
        #expect(throws: SwiftalkError.self) { try i.eval("readLine(1)") }
    }
}
