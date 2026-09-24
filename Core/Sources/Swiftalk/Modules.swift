#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Modules (round 100, §15): `import M from "./mod.swt"` / `import (a, b)
/// from "..."` and `export`. A module is a `.swt` file evaluated once
/// per Interpreter, in strict mode, in a scope of its own whose parent
/// is the builtins — never the importer's globals. Its namespace is a
/// labeled tuple of its exports, in export order (no new type: `M.foo`
/// reads, `M.foo(1)` calls through). Exports are values, copied at
/// import; imported names are `let`s.
final class ModuleSystem {
    final class Module {
        let names: [String]
        let values: [Value]
        /// The namespace `import M from` binds (round 184): a type whose
        /// statics are the exports, made on the first such import and
        /// shared by every later one, so an `extension` of it reaches
        /// all importers — the way a type's does.
        var namespaceType: StructType? = nil

        init(names: [String], values: [Value]) {
            self.names = names
            self.values = values
        }
    }
    private let builtins: Environment
    private var cache: [String: Module] = [:]
    private var loading: Set<String> = []
    var baseStack: [String] = ["."]
    /// Runs on every new module scope before its statements do — the
    /// Interpreter installs the module's own `eval` there (round 123).
    var fileScopeSetup: ((Environment) -> Void)? = nil
    /// resolved spec → source. nil: files through POSIX, URLs refused.
    var loader: ((String) throws -> String)? = nil
    /// Native modules (round 182) by bare name: registered by the
    /// embedder, or loaded from `searchPath` as `lib<name>.dylib`.
    private var native: [String: Module] = [:]
    var searchPath: [String] = []

    init(builtins: Environment) {
        self.builtins = builtins
    }

    /// The type object for a module's namespace (round 184), named by
    /// the first importer's choice; a later `import N from` the same
    /// module binds the same object under `N`, an alias.
    func namespaceType(of module: Module, named name: String) -> StructType {
        if let existing = module.namespaceType { return existing }
        let st = StructType(name: name, propertyOrder: [], properties: [:], declEnv: builtins, isModule: true)
        st.constructor = FunctionObject(parameters: [], body: [], closure: builtins, builtin: nil, role: .structType(st))
        for (export, value) in zip(module.names, module.values) { st.statics[export] = value }
        module.namespaceType = st
        return st
    }

    func register(_ module: Swiftalk.Module) {
        native[module.name] = Module(names: module.names, values: module.values)
    }

    /// A bare spec — no `/`, no `.swt`, not a URL, not a library file —
    /// names a native module (round 182), as `fs` does in Node.
    static func isBare(_ spec: String) -> Bool {
        !isURL(spec) && !spec.contains("/") && !spec.hasSuffix(".swt")
            && !spec.hasSuffix(Swiftalk.Module.librarySuffix)
    }

    func load(_ spec: String) throws -> Module {
        if ModuleSystem.isBare(spec) {
            if let module = native[spec] { return module }
            let file = Swiftalk.Module.fileName(for: spec)
            for dir in searchPath {
                let path = dir + "/" + file
                guard access(path, R_OK) == 0 else { continue }
                let loaded = try Swiftalk.Module.load(path: path)
                register(loaded)
                native[spec] = native[loaded.name]
                return native[spec]!
            }
            let looked = searchPath.isEmpty ? "the module path is empty"
                : "no \(file) on the module path (\(searchPath.joined(separator: ", ")))"
            throw SwiftalkError.type(
                "no module named '\(spec)' — \(looked); a swiftalk file is imported by its path, \"./\(spec).swt\"")
        }
        let resolved = ModuleSystem.resolve(spec, base: baseStack.last ?? ".")
        if let module = cache[resolved] { return module }
        if resolved.hasSuffix(Swiftalk.Module.librarySuffix) {
            // a module library by path (round 182)
            let loaded = try Swiftalk.Module.load(path: resolved)
            let module = Module(names: loaded.names, values: loaded.values)
            cache[resolved] = module
            return module
        }
        guard !loading.contains(resolved) else {
            throw SwiftalkError.type("circular import of '\(resolved)'")
        }
        let source = try loader.map { try $0(resolved) } ?? ModuleSystem.readFile(resolved)
        loading.insert(resolved)
        defer { loading.remove(resolved) }
        baseStack.append(ModuleSystem.directory(of: resolved))
        defer { baseStack.removeLast() }
        let env = Environment(parent: builtins)
        env.isFileScope = true
        fileScopeSetup?(env)
        do {
            var lexer = Lexer(source)
            var parser = Parser(try lexer.tokenize())
            for statement in try parser.parseProgram() {
                _ = try execute(statement, in: env)
            }
        } catch let error as SwiftalkError {
            throw SwiftalkError.type("in module '\(resolved)': \(error.description)")
        } catch is ControlFlow {
            throw SwiftalkError.type("in module '\(resolved)': 'break'/'continue' outside a loop")
        } catch is ReturnSignal {
            throw SwiftalkError.type("in module '\(resolved)': 'return' outside a function")
        }
        let module = Module(names: env.exports, values: try env.exports.map { try env.lookup($0) })
        cache[resolved] = module
        return module
    }

    static func isURL(_ s: String) -> Bool {
        s.hasPrefix("http://") || s.hasPrefix("https://")
    }

    /// A spec against the importing file's directory: URLs and
    /// absolute paths as they are, `./` and `../` folded.
    static func resolve(_ spec: String, base: String) -> String {
        if isURL(spec) || spec.hasPrefix("/") { return spec }
        if isURL(base) {
            return base + "/" + spec.split(separator: "/").filter { $0 != "." }.joined(separator: "/")
        }
        var parts: [String] = base == "." ? [] : base.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for piece in spec.split(separator: "/") {
            switch piece {
            case ".": continue
            case "..":
                if let last = parts.last, last != "..", last != "" { parts.removeLast() } else { parts.append("..") }
            default: parts.append(String(piece))
            }
        }
        return parts.joined(separator: "/")
    }

    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        let dir = String(path[..<slash])
        return dir.isEmpty ? "/" : dir
    }

    /// POSIX, Foundation-free — the same read the CLI does.
    static func readFile(_ path: String) throws -> String {
        guard !isURL(path) else {
            throw SwiftalkError.type("loading '\(path)' needs a module loader — the swiftalk CLI fetches URLs with curl")
        }
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { throw SwiftalkError.type("cannot open module '\(path)'") }
        defer { close(fd) }
        var data: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            data.append(contentsOf: chunk[0..<n])
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// The active ModuleSystem, thread-locally (as the Scheduler's context
/// is): installed by `Interpreter.eval` for its duration.
enum ModuleContext {
    private static let key: pthread_key_t = {
        var k = pthread_key_t()
        pthread_key_create(&k, nil)
        return k
    }()
    static var current: ModuleSystem? {
        guard let p = pthread_getspecific(key) else { return nil }
        return Unmanaged<ModuleSystem>.fromOpaque(p).takeUnretainedValue()
    }
    @discardableResult
    static func activate(_ system: ModuleSystem?) -> ModuleSystem? {
        let previous = current
        pthread_setspecific(key, system.map { Unmanaged.passUnretained($0).toOpaque() })
        return previous
    }
}
