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
    struct Module {
        let names: [String]
        let values: [Value]
    }
    private let builtins: Environment
    private var cache: [String: Module] = [:]
    private var loading: Set<String> = []
    var baseStack: [String] = ["."]
    /// resolved spec → source. nil: files through POSIX, URLs refused.
    var loader: ((String) throws -> String)? = nil

    init(builtins: Environment) {
        self.builtins = builtins
    }

    func load(_ spec: String) throws -> Module {
        let resolved = ModuleSystem.resolve(spec, base: baseStack.last ?? ".")
        if let module = cache[resolved] { return module }
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
