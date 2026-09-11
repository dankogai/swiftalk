import Testing
@testable import Swiftalk

/// Round 151: the conversion law reaches user types — `Double(x)` runs a
/// struct's `let Double`, and a type's `let String` owns its `.pretty`
/// text at every depth of a layout.
@Suite("user conversion members — T(x) is x.T(), and .pretty asks the type (round 151)")
struct UserConversionTests {
    private let decls = """
        struct Temp {
            var kelvin: Double = 0.0
            let Double = { .kelvin - 273.15 }
            let Int = { Int(.kelvin) }
            let String = { $.contains(.pretty) ? "\\(.kelvin)K" : .description }
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

    @Test("String(x, format) reaches let String; .String() without one stays the source form")
    func stringForms() throws {
        let i = Swiftalk.Interpreter()
        _ = try i.eval(decls)
        #expect(try i.eval("Temp(kelvin: 1.5).String()") == .string("Temp(kelvin: 1.5)"))
        #expect(try i.eval("String(Temp(kelvin: 1.5))") == .string("Temp(kelvin: 1.5)"))
        #expect(try i.eval("Temp(kelvin: 1.5).String(.pretty)") == .string("1.5K"))
        #expect(try i.eval("String(Temp(kelvin: 1.5), .pretty)") == .string("1.5K"))
        #expect(try i.eval("Coin.heads.String(.pretty)") == .string("H"))
        #expect(try i.eval("Coin.tails.String()") == .string("Coin.tails"))
        #expect(try i.eval("Plain().String(.pretty)") == .string("Plain(\n  x: 1\n)"))
    }

    @Test("a pretty layout asks each user-typed element; the plain form and Dictionary keys do not")
    func nested() throws {
        let i = Swiftalk.Interpreter()
        _ = try i.eval(decls)
        #expect(try i.eval("[Temp(kelvin: 1.0), Temp(kelvin: 2.0)].String(.pretty)") == .string("[\n  1.0K,\n  2.0K\n]"))
        #expect(try i.eval("[Temp(kelvin: 1.0)].String()") == .string("[Temp(kelvin: 1.0)]"))
        #expect(try i.eval("(t: Temp(kelvin: 1.0), c: Coin.tails).String(.pretty)") == .string("(\n  t: 1.0K,\n  c: T\n)"))
        #expect(try i.eval("[\"k\": Coin.heads].String(.pretty)") == .string("[\n  \"k\": H\n]"))
        #expect(try i.eval("[Coin.heads: 1].String(.pretty)") == .string("[\n  Coin.heads: 1\n]"))     // a key is a lookup literal
        #expect(try i.eval("Set(Coin.heads).String(.pretty)") == .string("Set(\n  H\n)"))
        #expect(try i.eval("[Plain()].String(.pretty)") == .string("[\n  Plain(\n    x: 1\n  )\n]"))   // no member: laid out as before
        #expect(throws: SwiftalkError.self) { try i.eval("[Bad()].String(.pretty)") }                  // must return a String
        #expect(throws: SwiftalkError.self) { try i.eval("[Temp(kelvin: 1.0)].String(.json, .pretty)") }   // JSON has no struct form, as before
    }
}
