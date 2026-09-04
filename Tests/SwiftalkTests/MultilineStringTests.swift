import Testing
@testable import Swiftalk

@Suite("\"\"\" multi-line and #\"...\"# raw string literals (round 94)")
struct MultilineStringTests {
    @Test("content between the delimiter lines; the closing delimiter's indentation is stripped; quotes need no escape")
    func multiline() throws {
        #expect(try eval("""
            let s = \"\"\"
                Roses are "red",
                  violets are blue.
                \"\"\"
            s
            """) == .string("Roses are \"red\",\n  violets are blue."))
        #expect(try eval("let s = \"\"\"\n    \"\"\"\ns") == .string(""))
        #expect(try eval("let s = \"\"\"\n    a\n\n    b\n    \"\"\"\ns") == .string("a\n\nb"))
        // the closing delimiter at column 0 strips nothing
        #expect(try eval("let s = \"\"\"\n  x\n    y\n\"\"\"\ns") == .string("  x\n    y"))
        // escapes and interpolation as in a single-line literal; \\ at a line's end joins lines
        #expect(try eval("let n = 2\nlet s = \"\"\"\n    \\(n) lines\\tof \\\"text\\\"\n    \"\"\"\ns") == .string("2 lines\tof \"text\""))
        #expect(try eval("let s = \"\"\"\n    one \\\n    line\n    \"\"\"\ns") == .string("one line"))
        #expect(try eval("\"\"\"\n  x\n  \"\"\".count") == .int(1))
    }

    @Test("Swift's rules enforced: content starts on the next line; less indentation than the closing delimiter is an error")
    func multilineErrors() throws {
        #expect(throws: SwiftalkError.self) { try eval("let s = \"\"\"bad\n\"\"\"") }
        #expect(throws: SwiftalkError.self) { try eval("let s = \"\"\"\n  a\n    \"\"\"") }
        #expect(throws: SwiftalkError.self) { try eval("let s = \"\"\"\n  a") }
        // blank lines may be shorter than the indentation
        #expect(try eval("let s = \"\"\"\n    a\n\n    b\n    \"\"\"\ns.count") == .int(4))
        // the REPL asks for more lines while a \"\"\" is open
        #expect(Swiftalk.needsMoreInput("let s = \"\"\"") == true)
        #expect(Swiftalk.needsMoreInput("let s = \"\"\"\n    hi") == true)
        #expect(Swiftalk.needsMoreInput("let s = \"\"\"\n    hi\n    \"\"\"") == false)
        #expect(Swiftalk.needsMoreInput("let s = \"unterminated") == false)
    }

    @Test("raw strings: #\"...\"# keeps backslashes and \\( verbatim; \\#( interpolates; ##...## nests a \"#")
    func raw() throws {
        #expect(try eval("#\"a \\n b \\(x) \"quoted\" c\"#") == .string("a \\n b \\(x) \"quoted\" c"))
        #expect(try eval("#\"total: \\#(6 * 7)\"#") == .string("total: 42"))
        #expect(try eval("#\"line\\#nbreak\"#") == .string("line\nbreak"))
        #expect(try eval("##\"a \"# b\"##") == .string("a \"# b"))
        #expect(try eval("#\"\\d+\"#.count") == .int(3))
        #expect(try eval("Regex(#\"\\d+\"#) == /\\d+/") == .bool(true))
        #expect(try eval("#\"\"\"\n    C:\\dir\\file \\(nothing)\n    \"\"\"#") == .string("C:\\dir\\file \\(nothing)"))
        #expect(throws: SwiftalkError.self) { try eval("#\"unterminated") }
        #expect(throws: SwiftalkError.self) { try eval("#x") }
        // the round-trip law still holds: a raw literal's value re-enters through the ordinary form
        #expect(try eval("let r = #\"a\\b\"#\nr.String(.quoted)") == .string("\"a\\\\b\""))
    }
}
