/// `fetch` (round 163), JS's, at the top level: `fetch(url)` and
/// `fetch(url, options)` return a Task whose value is a Result —
/// `.success(Response)` for any HTTP answer (`ok` says whether it was
/// a 2xx), `.failure(message)` when no answer came. The core is
/// Foundation-free, so the HTTP itself is the host's: an embedder sets
/// `Interpreter.fetcher`; the CLI supplies curl. The request runs on a
/// worker thread while the swiftalk task is parked, so other tasks run
/// meanwhile and several fetches overlap.
extension Swiftalk {
    /// What `fetch` asks the host for.
    public struct FetchRequest {
        public let url: String
        public let method: String
        public let headers: [String: String]
        public let body: [UInt8]?
        public init(url: String, method: String = "GET", headers: [String: String] = [:], body: [UInt8]? = nil) {
            self.url = url
            self.method = method
            self.headers = headers
            self.body = body
        }
    }

    /// What the host answers with. Header names are lowercased by the
    /// core when it builds the `Response`.
    public struct FetchResponse {
        public let status: Int
        public let headers: [String: String]
        public let body: [UInt8]
        public init(status: Int, headers: [String: String] = [:], body: [UInt8] = []) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }
}

extension Swiftalk.FetchRequest {
    /// `fetch(url)`, `fetch(url, options)` — options a Dictionary (JS's
    /// object) or a labeled tuple: `method:`, `headers:`, `body:` (a
    /// String or a Data).
    init(arguments args: [Value]) throws {
        guard (1...2).contains(args.count), case .string(let url) = args[0] else {
            throw SwiftalkError.type("fetch(url) or fetch(url, options) — the url a String")
        }
        var method = "GET"
        var headers: [String: String] = [:]
        var body: [UInt8]? = nil
        if args.count == 2 {
            let options: [(String, Value)]
            switch args[1] {
            case .dictionary(let d):
                options = try d.map { pair in
                    guard case .string(let key) = pair.key else {
                        throw SwiftalkError.type("fetch options: String keys — method, headers, body")
                    }
                    return (key, pair.value)
                }
            case .tuple(let t):
                options = try zip(t.labels, t.values).map { label, value in
                    guard let label else { throw SwiftalkError.type("fetch options: a labeled tuple — (method:, headers:, body:)") }
                    return (label, value)
                }
            default:
                throw SwiftalkError.type("fetch options are a Dictionary or a labeled tuple, not a \(args[1].typeName)")
            }
            for (key, value) in options {
                switch (key, value) {
                case ("method", .string(let m)):    method = m.uppercased()
                case ("headers", .dictionary(let d)):
                    for (k, v) in d {
                        guard case .string(let name) = k, case .string(let text) = v else {
                            throw SwiftalkError.type("fetch headers: [String: String]")
                        }
                        headers[name] = text
                    }
                case ("body", .string(let s)):      body = Array(s.utf8)
                case ("body", .data(let bytes)):    body = bytes
                case ("body", .nil):                body = nil
                default:
                    throw SwiftalkError.type("fetch option '\(key)': method (String), headers ([String: String]), body (String or Data)")
                }
            }
        }
        self.init(url: url, method: method, headers: headers, body: body)
    }
}

/// The `Response` type, declared in swiftalk itself at startup — the
/// first prelude: a struct with what JS's has, as swiftalk spells it.
let fetchPrelude = """
    struct Response {
        var status: Int = 0
        var headers: [String: String] = [:]
        var body: Data = Data()
        var ok { 200 <= .status && .status < 300 }
        let text = { .body.String(.utf8) }
        let json = { SION(json: .body.String(.utf8)!) }
    }
    """
