import Testing
@testable import Swiftalk

/// Rounds 151–152: the conversion law reaches user types — `Double(x)`
/// runs a struct's `let Double` — and a type's `let String` owns its
/// text wherever a value of it prints: `.String()`, `.String(.pretty)`,
/// `print`, interpolation, inside a container. `.description` and the
/// data formats stay the builtin memberwise text.
@Suite("user conversion members — T(x) is x.T(), and a type's String member owns its text (rounds 151–152)")
struct UserConversionTests {
    private let decls = """
        struct Temp {
            var kelvin: Double = 0.0
            let Double = { .kelvin - 273.15 }
            let Int = { Int(.kelvin) }
            let String = { "\\(.kelvin)K" }
        }
        enum Coin {
            case heads, tails
            let String = { $.contains(.pretty) ? (self == Coin.heads ? "H" : "T") : .description }
            let Int = { self == Coin.heads ? 1 : 0 }
        }
        struct Plain { var x: Int = 1 }
        struct Bad { var x: Int = 1; let String = { 42 } }
        """

    @Test("Double(x) and Int(x) run the members as x.Double() and x.Int() do")
    func constructorForms() throws {
        let i = Swiftalk.Interpreter()
        _ = try i.eval(decls)
        #expect(try i.eval("Double(Temp(kelvin: 300.0))") == .double(300.0 - 273.15))
        #expect(try i.eval("Temp(kelvin: 300.0).Double()") == .double(300.0 - 273.15))
        #expect(try i.eval("Int(Temp(kelvin: 300.5))") == .int(300))
        #expect(try i.eval("Int(Coin.heads) + Int(Coin.tails)") == .int(1))
        #expect(try i.eval("[Coin.heads, Coin.tails].map(Int)") == .array([.int(1), .int(0)]))
        #expect(throws: SwiftalkError.self) { try i.eval("Double(Plain())") }            // no member: the builtin's refusal, as before
        #expect(throws: SwiftalkError.self) { try i.eval("Bool(Temp())") }
    }

    @Test("let String owns .String(), String(x), print's form and interpolation; .description is the builtin text")
    func stringForms() throws {
        let i = Swiftalk.Interpreter()
        _ = try i.eval(decls)
        #expect(try i.eval("Temp(kelvin: 1.5).String()") == .string("1.5K"))
        #expect(try i.eval("String(Temp(kelvin: 1.5))") == .string("1.5K"))
        #expect(try i.eval("Temp(kelvin: 1.5).String(.pretty)") == .string("1.5K"))
        #expect(try i.eval("String(Temp(kelvin: 1.5), .pretty)") == .string("1.5K"))
        #expect(try i.eval("\"\\(Temp(kelvin: 1.5))\"") == .string("1.5K"))
        #expect(try i.eval("Temp(kelvin: 1.5).description") == .string("Temp(kelvin: 1.5)"))
        #expect(try i.eval("Temp(kelvin: 1.5).debugDescription") == .string("Temp(kelvin: +0x1.8p0)"))
        #expect(try i.eval("Coin.heads.String(.pretty)") == .string("H"))
        #expect(try i.eval("Coin.tails.String()") == .string("Coin.tails"))                      // its member says .description
        #expect(try i.eval("Plain().String()") == .string("Plain(x: 1)"))                        // no member: the builtin, as before
        #expect(try i.eval("Plain().String(.pretty)") == .string("Plain(\n  x: 1\n)"))
        #expect(try i.eval("Bad().String()") == .int(42))                                        // a direct call is just a call; the interpreter's own asks below must get a String
        #expect(throws: SwiftalkError.self) { try i.eval("\"\\(Bad())\"") }
    }

    @Test("a container, plain or pretty, asks each user-typed element — keys too; the data formats and .description do not")
    func nested() throws {
        let i = Swiftalk.Interpreter()
        _ = try i.eval(decls)
        #expect(try i.eval("[Temp(kelvin: 1.0), Temp(kelvin: 2.0)].String(.pretty)") == .string("[\n  1.0K,\n  2.0K\n]"))
        #expect(try i.eval("[Temp(kelvin: 1.0), Temp(kelvin: 2.0)].String()") == .string("[1.0K, 2.0K]"))
        #expect(try i.eval("String([Temp(kelvin: 1.0)])") == .string("[1.0K]"))
        #expect(try i.eval("\"\\([Temp(kelvin: 1.0)])\"") == .string("[1.0K]"))
        #expect(try i.eval("(t: Temp(kelvin: 1.0), c: Coin.tails).String()") == .string("(t: 1.0K, c: Coin.tails)"))
        #expect(try i.eval("(t: Temp(kelvin: 1.0), c: Coin.tails).String(.pretty)") == .string("(\n  t: 1.0K,\n  c: T\n)"))
        #expect(try i.eval("[\"k\": Coin.heads].String(.pretty)") == .string("[\n  \"k\": H\n]"))
        #expect(try i.eval("[Temp(kelvin: 1.0): 1].String()") == .string("[1.0K: 1]"))
        #expect(try i.eval("[Coin.heads: 1].String(.pretty)") == .string("[\n  H: 1\n]"))
        #expect(try i.eval("Set(Coin.heads).String(.pretty)") == .string("Set(\n  H\n)"))
        #expect(try i.eval("[Temp(kelvin: 1.0)].description") == .string("[Temp(kelvin: 1.0)]"))        // the builtin text, throughout
        #expect(try i.eval("[Temp(kelvin: 1.0)].String(.sion)") == .string("[Temp(kelvin: 1.0)]"))      // a data format, builtin throughout
        #expect(try i.eval("[Temp(kelvin: 1.0)].debugDescription") == .string("[Temp(kelvin: +0x1p0)]"))
        #expect(try i.eval("[Plain()].String(.pretty)") == .string("[\n  Plain(\n    x: 1\n  )\n]"))   // no member: laid out as before
        #expect(throws: SwiftalkError.self) { try i.eval("[Bad()].String(.pretty)") }                  // must return a String
        #expect(throws: SwiftalkError.self) { try i.eval("[Bad()].String()") }
        #expect(throws: SwiftalkError.self) { try i.eval("[Temp(kelvin: 1.0)].String(.json, .pretty)") }   // JSON has no struct form, as before
    }
}
