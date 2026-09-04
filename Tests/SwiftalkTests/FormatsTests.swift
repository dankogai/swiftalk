import Testing
@testable import Swiftalk

@Suite("SION as a built-in: SION, JSON, and property lists (round 97)")
struct FormatsTests {
    @Test("Data's literal is SION's: .Data(\"base64\"); Data(s) decodes base64; s.Data(.utf8) encodes text")
    func dataLiteral() throws {
        #expect(try eval(#""café".Data(.utf8)"#) == .data(Array("café".utf8)))
        #expect(try eval(#""café".Data(.utf8).String()"#) == .string(#".Data("Y2Fmw6k=")"#))
        #expect(try eval(#"Data("Y2Fmw6k=") == "café".Data(.utf8)"#) == .bool(true))
        #expect(try eval(#".Data("Y2Fmw6k=") == "Y2Fmw6k=".Data()"#) == .bool(true))   // the round-47 law
        #expect(try eval(#""hello".Data()"#) == .nil)                                   // not base64: failable
        #expect(try eval(#"Data("")"#) == .data([]))
        #expect(try eval(#"Data("AQ==")"#) == .data([1]))
        #expect(try eval(#"Data("AQI=")"#) == .data([1, 2]))
        #expect(try eval(#"Data("A Q I D")"#) == .data([1, 2, 3]))                     // whitespace ignored
        #expect(try eval(#"Data("AQIDA")"#) == .nil)                                    // bad length
        #expect(try eval("Data([255, 1]).String()") == .string(#".Data("/wE=")"#))
        #expect(try eval("Data([255, 1]).debugDescription") == .string("Data([0xff, 0x1])"))
        // the round-trip law, both forms
        guard case .string(let src) = try eval("Data([0, 127, 255]).String()") else { throw SwiftalkError.type("expected string") }
        #expect(try eval(src) == .data([0, 127, 255]))
        #expect(try eval("let d: Data = .Data(\"AQID\")\nd.count") == .int(3))
    }

    @Test("SION(text) reads a document — any key, dates, bytes, comments, hex, \"\"\" — and .String() writes it back")
    func sion() throws {
        let doc = #"""
            let doc: SION = SION("""
                [
                    "int": -42, "double": 42.195, "string": "漢字😇",
                    "array": [nil, true, 1, 1.0, "one", [1], ["one": 1.0]],
                    "date": .Date(0x0p+0),
                    "data": .Data("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"),
                    nil: "nil key", 1.0: "double key", []: "array key", [:]: "dict key",  // any key
                    "hex": 0xff_ff, /* block */ "neg": -1.5e3,
                ]
                """)

            """#
        #expect(try eval(doc + "doc[\"int\"]") == .int(-42))
        #expect(try eval(doc + "doc[\"date\"]") == .date(0))
        #expect(try eval(doc + "doc[\"data\"].count") == .int(42))
        #expect(try eval(doc + "doc[nil]") == .string("nil key"))
        #expect(try eval(doc + "doc[[:]]") == .string("dict key"))
        #expect(try eval(doc + "doc[\"hex\"]") == .int(65535))
        #expect(try eval(doc + "doc[\"neg\"]") == .double(-1500))
        #expect(try eval(doc + "SION(doc.String()) == doc") == .bool(true))          // the round-trip law, through SION
        #expect(try eval(doc + "doc.String(.sion) == doc.String()") == .bool(true))
        #expect(try eval("SION(\"[1, 2, 3]\")") == .array([.int(1), .int(2), .int(3)]))
        #expect(try eval("SION(\"42\")") == .int(42))
        #expect(try eval("SION(\"nil\")") == .nil)
        #expect(try eval("\"[1, 2]\".SION()") == .array([.int(1), .int(2)]))       // the round-47 law
        #expect(try eval("SION(42)") == .int(42))                                   // a value SION carries: itself
        #expect(try eval("SION([1, \"a\"])") == .array([.int(1), .string("a")]))
        #expect(try eval("let x: SION = SION(\"[1, [2]]\")\nx") == .array([.int(1), .array([.int(2)])]))
    }

    @Test("a SION document is data, never code")
    func sionRejects() throws {
        #expect(throws: SwiftalkError.self) { try eval("SION(\"[1, 2\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION(\"f(1)\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION(\"x\")") }
        #expect(throws: SwiftalkError.self) { try eval(##"SION(#"[1, "\(2)"]"#)"##) }   // a raw literal, so SION sees the \(
        #expect(throws: SwiftalkError.self) { try eval("SION(\"/a/\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION(\"1; 2\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION(\".Data(\\\"@@\\\")\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION()") }
        #expect(throws: SwiftalkError.self) { try eval("SION({ 1 })") }
    }

    @Test("JSON: canonical text out (keys sorted, escapes), RFC 8259 in; lossy where JSON is poorer")
    func json() throws {
        #expect(try eval(#"let j: SION = ["name": "s", "n": 42, "pi": 3.14, "ok": true, "none": nil, "tags": ["a", "b"]]"# + "\nj.String(.json)")
                == .string(#"{"n":42,"name":"s","none":null,"ok":true,"pi":3.14,"tags":["a","b"]}"#))
        #expect(try eval(#""tab\t\"q\" \u{1}".String(.json)"#) == .string(#""tab\t\"q\" \u0001""#))
        #expect(try eval(##"SION(json: #"{"a": [1, 2.5, -3e2, "\u00e9\ud83d\ude00", null, {"b": false}]}"#)"##)
                == .dictionary([.string("a"): .array([.int(1), .double(2.5), .double(-300), .string("é😀"), .nil,
                                                         .dictionary([.string("b"): .bool(false)])])]))
        #expect(try eval("SION(json: \" [ ] \")") == .array([]))
        #expect(try eval("SION(json: \"12345678901234567890\")") == .double(12345678901234567890))   // does not fit an Int
        #expect(try eval("SION(json: \"-0\")") == .int(0))
        #expect(try eval(#"let j: SION = ["k": [1, "two", [3.5, nil]], "e": [:]]"# + "\nSION(json: j.String(.json)) == j") == .bool(true))
        // lossy, by decision: Data → base64, Date → epoch, a non-String key → its String()
        #expect(try eval(#"["k": .Date(0.0), "d": Data("AQID")].String(.json)"#) == .string(#"{"d":"AQID","k":0.0}"#))
        #expect(try eval(#"[1: "one"].String(.json)"#) == .string(#"{"1":"one"}"#))
        #expect(throws: SwiftalkError.self) { try eval("(1.0 / 0.0).String(.json)") }
        #expect(throws: SwiftalkError.self) { try eval("SION(json: \"[1, 2\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION(json: \"{1: 2}\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION(json: \"'x'\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION(json: \"[1] x\")") }
        #expect(throws: SwiftalkError.self) { try eval(#"SION(json: "\"\\x\"")"#) }
        #expect(throws: SwiftalkError.self) { try eval("SION(json: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("[{ 1 }].String(.json)") }
    }

    @Test("property lists, XML: Apple's layout out, the plist subset of XML in; nil and non-String keys refused")
    func plistXML() throws {
        let p = #"let p: SION = ["name": "a & b <c>", "n": 97, "r": 0.5, "on": true, "when": .Date(1234567890.0), "bytes": Data("AQID"), "list": [1, "two"], "empty": [:], "none": []]"# + "\n"
        #expect(try eval(p + "p.String(.propertyList).split(\"\\n\")[0]") == .string(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        #expect(try eval(p + "p.String(.propertyList).contains(\"<string>a &amp; b &lt;c&gt;</string>\")") == .bool(true))
        #expect(try eval(p + "p.String(.propertyList).contains(\"<date>2009-02-13T23:31:30Z</date>\")") == .bool(true))
        #expect(try eval(p + "p.String(.propertyList).contains(\"<dict/>\") && p.String(.propertyList).contains(\"<array/>\")") == .bool(true))
        #expect(try eval(p + "SION(propertyList: p.String(.propertyList)) == p") == .bool(true))
        #expect(try eval(#"SION(propertyList: "<?xml version=\"1.0\"?><!-- c --><plist version=\"1.0\"><array><integer>-7</integer><real>1e3</real><string>x&#233;&#x1F600;</string><true/><data> AQ ID </data><date>2000-01-01T00:00:00Z</date></array></plist>")"#)
                == .array([.int(-7), .double(1000), .string("xé😀"), .bool(true), .data([1, 2, 3]), .date(946684800)]))
        #expect(throws: SwiftalkError.self) { try eval("[nil].String(.propertyList)") }
        #expect(throws: SwiftalkError.self) { try eval("[1: \"one\"].String(.propertyList)") }
        #expect(throws: SwiftalkError.self) { try eval("SION(propertyList: \"<plist><foo/></plist>\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION(propertyList: \"<plist><date>yesterday</date></plist>\")") }
        #expect(throws: SwiftalkError.self) { try eval("SION(propertyList: \"<plist><dict><string>x</string></dict></plist>\")") }
    }

    @Test("property lists, binary: bplist00 out and in, verified against Apple's own writer")
    func plistBinary() throws {
        let p = #"let p: SION = ["name": "swiftalk", "u": "héllo", "n": 97, "neg": -1, "big": 3000000000, "huge": 9223372036854775807, "r": 0.5, "on": true, "off": false, "when": .Date(1234567890.0), "bytes": Data("AQID"), "list": [1, "two", [0.25]], "empty": [:], "sixteen": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]]"# + "\n"
        #expect(try eval(p + "p.Data(.propertyList)[0..<8].String(.utf8)") == .string("bplist00"))
        #expect(try eval(p + "SION(propertyList: p.Data(.propertyList)) == p") == .bool(true))
        #expect(try eval("SION(propertyList: [].Data(.propertyList))") == .array([]))
        #expect(try eval("SION(propertyList: \"x\".Data(.propertyList))") == .string("x"))
        // a plist written by plutil -convert binary1 from swiftalk's XML
        #expect(try eval("let v: SION = SION(propertyList: Data(\"YnBsaXN0MDDZAQIDBAUGBwgJCgsMDQ4PECElVHdoZW5Sb25VZW1wdHlVYnl0ZXNXdmVyc2lvblVyYXRpb1NiaWdUbGlzdFRuYW1lM0GujHSkAAAACdBDAQIDEGEjP+AAAAAAAACvEBAREhMUFRYXGBkaGxwdHh8gEAEQAhADEAQQBRAGEAcQCBAJEAoQCxAMEA0QDhAPEBCkESIjJGUAaADpAGwAbABvE///////////ErLQXgBYc3dpZnRhbGsIGyAjKS83PUFGS1RVVlpcZXh6fH6AgoSGiIqMjpCSlJaYnaixtgAAAAAAAAEBAAAAAAAAACYAAAAAAAAAAAAAAAAAAAC/\"))\n[v[\"when\"], v[\"list\"], v[\"big\"].count, v[\"bytes\"]]")
                == .array([.date(1234567890), .array([.int(1), .string("héllo"), .int(-1), .int(3000000000)]), .int(16), .data([1, 2, 3])]))
        #expect(throws: SwiftalkError.self) { try eval("[nil].Data(.propertyList)") }
        #expect(throws: SwiftalkError.self) { try eval("[1: 2].Data(.propertyList)") }
        #expect(throws: SwiftalkError.self) { try eval("SION(propertyList: Data(\"AAAA\"))") }
        #expect(throws: SwiftalkError.self) { try eval("SION(propertyList: 1)") }
        #expect(throws: SwiftalkError.self) { try eval("42.Data(.utf8)") }
        #expect(throws: SwiftalkError.self) { try eval("\"x\".Data(.hex)") }
    }
}
