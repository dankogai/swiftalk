import Testing
@testable import Swiftalk

// Round 196: s.trimmed() — whitespace and newlines off both ends; s.trimmed(chars) those graphemes.
struct TrimmedTests {
    @Test("trimmed(): spaces, tabs, newlines, and Unicode spaces off both ends, nothing inside")
    func whitespace() throws {
        #expect(try eval("\"  hello  \".trimmed()") == .string("hello"))
        #expect(try eval("\"\\t hello world \\n\".trimmed()") == .string("hello world"))
        #expect(try eval("\"\\r\\nline\\r\\n\".trimmed()") == .string("line"))
        #expect(try eval("\"\\u{3000}全角\\u{3000}\".trimmed()") == .string("全角"))            // ideographic space is White_Space
        #expect(try eval("\"   \".trimmed()") == .string(""))
        #expect(try eval("\"\".trimmed()") == .string(""))
        #expect(try eval("\"hello\".trimmed()") == .string("hello"))
        #expect(try eval("\"  a  b  \".trimmed()") == .string("a  b"))
        #expect(try eval("\" x \".trimmed().Type == String") == .bool(true))
        #expect(try eval("readLine.Type == Function") == .bool(true))                       // the usual partner
    }

    @Test("trimmed(chars): the given graphemes, Python's strip; errors for a bad argument or too many")
    func characters() throws {
        #expect(try eval("\"--hello--\".trimmed(\"-\")") == .string("hello"))
        #expect(try eval("\"xyhelloyx\".trimmed(\"xy\")") == .string("hello"))
        #expect(try eval("\"  hello!!\".trimmed(\"!\")") == .string("  hello"))              // only what is named
        #expect(try eval("\"éé.é\".trimmed(\"é\")") == .string("."))
        #expect(try eval("\"abc\".trimmed(\"\")") == .string("abc"))
        #expect(throws: SwiftalkError.self) { try eval("\"a\".trimmed(1)") }
        #expect(throws: SwiftalkError.self) { try eval("\"a\".trimmed(\"a\", \"b\")") }
        #expect(throws: SwiftalkError.self) { try eval("1.trimmed()") }
        #expect(throws: SwiftalkError.self) { try eval("\"a\".trimmed") }                    // a method
    }
}
