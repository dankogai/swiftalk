#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public extension Swiftalk.Value {
    /// `.success(v)` / `.failure(m)` as Values (round 188) — see `Swiftalk.success`.
    static func success(_ value: Swiftalk.Value) -> Swiftalk.Value { Swiftalk.success(value) }
    static func failure(_ message: String) -> Swiftalk.Value { Swiftalk.failure(message) }
}

public extension Swiftalk.HostValue {
    func patternMatch(_ subject: Swiftalk.Value, binding: Bool) throws -> Swiftalk.Value? {
        if binding { throw Swiftalk.Error.type("a \(typeName) cannot be a case binding's source") }
        return nil
    }
    func setMember(_ name: String, to value: Swiftalk.Value) throws -> Bool { false }
}

extension Swiftalk {
    /// A value a module owns (round 186): `Value.host(object)`. The core
    /// knows nothing of what it holds — the object answers for its
    /// type, its members, equality, printing, and `switch` matching.
    /// A `Regex` is the first: the engine lives in the Regex module and
    /// the core keeps only the literal's grammar.
    public protocol HostValue: AnyObject {
        /// The type's name — what `.Type.name` and error messages say.
        var typeName: String { get }
        /// The type value itself — what `x.Type` answers: the Function
        /// `Module.type(_:_:)` returned.
        var type: Value { get }
        /// `x.name` (`called` false) or `x.name(args)` (true): nil when
        /// the value has no such member — the core's universal members
        /// (`.Type`, `.String()`, `==`) then answer, or it is an error.
        func member(_ name: String, args: [Value], called: Bool) throws -> Value?
        func isEqual(to other: any HostValue) -> Bool
        func hash(into hasher: inout Hasher)
        /// The source form: what prints, what the REPL echoes, what
        /// `.String()` gives — and what re-enters, where it can.
        func sourceString(debug: Bool) -> String
        /// `switch subject { case pattern: }` and `case let m = pattern`
        /// (Swift's `~=`): nil is no match; a value is a match, and what
        /// the binding form binds. `binding` tells the two apart, so a
        /// wrong subject type can be no match for the one and an error
        /// for the other. The default never matches.
        func patternMatch(_ subject: Value, binding: Bool) throws -> Value?
        /// `x.name = value` (round 191): true when the object took it,
        /// false when the member is not assignable — an error then. The
        /// default takes nothing.
        func setMember(_ name: String, to value: Value) throws -> Bool
    }

    /// A `Result` for a module to answer with (round 188): `.success(v)`
    /// and `.failure(message)` — what `fetch` gives, what `!`, `?`, `??`,
    /// `.then`, `.catch` take.
    public static func success(_ value: Value) -> Value {
        try! constructEnumCase(Builtins.resultType, "success", args: [(nil, value)], called: true)
    }
    public static func failure(_ message: String) -> Value {
        try! constructEnumCase(Builtins.resultType, "failure", args: [(nil, .string(message))], called: true)
    }

    /// Calls a swiftalk Function value from a module (round 186): the
    /// arguments unlabeled, in order.
    public static func call(_ function: Value, _ args: [Value]) throws -> Value {
        try call(function, labeled: args.map { (label: nil, value: $0) })
    }

    /// The same with labels (round 189) — a struct's memberwise init,
    /// `Response(status:headers:body:)`, wants them.
    public static func call(_ function: Value, labeled args: [(label: String?, value: Value)]) throws -> Value {
        guard case .function(let fn) = function else {
            throw Swiftalk.Error.type("cannot call a \(function.typeName)")
        }
        return try apply(fn, args: args)
    }

    /// Writes to the running Interpreter's output (round 189) — where
    /// `print` goes: `Interpreter.output`, stdout unless the embedder
    /// redirected it. With no Interpreter running, stdout.
    public static func output(_ text: String) {
        if let sink = Interpreter.current?.output {
            sink(text)
        } else {
            _ = Array(text.utf8).withUnsafeBufferPointer { write(1, $0.baseAddress, $0.count) }
        }
    }

    /// Writes to the running Interpreter's error output (round 191) —
    /// where `debugPrint` goes: `Interpreter.errorOutput`, stderr unless
    /// the embedder redirected it.
    public static func errorOutput(_ text: String) {
        if let sink = Interpreter.current?.errorOutput {
            sink(text)
        } else {
            writeStandardError(text)
        }
    }

    /// stderr, raw (round 191) — the default `Interpreter.errorOutput`.
    static func writeStandardError(_ text: String) {
        _ = Array(text.utf8).withUnsafeBufferPointer { write(2, $0.baseAddress, $0.count) }
    }

    /// A lazy Sequence a module makes (round 191): `make` is called once
    /// per iteration and returns the puller — a Value per pull, nil at
    /// the end. `.Type` is Sequence; `for`, `map`, `prefix`, `Array()`
    /// all apply. A file handle's `lines` reads from where the handle
    /// is, so iterating it twice reads on, not again.
    public static func sequence(_ make: @escaping () -> () throws -> Value?) -> Value {
        .sequence(SequenceObject(kind: .native(make: make)))
    }

    /// A value's display text (round 189): a String bare, everything
    /// else its source form — with a type's own `String` member
    /// speaking (round 152). What `print` writes; `sourceString(debug:)`
    /// on the Value is `debugPrint`'s.
    public static func display(_ value: Value) throws -> String {
        try displayString(value)
    }

    /// A host hook the running Interpreter provides (round 189):
    /// `Interpreter.hooks[name]` — Values in, a Value out, the host's
    /// business (the Net module's `fetch` asks for "fetch" and falls
    /// back to curl). Resolve it before `offload`: a worker thread has
    /// no running Interpreter.
    public static func hook(_ name: String) -> (([Value]) throws -> Value)? {
        Interpreter.current?.hooks[name]
    }

    /// A Task running `body` (round 189): eager, the JS way, parked at
    /// its suspension points — what a module's asynchronous answer is.
    /// An error when no task context is running (a coroutine body).
    public static func spawn(_ body: @escaping () throws -> Value) throws -> Value {
        guard let ctx = Scheduler.current else {
            throw Swiftalk.Error.type("a Task cannot be spawned here (inside a Sequence coroutine body)")
        }
        let fn = FunctionObject(parameters: [], body: [], closure: Environment(), builtin: { _ in try body() })
        return try ctx.scheduler.spawn(fn, from: ctx)
    }

    /// Runs blocking `work` on a worker thread while the current task is
    /// parked (round 189; round 163's mechanism) — other tasks run
    /// meanwhile, and the result comes back when `work` returns. The
    /// work must not touch interpreter state.
    public static func offload<T>(_ work: @escaping () -> T) throws -> T {
        guard let ctx = Scheduler.current else {
            throw Swiftalk.Error.type("blocking work cannot be offloaded here (inside a Sequence coroutine body)")
        }
        return try ctx.scheduler.offload(from: ctx, work)
    }

    /// A native module (round 182): exports written in Swift, imported
    /// by a bare name — `import (getenv) from "POSIX"` — the way a `.swt`
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

        /// Exports a TYPE (round 186): a name that constructs — `Regex(pattern)`,
        /// `Regex(pattern, flags)` — and answers for the values it makes
        /// (`x.Type`). `construct` receives the call's arguments in order,
        /// labels dropped; round 47's law holds, so `x.Name(args)` is
        /// `Name(x, args)`. The returned Value is the type: hand it to the
        /// values you make, for their `type`.
        @discardableResult
        public func type(_ name: String, _ construct: @escaping ([Value]) throws -> Value) -> Value {
            let fn = FunctionObject(parameters: [], body: [], closure: Environment(), builtin: construct, role: .type(name))
            let value = Value.function(fn)
            export(name, value)
            return value
        }

        /// Extends a CORE type (round 186): `String.firstMatch` for the
        /// Regex module. `body` sees the receiver, the arguments (labels
        /// dropped), and whether the member was called; returning nil
        /// DECLINES, and the core's own member, if any, answers — so a
        /// module adds an argument type to an existing method
        /// (`s.contains(/re/)`) and leaves the rest as it was. In force
        /// for the whole program (round 147's rule) from the moment the
        /// module is registered or loaded.
        public func extend(_ typeName: String, _ member: String,
                           _ body: @escaping (_ receiver: Value, _ args: [Value], _ called: Bool) throws -> Value?) {
            extensions.append((typeName, member, body))
        }
        public private(set) var extensions: [(type: String, member: String, body: (Value, [Value], Bool) throws -> Value?)] = []

        /// A static on a type the module exports (round 191): `IO.stdin`.
        /// Read off the type, never called; a Function value is a static
        /// method.
        public func `static`(_ typeName: String, _ name: String, _ value: Value) {
            statics.append((typeName, name, value))
        }
        public private(set) var statics: [(type: String, name: String, value: Value)] = []

        /// swiftalk source the module ships (round 189): evaluated once,
        /// when the module is registered or loaded, in a file scope of
        /// its own whose parent is the builtins; what it `export`s joins
        /// the exports — `Net`'s `Response` is a struct declared here.
        /// `value(named:)` reads them back from Swift.
        public var prelude: String? = nil

        /// An export by name — including what the prelude declared.
        public func value(named name: String) -> Value? {
            names.firstIndex(of: name).map { values[$0] }
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
