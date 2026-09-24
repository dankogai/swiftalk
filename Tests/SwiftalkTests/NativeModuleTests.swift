import Testing
@testable import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Round 182: native modules — Swift exports imported by a bare name,
// registered in-process or loaded from `lib<name>.dylib` on the module
// path; the core is a dynamic library so both sides share one Value.
struct NativeModuleTests {
    private func greet() -> Swiftalk.Module {
        let m = Swiftalk.Module(name: "greet")
        m.function("hello") { args in
            guard case .string(let who)? = args.first else {
                throw Swiftalk.Error.type("hello(name) takes a String")
            }
            return .string("hello, \(who)")
        }
        m.export("answer", .int(42))
        m.export("answer", .int(41))                   // a re-export replaces
        return m
    }

    @Test("a registered module imports by its bare name: every export, a namespace, the named few; a constant reads, a Function calls, its error is the caller's")
    func registered() throws {
        let a = Swiftalk.Interpreter()
        a.register(greet())
        #expect(try a.eval("import from \"greet\"\nhello(\"world\")") == .string("hello, world"))
        #expect(try a.eval("answer") == .int(41))
        #expect(try a.eval("hello.Type.String()") == .string("Function"))
        let b = Swiftalk.Interpreter()
        b.register(greet())
        #expect(try b.eval("import G from \"greet\"\nG.hello(\"x\")") == .string("hello, x"))
        #expect(try b.eval("G.answer") == .int(41))
        let c = Swiftalk.Interpreter()
        c.register(greet())
        #expect(try c.eval("import (answer) from \"greet\"\nanswer") == .int(41))
        #expect(throws: SwiftalkError.self) { try c.eval("import (nope) from \"greet\"") }
        #expect(throws: SwiftalkError.self) { try c.eval("hello") }          // not imported by (answer)
        let d = Swiftalk.Interpreter()
        d.register(greet())
        #expect(throws: SwiftalkError.self) { try d.eval("import from \"greet\"\nhello(1)") }
    }

    @Test("a bare name nobody registered is an error that says where it looked; a path or a .swt is a file as ever")
    func unresolved() throws {
        #expect(throws: SwiftalkError.self) { try Swiftalk.Interpreter().eval("import from \"nowhere\"") }
        do {
            let i = Swiftalk.Interpreter()
            i.modulePath = ["/nonexistent"]
            try i.eval("import from \"nowhere\"")
            Issue.record("imported nothing")
        } catch let error as SwiftalkError {
            #expect(error.description.contains("/nonexistent"))
            #expect(error.description.contains("./nowhere.swt"))
        }
        #expect(ModuleSystem.isBare("Env"))
        #expect(!ModuleSystem.isBare("./Env"))
        #expect(!ModuleSystem.isBare("Env.swt"))
        #expect(!ModuleSystem.isBare("https://x/Env"))
        #expect(!ModuleSystem.isBare("libEnv" + Swiftalk.Module.librarySuffix))
    }

    @Test("the example module loads from the module path as libEnv: get, set, unset, all, platform; and by its path")
    func dynamic() throws {
        let dir = try #require(buildDirectory(), "no lib\("Env")\(Swiftalk.Module.librarySuffix) beside the test — build it: swift build")
        let i = Swiftalk.Interpreter()
        i.modulePath = ["/nonexistent", dir]
        #expect(try i.eval("import from \"Env\"\nset(\"SWIFTALK_TEST\", \"one\")\nget(\"SWIFTALK_TEST\")") == .string("one"))
        #expect(try i.eval("unset(\"SWIFTALK_TEST\")\nget(\"SWIFTALK_TEST\")") == .nil)
        #expect(try i.eval("all().Type.String()") == .string("[String: String]"))
        #expect(try i.eval("all()[\"PATH\"] == get(\"PATH\")") == .bool(true))
        #expect(try i.eval("platform") == .string(platform))
        #expect(throws: SwiftalkError.self) { try i.eval("get(1)") }
        #expect(throws: SwiftalkError.self) { try i.eval("set(\"A\")") }
        let j = Swiftalk.Interpreter()
        let path = dir + "/" + Swiftalk.Module.fileName(for: "Env")
        #expect(try j.eval("import Env from \"\(path)\"\nEnv.platform") == .string(platform))
        #expect(throws: SwiftalkError.self) { try Swiftalk.Interpreter().eval("import from \"Env\"") }   // an empty module path
        #expect(throws: SwiftalkError.self) { try Swiftalk.Module.load(path: "/nonexistent" + Swiftalk.Module.librarySuffix) }
    }

    private var platform: String {
        #if os(macOS)
        "darwin"
        #else
        "linux"
        #endif
    }

}
