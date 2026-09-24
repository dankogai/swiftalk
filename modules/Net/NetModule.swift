import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// `Net` — `fetch` and its `Response` (round 189; JS's fetch since round
// 163, a core-registered module from 185 until now). Preimported by the
// CLI; `import from "Net"` otherwise. `fetch(url[, options])` is a Task
// whose value is a Result: `.success(Response)` for any HTTP answer,
// `.failure(message)` when none came. The request runs on a worker
// thread while the task is parked, so fetches overlap and other tasks
// run meanwhile. The HTTP is `curl -sSL -i` (posix_spawn, no
// Foundation) — unless the host lends a "fetch" hook
// (`Interpreter.hooks["fetch"]`): a request Dictionary in (url, method,
// headers, body), a response Dictionary out (status, headers, body).
// `Response` is declared in swiftalk, in the module's prelude.

/// What `fetch` asks for: `fetch(url)`, `fetch(url, options)` — options
/// a Dictionary (JS's object) or a labeled tuple: `method:`, `headers:`,
/// `body:` (a String or a Data).
struct Request {
    let url: String
    var method = "GET"
    var headers: [String: String] = [:]
    var body: [UInt8]? = nil

    init(arguments args: [Swiftalk.Value]) throws {
        guard (1...2).contains(args.count), case .string(let url) = args[0] else {
            throw Swiftalk.Error.type("fetch(url) or fetch(url, options) — the url a String")
        }
        self.url = url
        guard args.count == 2 else { return }
        let options: [(String, Swiftalk.Value)]
        switch args[1] {
        case .dictionary(let d, _):
            options = try d.map { pair in
                guard case .string(let key) = pair.key else {
                    throw Swiftalk.Error.type("fetch options: String keys — method, headers, body")
                }
                return (key, pair.value)
            }
        case .tuple(let t):
            options = try zip(t.labels, t.values).map { label, value in
                guard let label else { throw Swiftalk.Error.type("fetch options: a labeled tuple — (method:, headers:, body:)") }
                return (label, value)
            }
        default:
            throw Swiftalk.Error.type("fetch options are a Dictionary or a labeled tuple, not a \(args[1].typeName)")
        }
        for (key, value) in options {
            switch (key, value) {
            case ("method", .string(let m)):    method = m.uppercased()
            case ("headers", .dictionary(let d, _)):
                for (k, v) in d {
                    guard case .string(let name) = k, case .string(let text) = v else {
                        throw Swiftalk.Error.type("fetch headers: [String: String]")
                    }
                    headers[name] = text
                }
            case ("body", .string(let s)):      body = Array(s.utf8)
            case ("body", .data(let bytes)):    body = bytes
            case ("body", .nil):                body = nil
            default:
                throw Swiftalk.Error.type("fetch option '\(key)': method (String), headers ([String: String]), body (String or Data)")
            }
        }
    }

    /// The hook's argument: a Dictionary of the request.
    var value: Swiftalk.Value {
        .dictionary([
            .string("url"): .string(url), .string("method"): .string(method),
            .string("headers"): .dictionary(Dictionary(uniqueKeysWithValues: headers.map { (.string($0.key), .string($0.value)) })),
            .string("body"): body.map { .data($0) } ?? .nil,
        ])
    }
}

struct Answer {
    var status = 0
    var headers: [String: String] = [:]
    var body: [UInt8] = []

    /// The hook's answer: a Dictionary with status, headers, body.
    init(value: Swiftalk.Value) throws {
        guard case .dictionary(let d, _) = value else {
            throw Swiftalk.Error.type("the fetch hook must answer a Dictionary (status, headers, body), not a \(value.typeName)")
        }
        if case .int(let s)? = d[.string("status")] { status = Int(s) }
        if case .dictionary(let h, _)? = d[.string("headers")] {
            for (k, v) in h {
                if case .string(let name) = k, case .string(let text) = v { headers[name] = text }
            }
        }
        switch d[.string("body")] {
        case .data(let bytes)?: body = bytes
        case .string(let s)?:   body = Array(s.utf8)
        default: break
        }
    }
    init(status: Int, headers: [String: String], body: [UInt8]) {
        self.status = status; self.headers = headers; self.body = body
    }
}

/// The `Response` type, declared in swiftalk: a struct with what JS's
/// has, as swiftalk spells it.
let prelude = """
    export struct Response {
        var status: Int = 0
        var headers: [String: String] = [:]
        var body: Data = Data()
        var ok { 200 <= .status && .status < 300 }
        let text = { .body.String(.utf8) }
        let json = { SION(json: .body.String(.utf8)!) }
    }
    """

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "Net")
    m.prelude = prelude
    m.function("fetch") { args in
        let request = try Request(arguments: args)
        let hook = Swiftalk.hook("fetch")                       // resolved here: the worker thread has no Interpreter
        guard let responseType = m.value(named: "Response") else {
            throw Swiftalk.Error.type("fetch: the Response type is missing")
        }
        return try Swiftalk.spawn {
            let outcome: Result<Answer, Swift.Error> = try Swiftalk.offload {
                Result {
                    if let hook { return try Answer(value: try hook([request.value])) }
                    return try fetchWithCurl(request)
                }
            }
            switch outcome {
            case .failure(let error):
                return .failure((error as? Swiftalk.Error)?.description ?? "\(error)")
            case .success(let answer):
                var headers: [Swiftalk.Value: Swiftalk.Value] = [:]
                for (k, v) in answer.headers { headers[.string(k.lowercased())] = .string(v) }
                let response = try Swiftalk.call(responseType, labeled: [
                    ("status", .int(Int64(answer.status))), ("headers", .dictionary(headers)), ("body", .data(answer.body))])
                return .success(response)
            }
        }
    }
    return m
}

// ---- curl (round 163's transport, the CLI's until round 189) ----

/// Runs curl with `args`: stdout comes back as bytes; `input`, if any,
/// goes to curl's stdin. posix_spawn and pipes, no Foundation.
func runCurl(_ args: [String], input: [UInt8]? = nil) throws -> [UInt8] {
    var out: [Int32] = [0, 0]
    var inp: [Int32] = [0, 0]
    guard pipe(&out) == 0, pipe(&inp) == 0 else { throw Swiftalk.Error.type("curl: pipe failed") }
    #if canImport(Darwin)
    var actions: posix_spawn_file_actions_t? = nil      // an opaque pointer on Darwin
    #else
    var actions = posix_spawn_file_actions_t()
    #endif
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_adddup2(&actions, out[1], 1)
    posix_spawn_file_actions_adddup2(&actions, out[1], 2)      // curl's own message rides along; it is the error text on failure
    posix_spawn_file_actions_adddup2(&actions, inp[0], 0)
    for fd in [out[0], out[1], inp[0], inp[1]] { posix_spawn_file_actions_addclose(&actions, fd) }
    var argv: [UnsafeMutablePointer<CChar>?] = []
    for a in ["curl"] + args { argv.append(strdup(a)) }
    argv.append(nil)
    defer { for p in argv { free(p) } }
    var pid: pid_t = 0
    let rc = posix_spawnp(&pid, "curl", &actions, nil, argv, nil)
    posix_spawn_file_actions_destroy(&actions)
    close(out[1]); close(inp[0])
    guard rc == 0 else { close(out[0]); close(inp[1]); throw Swiftalk.Error.type("cannot run curl: \(String(cString: strerror(rc)))") }
    if let input {
        var written = 0
        while written < input.count {
            let n = input[written...].withUnsafeBufferPointer { write(inp[1], $0.baseAddress, $0.count) }
            if n <= 0 { break }
            written += n
        }
    }
    close(inp[1])
    var data: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = read(out[0], &chunk, chunk.count)
        guard n > 0 else { break }
        data.append(contentsOf: chunk[0..<n])
    }
    close(out[0])
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    let exitCode = (status >> 8) & 0xff
    guard exitCode == 0 else {
        throw Swiftalk.Error.type(String(decoding: data, as: UTF8.self).split(separator: "\n").last.map(String.init) ?? "curl exited with \(exitCode)")
    }
    return data
}

/// `curl -sSL -i`, the response parsed here — the last header block's
/// status line and headers (redirects and `100 Continue` leave earlier
/// blocks), the rest the body.
func fetchWithCurl(_ request: Request) throws -> Answer {
    var args = ["-sS", "-L", "-i", "-X", request.method]
    for (name, value) in request.headers.sorted(by: { $0.key < $1.key }) { args += ["-H", "\(name): \(value)"] }
    if request.body != nil { args += ["--data-binary", "@-"] }
    args.append(request.url)
    let raw = try runCurl(args, input: request.body)
    var rest = raw[...]
    var status = 0
    var headers: [String: String] = [:]
    while rest.starts(with: Array("HTTP/".utf8)) {
        var end = rest.startIndex
        var blank: Range<Int>? = nil
        while end < rest.endIndex {
            if rest[end] == 10 {
                let lineEnd = end
                let next = end + 1
                if next < rest.endIndex, rest[next] == 10 { blank = lineEnd..<(next + 1); break }
                if next + 1 < rest.endIndex, rest[next] == 13, rest[next + 1] == 10 { blank = lineEnd..<(next + 2); break }
            }
            end += 1
        }
        let blockEnd = blank?.lowerBound ?? rest.endIndex
        let block = String(decoding: rest[rest.startIndex..<blockEnd], as: UTF8.self)
        status = 0
        headers = [:]
        for (n, line) in block.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).enumerated() {
            let line = line.hasSuffix("\r") ? String(line.dropLast()) : String(line)
            if n == 0 {
                let parts = line.split(separator: " ")
                if parts.count > 1 { status = Int(parts[1]) ?? 0 }
            } else if let colon = line.firstIndex(of: ":") {
                headers[line[..<colon].lowercased()] = String(line[line.index(after: colon)...].drop(while: { $0 == " " || $0 == "\t" }))
            }
        }
        rest = rest[(blank?.upperBound ?? rest.endIndex)...]
    }
    return Answer(status: status, headers: headers, body: Array(rest))
}

/// The entry point the interpreter calls after dlopen.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
