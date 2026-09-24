# Net

The module of `fetch` and its `Response` (round 185; a top-level
builtin and a prelude struct from round 163 until then; a library,
`modules/Net` built as `libNet.dylib`, since round 189). `import from
"Net"` binds `fetch` and `Response`, `import Net from "Net"` the
namespace: `Net.fetch(url)`, `Net.Response`. **The CLI preimports it**
as its prelude, so `fetch` is simply there; an embedder gets the same
from `Interpreter.preimport()`. The HTTP is **curl** (`-sSL -i`,
redirects followed, through posix_spawn) — unless the host lends a
`fetch` hook, `Interpreter.hooks["fetch"]`: a request Dictionary in
(`url`, `method`, `headers`, `body`), a response Dictionary out
(`status`, `headers`, `body`), a thrown error a `.failure`. A test
stubs the network there; an embedder routes it, or refuses it.

| Form | Meaning |
|---|---|
| `fetch(url)`, `fetch(url, options)` | **JS's `fetch`** (round 163): a **Task** whose value is a **Result** — `.success(Response)` for any HTTP answer (a 404 is a success with `ok == false`), `.failure(message)` when no answer came (DNS, refused, no fetcher). `await` it, then `.then`/`.catch`/`?`/`??`. Options are a Dictionary (JS's object) or a labeled tuple: `method:` (a String, any case), `headers:` (`[String: String]`), `body:` (a String or a Data). The request runs on a worker thread while the task is parked, so several fetches overlap and other tasks run meanwhile. Bad arguments to the call itself throw |
| `Response` | the answer, a struct declared in swiftalk: `status` (Int), `headers` (`[String: String]`, names lowercased), `body` (Data), `ok` (`200 <= status < 300`), `text()` (the body as UTF-8), `json()` (`SION(json:)` of it). Constructible: `Response(status: 204)` |
| `extension Net { static let resolve = { host in ... } }` | the namespace is a type (round 184): what a Swift or swiftalk extension adds sits beside `fetch` |

```swift
let r = (await fetch("https://example.com/data.json"))!
r.status                       // 200
r.headers["content-type"]      // "application/json"
r.json()                       // the document, as a SION value
(await fetch("https://nowhere.invalid/")) ?? nil   // a .failure defaults
```

`Response` is declared in swiftalk, in the module's prelude
([module.md](module.md)); `fetch` is `Swiftalk.spawn` around
`Swiftalk.offload`. See [Task.md](Task.md) for `await` and the
scheduler.
