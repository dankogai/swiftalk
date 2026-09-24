import Testing
@testable import Swiftalk
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Round 163: `fetch(url[, options])` — a Task whose value is a Result of
/// a `Response`; the HTTP is the host's (`Interpreter.fetcher`), stubbed
/// here, so no network is touched.
@Suite("fetch() — JS's, as a Task of a Result (round 163)")
struct FetchTests {
    /// A fetcher answering from a table, recording what it was asked.
    final class Stub: @unchecked Sendable {
        var requests: [Swiftalk.FetchRequest] = []
        var answers: [String: Swiftalk.FetchResponse] = [:]
        var delay: UInt32 = 0
        /// (start, finish) per request, for the overlap test — written on
        /// worker threads, so under a lock.
        var spans: [(start: Double, finish: Double)] = []
        private var lock = pthread_mutex_t()
        init() { pthread_mutex_init(&lock, nil) }
        static func now() -> Double {
            var ts = timespec(); clock_gettime(CLOCK_REALTIME, &ts)
            return Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9
        }
        func fetch(_ request: Swiftalk.FetchRequest) throws -> Swiftalk.FetchResponse {
            let start = Stub.now()
            pthread_mutex_lock(&lock); requests.append(request); pthread_mutex_unlock(&lock)
            if delay > 0 { usleep(delay) }
            pthread_mutex_lock(&lock); spans.append((start, Stub.now())); pthread_mutex_unlock(&lock)
            guard let answer = answers[request.url] else { throw SwiftalkError.type("no route to \(request.url)") }
            return answer
        }
    }
    func interpreter(_ stub: Stub) -> Swiftalk.Interpreter {
        let i = try! SwiftalkTests.interpreter()
        i.fetcher = stub.fetch
        return i
    }

    @Test("a Task; await gives a Result; the Response has status, ok, headers (lowercased), body, text(), json()")
    func response() throws {
        let stub = Stub()
        stub.answers["https://x/json"] = .init(status: 200, headers: ["Content-Type": "application/json"], body: Array("{\"a\": [1, 2]}".utf8))
        stub.answers["https://x/missing"] = .init(status: 404, body: Array("gone".utf8))
        let i = interpreter(stub)
        #expect(try i.eval("fetch(\"https://x/json\").Type == Task") == .bool(true))
        #expect(try i.eval("(await fetch(\"https://x/json\")).Type == Result") == .bool(true))
        #expect(try i.eval("let r = (await fetch(\"https://x/json\"))!\n[r.status, r.ok, r.headers[\"content-type\"], r.text()]") == .array([.int(200), .bool(true), .string("application/json"), .string("{\"a\": [1, 2]}")]))
        #expect(try i.eval("(await fetch(\"https://x/json\")).then { $0.json()[\"a\"] }.catch { _ in nil }") == .array([.int(1), .int(2)]))
        #expect(try i.eval("(await fetch(\"https://x/missing\")).then { [$0.status, $0.ok, $0.text()] }") == (try i.eval("Result.success([404, false, \"gone\"])")))
        #expect(try i.eval("(await fetch(\"https://x/json\"))!.Type == Response") == .bool(true))
        #expect(try i.eval("Response(status: 204).ok && Response().text() == \"\"") == .bool(true))       // the prelude type, constructible
    }

    @Test("failures are .failure(message): no route, a throwing fetcher, no fetcher at all")
    func failures() throws {
        let stub = Stub()
        let i = interpreter(stub)
        #expect(try i.eval("(await fetch(\"https://x/nope\")).failure") == .string("type error: no route to https://x/nope"))
        #expect(try i.eval("(await fetch(\"https://x/nope\")).catch { err in \"failed: \" + err }") == .string("failed: type error: no route to https://x/nope"))
        #expect(try i.eval("(await fetch(\"https://x/nope\")) ?? 0") == .int(0))
        let bare = try SwiftalkTests.interpreter()   // the prelude, but no fetcher
        #expect(try bare.eval("(await fetch(\"https://x/\")).failure != nil") == .bool(true))
        #expect(try bare.eval("(await fetch(\"https://x/\")).failure.contains(\"fetcher\")") == .bool(true))
    }

    @Test("options: a Dictionary or a labeled tuple — method, headers, body (String or Data); the call's own errors throw")
    func options() throws {
        let stub = Stub()
        stub.answers["https://x/post"] = .init(status: 201)
        let i = interpreter(stub)
        #expect(try i.eval("(await fetch(\"https://x/post\", [\"method\": \"post\", \"headers\": [\"X-A\": \"1\"], \"body\": \"hi\"])).then { $0.status }") == (try i.eval("Result.success(201)")))
        #expect(stub.requests.last?.method == "POST")
        #expect(stub.requests.last?.headers == ["X-A": "1"])
        #expect(stub.requests.last?.body == Array("hi".utf8))
        #expect(try i.eval("(await fetch(\"https://x/post\", (method: \"PUT\", body: \"hi\".Data(.utf8)))).then { $0.status }") == (try i.eval("Result.success(201)")))
        #expect(stub.requests.last?.method == "PUT")
        #expect(stub.requests.last?.body == Array("hi".utf8))
        #expect(try i.eval("(await fetch(\"https://x/post\"))!.status") == .int(201))
        #expect(stub.requests.last?.method == "GET")
        #expect(stub.requests.last?.body == nil)
        #expect(throws: SwiftalkError.self) { try i.eval("fetch(1)") }
        #expect(throws: SwiftalkError.self) { try i.eval("fetch()") }
        #expect(throws: SwiftalkError.self) { try i.eval("fetch(\"https://x/post\", [\"method\": 1])") }
        #expect(throws: SwiftalkError.self) { try i.eval("fetch(\"https://x/post\", [\"bogus\": 1])") }
        #expect(throws: SwiftalkError.self) { try i.eval("fetch(\"https://x/post\", 1)") }
    }

    @Test("fetches overlap: the request runs on a worker thread while the task is parked, so other tasks run meanwhile")
    func overlap() throws {
        let stub = Stub()
        stub.delay = 150_000                                    // 0.15 s per request
        stub.answers["https://x/a"] = .init(status: 200)
        stub.answers["https://x/b"] = .init(status: 200)
        let i = interpreter(stub)
        #expect(try i.eval("let a = fetch(\"https://x/a\")\nlet b = fetch(\"https://x/b\")\nvar ticks = 0\nlet t = async { while ticks < 3 { ticks += 1; Task.sleep(0.01) } }\n[(await a)!.status, (await b)!.status, await t, ticks]") == .array([.int(200), .int(200), .nil, .int(3)]))
        #expect(stub.requests.count == 2)
        // Structural, not a stopwatch (a loaded CI runner is no judge of
        // wall time): the second request began before the first ended.
        let spans = stub.spans.sorted { $0.start < $1.start }
        #expect(spans.count == 2)
        if spans.count == 2 {
            #expect(spans[1].start < spans[0].finish, "the fetches ran one after the other: \(spans)")
        }
    }
}
