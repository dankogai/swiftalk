import Testing
@testable import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The eg/ examples, kept honest (round 66): quine laws are checked
/// byte-for-byte against the actual files, outputs line-for-line —
/// the same discipline as Status.md's verified transcripts.
@Suite("eg/ — the examples run, and the quines are quines (round 66)")
struct EgTests {
    private func slurp(_ name: String) throws -> String {
        // Tests/SwiftalkTests/EgTests.swift → ../../../eg/<name>
        let root = #filePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .dropLast(3)
            .joined(separator: "/")
        let fd = open("\(root)/eg/\(name)", O_RDONLY)
        guard fd >= 0 else {
            throw SwiftalkError.type("cannot open eg/\(name)")
        }
        defer { close(fd) }
        var data: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            data.append(contentsOf: chunk[0..<n])
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func output(of source: String) throws -> String {
        let interp = Swiftalk.Interpreter()
        var captured = ""
        interp.output = { captured += $0 }
        _ = try interp.eval(source)
        return captured
    }

    @Test("quine.swt: eval(source) IS the source")
    func valueQuine() throws {
        let source = try slurp("quine.swt")
        #expect(try eval(source) == .string(source))
    }

    @Test("quine-print.swt: the output IS the source")
    func printQuine() throws {
        let source = try slurp("quine-print.swt")
        #expect(try output(of: source) == source)
    }

    @Test("lambda.swt: Church arithmetic through the Z combinator")
    func lambda() throws {
        #expect(try output(of: try slurp("lambda.swt"))
            == "5\n6\n2\ntrue\ntrue\n3628800\n")
    }

    @Test("ski.swt: S, K, I — and iota deriving all three")
    func ski() throws {
        #expect(try output(of: try slurp("ski.swt"))
            == "42\n42\nyes\nno\n42\n42\n1\n42\n")
    }
}
