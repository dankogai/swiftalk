#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension Swiftalk {
    /// A native module (round 182): exports written in Swift, imported
    /// by a bare name — `import (get) from "Env"` — the way a `.swt`
    /// file's are by its path. A module is a name and an ordered list of
    /// exports; each export is an ordinary Value, so a Swift closure
    /// becomes a swiftalk Function and a constant is just a value.
    ///
    /// Two ways in. An embedder builds one and calls
    /// `Interpreter.register(_:)`. Or the same module is compiled as a
    /// dynamic library exporting one C symbol, `swiftalk_module`, whose
    /// return value is `entryPoint()`; the interpreter finds
    /// `lib<Name>.dylib` (`.so` on Linux) on its `modulePath` and loads
    /// it with dlopen. Both sides must link the ONE `libSwiftalk` —
    /// which is why the core is a dynamic library product of its own
    /// package.
    ///
    /// ```swift
    /// import Swiftalk
    /// func build() -> Swiftalk.Module {
    ///     let m = Swiftalk.Module(name: "Greet")
    ///     m.function("hello") { args in
    ///         guard case .string(let who)? = args.first else {
    ///             throw Swiftalk.Error.type("hello(name) takes a String")
    ///         }
    ///         return .string("hello, \(who)")
    ///     }
    ///     m.export("answer", .int(42))
    ///     return m
    /// }
    /// @_cdecl("swiftalk_module")
    /// public func swiftalkModule() -> UnsafeMutableRawPointer { build().entryPoint() }
    /// ```
    public final class Module {
        public let name: String
        public private(set) var names: [String] = []
        public private(set) var values: [Value] = []

        public init(name: String) {
            self.name = name
        }

        /// Exports a value under a name; exporting the name again
        /// replaces the value in place.
        public func export(_ name: String, _ value: Value) {
            if let i = names.firstIndex(of: name) {
                values[i] = value
            } else {
                names.append(name)
                values.append(value)
            }
        }

        /// Exports a Function: `body` receives the call's arguments in
        /// order, labels dropped, and what it returns is the call's
        /// value; a thrown `Swiftalk.Error` is the caller's error.
        public func function(_ name: String, _ body: @escaping ([Value]) throws -> Value) {
            export(name, .function(FunctionObject(parameters: [], body: [], closure: Environment(), builtin: body)))
        }

        /// The C symbol a module library exports.
        public static let entrySymbol = "swiftalk_module"

        /// `.dylib` on Darwin, `.so` elsewhere.
        public static let librarySuffix: String = {
            #if os(macOS)
            return ".dylib"
            #else
            return ".so"
            #endif
        }()

        /// The file a bare name resolves to on the module path:
        /// `lib<Name>.dylib` — what SwiftPM builds for a dynamic library
        /// product of that name. Names take a capital by convention
        /// (round 183); nothing here checks it.
        public static func fileName(for name: String) -> String {
            "lib\(name)\(librarySuffix)"
        }

        /// What `swiftalk_module` returns: the module, retained, as a
        /// raw pointer the C boundary can carry. `load(path:)` takes the
        /// retain back.
        public func entryPoint() -> UnsafeMutableRawPointer {
            Unmanaged.passRetained(self).toOpaque()
        }

        /// Loads a module library: dlopen, the entry symbol, one call.
        public static func load(path: String) throws -> Module {
            guard let handle = dlopen(path, RTLD_NOW) else {
                let why = dlerror().map { String(cString: $0) } ?? "dlopen failed"
                throw Swiftalk.Error.type("cannot load module '\(path)': \(why)")
            }
            guard let symbol = dlsym(handle, entrySymbol) else {
                throw Swiftalk.Error.type("'\(path)' is not a swiftalk module — it exports no \(entrySymbol)")
            }
            let entry = unsafeBitCast(symbol, to: (@convention(c) () -> UnsafeMutableRawPointer).self)
            return Unmanaged<Module>.fromOpaque(entry()).takeRetainedValue()
        }
    }
}
