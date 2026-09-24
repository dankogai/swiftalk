import Testing
@testable import Swiftalk

// Round 184: `import M from` binds a TYPE whose statics are the exports —
// so `extension M { static let f = ... }` adds to a module, native or
// .swt, and nothing constructs one.
struct NamespaceTypeTests {
    private let geometry = """
        export struct Point { var x: Double; var y: Double }
        export let area = { w, h in w * h }
        export let unit = 1.0
        """

    private func interpreter() -> Swiftalk.Interpreter {
        let i = Swiftalk.Interpreter()
        i.moduleLoader = { spec in
            guard spec.hasSuffix("geometry.swt") else { throw Swiftalk.Error.type("no \(spec)") }
            return geometry
        }
        return i
    }

    @Test("the namespace is a type: it prints as its name, its .Type is Function, and it cannot be constructed")
    func isType() throws {
        let i = interpreter()
        #expect(try i.eval("import G from \"./geometry.swt\"\nG.String()") == .string("G"))
        #expect(try i.eval("G.Type.String()") == .string("Function"))
        #expect(try i.eval("G.area(2.0, 3.0)") == .double(6))
        #expect(try i.eval("G.Point(x: 1.0, y: 2.0).y") == .double(2))
        #expect(throws: SwiftalkError.self) { try i.eval("G()") }
        #expect(throws: SwiftalkError.self) { try i.eval("G(unit: 2.0)") }
        #expect(throws: SwiftalkError.self) { try i.eval("G.nope") }
    }

    @Test("extension M adds statics to a .swt module's namespace, reaching every importer of that module")
    func extendsFile() throws {
        let i = interpreter()
        #expect(try i.eval("import G from \"./geometry.swt\"\nextension G { static let perimeter = { w, h in 2.0 * (w + h) } }\nG.perimeter(2.0, 3.0)") == .double(10))
        #expect(try i.eval("extension G { static let origin = G.Point(x: 0.0, y: 0.0) }\nG.origin.x") == .double(0))
        #expect(try i.eval("import H from \"./geometry.swt\"\nH == G") == .bool(true))       // the same type object, aliased
        #expect(try i.eval("H.perimeter(1.0, 1.0)") == .double(4))
        #expect(try i.eval("H.String()") == .string("G"))                                     // named by its first importer
        #expect(throws: SwiftalkError.self) { try i.eval("extension G { static let area = { 0 } }") }   // an export is taken
    }

    @Test("extension M adds to a native module too — the question that started the round: Net.resolve")
    func extendsNative() throws {
        let i = Swiftalk.Interpreter()
        let net = Swiftalk.Module(name: "Net")
        net.function("get") { args in .string("got \(args.count)") }
        i.register(net)
        #expect(try i.eval("import Net from \"Net\"\nextension Net { static let resolve = { host in \"93.184.216.34\" } }\nNet.resolve(\"example.com\")") == .string("93.184.216.34"))
        #expect(try i.eval("Net.get(1, 2)") == .string("got 2"))
        #expect(try i.eval("extension Net { static var count: Int { 2 } }\nNet.count") == .int(2))
        #expect(throws: SwiftalkError.self) { try i.eval("Net()") }
        // the named forms are untouched
        let j = Swiftalk.Interpreter()
        j.register(net)
        #expect(try j.eval("import (get) from \"Net\"\nget()") == .string("got 0"))
    }
}
