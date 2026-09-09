import Testing
@testable import Swiftalk
#if canImport(Foundation)
import Foundation
#endif

@Suite("Unicode normalization and escapes (round 137)")
struct NormalizationTests {
    @Test("normalize(with:) — nfc, nfd, nfkc, nfkd; the with: label optional")
    func forms() throws {
        #expect(try eval("\"e\\u{301}\".normalize(with: .nfc) == \"\\u{e9}\"") == .bool(true))
        #expect(try eval("\"\\u{e9}\".normalize(with: .nfd).unicodeScalars") == .array([.int(0x65), .int(0x301)]))
        #expect(try eval("\"\\u{e9}\".normalize(.nfd).count") == .int(1))                     // one grapheme still
        #expect(try eval("\"ﬁ\".normalize(with: .nfkc)") == .string("fi"))
        #expect(try eval("\"ﬁ\".normalize(with: .nfc)") == .string("ﬁ"))                       // canonical leaves the ligature
        #expect(try eval("\"①\".normalize(with: .nfkd)") == .string("1"))
        #expect(try eval("\"한\".normalize(with: .nfd).unicodeScalars") == .array([.int(0x1112), .int(0x1161), .int(0x11AB)]))
        #expect(try eval("\"\\u{1112}\\u{1161}\\u{11AB}\".normalize(with: .nfc)") == .string("한"))
        #expect(try eval("\"\\u{212B}\".normalize(with: .nfc) == \"\\u{c5}\"") == .bool(true))   // ANGSTROM SIGN: a singleton, never re-composed
        #expect(try eval("\"\\u{1E0B}\\u{323}\".normalize(with: .nfc) == \"\\u{1E0D}\\u{307}\"") == .bool(true))   // reordering, then composition
        #expect(try eval("\"\\u{958}\".normalize(with: .nfc) == \"\\u{915}\\u{93C}\"") == .bool(true))            // a composition exclusion stays apart
        #expect(try eval("\"\\u{FB01}\\u{2460}\\u{F900}\".normalize(with: .nfkc) == \"fi1\\u{8C48}\"") == .bool(true))
        #expect(try eval("\"\".normalize(with: .nfc)") == .string(""))
        #expect(try eval("\"abc\".normalize(with: .nfkd)") == .string("abc"))
        #expect(try eval("\"弾\".normalize(with: .nfc) == \"弾\"") == .bool(true))
        #expect(throws: SwiftalkError.self) { try eval("\"a\".normalize(with: .nfz)") }
        #expect(throws: SwiftalkError.self) { try eval("\"a\".normalize()") }
        #expect(throws: SwiftalkError.self) { try eval("1.normalize(with: .nfc)") }
    }

    #if canImport(Foundation)
    @Test("agrees with Foundation on a battery of awkward strings")
    func foundation() throws {
        let samples = ["e\u{301}", "\u{e9}", "ﬁ①", "한글", "\u{1112}\u{1161}\u{11AB}", "\u{212B}\u{2126}", "\u{1E0B}\u{323}",
                       "\u{958}\u{959}", "\u{F900}\u{F901}", "\u{FDFA}", "\u{3300}", "\u{1F100}", "\u{0344}", "a\u{301}\u{327}\u{302}",
                       "\u{FF76}\u{FF9E}", "Ǆǅ", "\u{2000}\u{2003}\u{00A0}", "\u{1D400}", "Dan = 弾 ✓ 🙂", "\u{0CC6}\u{0CC2}\u{0CD5}"]
        for s in samples {
            #expect(UnicodeNormalization.normalize(s, .nfc) == s.precomposedStringWithCanonicalMapping, "nfc \(s.unicodeScalars.map { String($0.value, radix: 16) })")
            #expect(UnicodeNormalization.normalize(s, .nfd) == s.decomposedStringWithCanonicalMapping, "nfd \(s.unicodeScalars.map { String($0.value, radix: 16) })")
            #expect(UnicodeNormalization.normalize(s, .nfkc) == s.precomposedStringWithCompatibilityMapping, "nfkc \(s.unicodeScalars.map { String($0.value, radix: 16) })")
            #expect(UnicodeNormalization.normalize(s, .nfkd) == s.decomposedStringWithCompatibilityMapping, "nfkd \(s.unicodeScalars.map { String($0.value, radix: 16) })")
        }
    }
    #endif

    /// The UCD's own conformance file, when SWIFTALK_NORMALIZATION_TEST
    /// names it (it is 2.8 MB, so not in the repo): every line of Parts
    /// 0–3, the five columns checked as the file's header prescribes.
    @Test("passes NormalizationTest.txt", .enabled(if: ProcessInfo.processInfo.environment["SWIFTALK_NORMALIZATION_TEST"] != nil))
    func conformance() throws {
        let path = ProcessInfo.processInfo.environment["SWIFTALK_NORMALIZATION_TEST"]!
        let text = try String(contentsOfFile: path, encoding: .utf8)
        func str(_ field: Substring) -> String {
            var v = String.UnicodeScalarView()
            for h in field.split(separator: " ") { v.append(Unicode.Scalar(UInt32(h, radix: 16)!)!) }
            return String(v)
        }
        var lines = 0, failures = 0
        for line in text.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("@") {
            let c = line.split(separator: ";").prefix(5).map(str)
            guard c.count == 5 else { continue }
            lines += 1
            let nfc = { UnicodeNormalization.normalize($0, .nfc) }, nfd = { UnicodeNormalization.normalize($0, .nfd) }
            let nfkc = { UnicodeNormalization.normalize($0, .nfkc) }, nfkd = { UnicodeNormalization.normalize($0, .nfkd) }
            let ok = c[1] == nfc(c[0]) && c[1] == nfc(c[1]) && c[1] == nfc(c[2]) && c[3] == nfc(c[3]) && c[3] == nfc(c[4])
                && c[2] == nfd(c[0]) && c[2] == nfd(c[1]) && c[2] == nfd(c[2]) && c[4] == nfd(c[3]) && c[4] == nfd(c[4])
                && [c[0], c[1], c[2], c[3], c[4]].allSatisfy { nfkc($0) == c[3] && nfkd($0) == c[4] }
            if !ok { failures += 1; if failures < 5 { Issue.record("line: \(line.prefix(80))") } }
        }
        #expect(lines > 18000)
        #expect(failures == 0)
    }

    @Test("escaped(): non-ASCII scalars as \\u{hex}, a backslash doubled; unescaped() reads the literal escapes back")
    func escapes() throws {
        #expect(try eval("\"Dan = 弾\".escaped()") == .string("Dan = \\u{5f3e}"))
        #expect(try eval("\"Dan = \\\\u{5f3e}\".unescaped()") == .string("Dan = 弾"))
        #expect(try eval("\"Dan = 弾\".escaped().unescaped() == \"Dan = 弾\"") == .bool(true))
        #expect(try eval("\"a\\\\b\".escaped()") == .string("a\\\\b"))                          // \ → \\ so the round trip holds
        #expect(try eval("\"a\\\\b\".escaped().unescaped() == \"a\\\\b\"") == .bool(true))
        #expect(try eval("\"🙂\".escaped()") == .string("\\u{1f642}"))
        #expect(try eval("\"e\\u{301}\".escaped()") == .string("e\\u{301}"))
        #expect(try eval("\"plain ascii\".escaped()") == .string("plain ascii"))
        #expect(try eval("\"a\\nb\".escaped()") == .string("a\nb"))                             // ASCII stays as it is, newline included
        #expect(try eval("\"a\\\\nb\".unescaped()") == .string("a\nb"))                         // unescaped knows the literal escapes
        #expect(try eval("\"\\\\t\\\\0\\\\\\\"\\\\'\".unescaped()") == .string("\t\0\"'"))
        #expect(try eval("\"\\\\u{41}\\\\u{1F600}\".unescaped()") == .string("A😀"))
        #expect(try eval(#"let s = "☃ \\ 弾""# + "\n" + #"eval("\"" + s.escaped() + "\"") == s"#) == .bool(true))   // the escaped text is a literal's body
        #expect(throws: SwiftalkError.self) { try eval("\"\\\\q\".unescaped()") }
        #expect(throws: SwiftalkError.self) { try eval("\"\\\\u{D800}\".unescaped()") }
        #expect(throws: SwiftalkError.self) { try eval("\"\\\\u41\".unescaped()") }
        #expect(throws: SwiftalkError.self) { try eval("\"abc\\\\\".unescaped()") }
        #expect(throws: SwiftalkError.self) { try eval("\"a\".escaped(1)") }
    }
}
