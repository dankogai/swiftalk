import Testing
@testable import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Round 188: the POSIX module — file I/O, directories, the process —
// every failure a .failure(message), every success a .success(value).
struct POSIXTests {
    private func interpreter() throws -> Swiftalk.Interpreter {
        let i = Swiftalk.Interpreter()
        i.modulePath = [try #require(buildDirectory())]
        _ = try i.eval("import from \"POSIX\"")
        return i
    }
    private var scratch: String {
        let base = getenv("TMPDIR").map { String(cString: $0) } ?? "/tmp"
        return (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/swiftalk-posix-\(getpid())"
    }

    @Test("files: writeFile, readFile, stat, open/write/lseek/read/close, rename, unlink; directories: mkdir, readdir, rmdir; the process: getcwd, chdir, getpid, uname")
    func files() throws {
        let i = try interpreter()
        let dir = scratch
        _ = try i.eval("let dir = \"\(dir)\"")
        #expect(try i.eval("mkdir(dir)") == (try i.eval("Result.success(nil)")))
        #expect(try i.eval("stat(dir)![\"isDirectory\"]") == .bool(true))
        #expect(try i.eval("writeFile(dir + \"/a.txt\", \"hello\\n\")!") == .int(6))
        #expect(try i.eval("readFile(dir + \"/a.txt\")!.String(.utf8)") == .string("hello\n"))
        #expect(try i.eval("readFile(dir + \"/a.txt\")!.Type == Data") == .bool(true))
        #expect(try i.eval("stat(dir + \"/a.txt\").then { [$0[\"size\"], $0[\"isFile\"], $0[\"mtime\"].Type == Date] }!") == .array([.int(6), .bool(true), .bool(true)]))
        #expect(try i.eval("let fd = open(dir + \"/a.txt\", [O_WRONLY, O_APPEND])!\nwrite(fd, Data([119, 111, 114, 108, 100]))!") == .int(5))
        #expect(try i.eval("close(fd)!") == .nil)
        #expect(try i.eval("let r = open(dir + \"/a.txt\")!\nlseek(r, 6)!") == .int(6))
        #expect(try i.eval("read(r, 3)!.String(.utf8)") == .string("wor"))
        #expect(try i.eval("read(r)!.String(.utf8)") == .string("ld"))
        #expect(try i.eval("read(r)!.count") == .int(0))                                   // EOF
        #expect(try i.eval("close(r)!") == .nil)
        #expect(try i.eval("readdir(dir)!") == .array([.string("a.txt")], lock: TypeAnnotation("Array", parameters: [TypeAnnotation("String")])))
        #expect(try i.eval("readdir(dir)!.Type.String()") == .string("[String]"))
        #expect(try i.eval("rename(dir + \"/a.txt\", dir + \"/b.txt\")!") == .nil)
        #expect(try i.eval("readdir(dir)!") == .array([.string("b.txt")]))
        #expect(try i.eval("let here = getcwd()!\nchdir(dir)!\nlet moved = getcwd()!\nchdir(here)!\nmoved.contains(\"swiftalk-posix-\")") == .bool(true))
        #expect(try i.eval("unlink(dir + \"/b.txt\")!") == .nil)
        #expect(try i.eval("rmdir(dir)!") == .nil)
        #expect(try i.eval("getpid() > 0") == .bool(true))
        #expect(try i.eval("[\"Darwin\", \"Linux\"].contains(uname()![\"sysname\"])") == .bool(true))
        #expect(try i.eval("[O_RDONLY, SEEK_SET, STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO]") == .array([.int(0), .int(0), .int(0), .int(1), .int(2)]))
    }

    @Test("failures are .failure(message) with strerror's words; wrong arguments are the caller's type errors")
    func failures() throws {
        let i = try interpreter()
        #expect(try i.eval("readFile(\"/nonexistent/x\").failure") == .string("readFile(/nonexistent/x): No such file or directory"))
        #expect(try i.eval("open(\"/nonexistent/x\") ?? -1") == .int(-1))
        #expect(try i.eval("stat(\"/nonexistent\").failure.contains(\"No such file\")") == .bool(true))
        #expect(try i.eval("readdir(\"/nonexistent\").failure != nil") == .bool(true))
        #expect(try i.eval("rmdir(\"/nonexistent\").failure != nil") == .bool(true))
        #expect(try i.eval("close(-1).failure != nil") == .bool(true))
        #expect(try i.eval("let f = { readFile(\"/nonexistent/x\")? }\nf().failure != nil") == .bool(true))   // ? propagates
        #expect(throws: SwiftalkError.self) { try i.eval("readFile(1)") }
        #expect(throws: SwiftalkError.self) { try i.eval("open()") }
        #expect(throws: SwiftalkError.self) { try i.eval("write(1)") }
        #expect(throws: SwiftalkError.self) { try i.eval("read(0, -1)") }
        #expect(throws: SwiftalkError.self) { try i.eval("open(\"x\", [\"r\"])") }
        #expect(try i.eval("open(\"/nonexistent/x\", [O_WRONLY, O_CREAT]).failure != nil") == .bool(true))
        #expect(throws: SwiftalkError.self) { try i.eval("readFile(\"/nonexistent/x\")!") }                  // a trap
        #expect(try i.eval("import P from \"POSIX\"\nP.getpid() == getpid()") == .bool(true))
    }
}
