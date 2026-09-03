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

    @Test("array.swt: COW, inferred locks, map/filter/reduce, and a hand-rolled sort")
    func array() throws {
        #expect(try output(of: try slurp("array.swt")) == """
            5
            2 11
            [1, 3, 5, 7, 11, 13]
            [2, 3, 5, 7, 11]
            [1, 4, 9, 16, 25, 36, 49, 64, 81, 100]
            [4, 16, 36, 64, 100]
            385
            [[1, 2], [30, 4]]
            [1, 2, 3]
            [1, 2, 3, 4, 5]
            ["h", "é", "l", "l", "o"]
            [3, 2, 1]
            true false
            1, 2, 3
            [1, 3, 5, 7, 9]
            ["apple", "fig", "pear"]

            """)
    }

    @Test("dictionary.swt: any key, nil as a value, sparse arrays, a histogram")
    func dictionary() throws {
        #expect(try output(of: try slurp("dictionary.swt")) == """
            ["smalltalk": 1972, "swift": 2014, "swiftalk": 2026]
            2014
            nil
            2015
            true false
            false
            two
            3
            million nil
            2
            false true
            8023
            ["i": 4, "m": 1, "p": 2, "s": 4]
            ["smalltalk": 1972]

            """)
    }

    @Test("sequence.swt: lazy generators and coroutines, infinite primes")
    func sequence() throws {
        #expect(try output(of: try slurp("sequence.swt")) == """
            1000000000000
            [1, 2, 3, 4, 5]
            [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
            ["0", "2", "8", "34", "144"]
            [0, 1, 2, 3, 4]
            [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]
            2
            3
            5
            7
            11
            13
            17
            19
            [2, 3, 5] [2, 3, 5]
            ["h.", "é.", "l.", "l.", "o."]
            ["a"]

            """)
    }

    @Test("ski.swt: S, K, I — and iota deriving all three")
    func ski() throws {
        #expect(try output(of: try slurp("ski.swt"))
            == "42\n42\nyes\nno\n42\n42\n1\n42\n")
    }

    @Test("sion.swt: MySION — a SION parser in swiftalk — parses swift-sion's README sample; the round-trip law holds through it (round 85)")
    func sion() throws {
        #expect(try output(of: try slurp("sion.swt")) == """
            -42 42.195 true nil true
            漢字、カタカナ、ひらがなの入ったstring😇
            [nil, true, 1, 1.0, "one", [1], ["one": 1.0]]
            ["array": [], "bool": false, "dictionary": [:], "double": 0.0, "int": 0, "nil": nil, "string": ""]
            .Date(0.0) Date
            42 Data
            Unlike JSON and Property Lists, / Yes, SION / does accept / non-String keys. / like / Map of ECMAScript.
            [255, 15, 5, 1000, -7, 1000.0, 0.25, 6.02e+23]
            tab\tnew
            line 😀 "quoted"
            [1, 2, 3]
            true nil
            true true
            true -42
            true 42.195
            true 1e+100
            true "漢字😇\\n"
            true [1, [2, [3]]]
            true ["k": [nil, 1.5]]
            true ["😇": true, 1.0: [], nil: [:]]
            true .Date(1234567890.5)
            true Data([99, 97, 102, 195, 169])
            expected ',' or ']' at 5
            expected ',' or ']' at 3
            unterminated string at 5
            expected ',' or ']' at 5
            bad base64 at 6
            unexpected 'x' at 4
            unexpected 't' at 0

            """)
    }
}
