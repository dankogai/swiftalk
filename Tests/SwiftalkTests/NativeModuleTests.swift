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
        try a.register(greet())
        #expect(try a.eval("import from \"greet\"\nhello(\"world\")") == .string("hello, world"))
        #expect(try a.eval("answer") == .int(41))
        #expect(try a.eval("hello.Type.String()") == .string("Function"))
        let b = Swiftalk.Interpreter()
        try b.register(greet())
        #expect(try b.eval("import G from \"greet\"\nG.hello(\"x\")") == .string("hello, x"))
        #expect(try b.eval("G.answer") == .int(41))
        let c = Swiftalk.Interpreter()
        try c.register(greet())
        #expect(try c.eval("import (answer) from \"greet\"\nanswer") == .int(41))
        #expect(throws: SwiftalkError.self) { try c.eval("import (nope) from \"greet\"") }
        #expect(throws: SwiftalkError.self) { try c.eval("hello") }          // not imported by (answer)
        let d = Swiftalk.Interpreter()
        try d.register(greet())
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
        #expect(ModuleSystem.isBare("POSIX"))
        #expect(!ModuleSystem.isBare("./POSIX"))
        #expect(!ModuleSystem.isBare("POSIX.swt"))
        #expect(!ModuleSystem.isBare("https://x/POSIX"))
        #expect(!ModuleSystem.isBare("libPOSIX" + Swiftalk.Module.librarySuffix))
    }

    @Test("the POSIX module loads from the module path as libPOSIX: the environment; and by its path")
    func dynamic() throws {
        let dir = try #require(buildDirectory(), "no libPOSIX beside the test — build it: swift build")
        let i = Swiftalk.Interpreter()
        i.modulePath = ["/nonexistent", dir]
        #expect(try i.eval("import from \"POSIX\"\nsetenv(\"SWIFTALK_TEST\", \"one\")!\ngetenv(\"SWIFTALK_TEST\")") == .string("one"))
        #expect(try i.eval("unsetenv(\"SWIFTALK_TEST\")!\ngetenv(\"SWIFTALK_TEST\")") == .nil)
        #expect(try i.eval("environ().Type.String()") == .string("[String: String]"))
        #expect(try i.eval("environ()[\"PATH\"] == getenv(\"PATH\")") == .bool(true))
        #expect(throws: SwiftalkError.self) { try i.eval("getenv(1)") }
        #expect(throws: SwiftalkError.self) { try i.eval("setenv(\"A\")") }
        let j = Swiftalk.Interpreter()
        let path = dir + "/" + Swiftalk.Module.fileName(for: "POSIX")
        #expect(try j.eval("import POSIX from \"\(path)\"\nPOSIX.getpid() > 0") == .bool(true))
        #expect(throws: SwiftalkError.self) { try Swiftalk.Interpreter().eval("import from \"POSIX\"") }   // an empty module path
        #expect(throws: SwiftalkError.self) { try Swiftalk.Module.load(path: "/nonexistent" + Swiftalk.Module.librarySuffix) }
    }

}
