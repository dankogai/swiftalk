import Swiftalk
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// `POSIX` — the process environment and file I/O (round 188; the `Env`
// module of rounds 182–183 grown up). Every function keeps its C name;
// what can fail answers a `Result` — `.success(value)` or
// `.failure("open(x): No such file or directory")` — so `open(path,
// O_RDONLY)!` traps, `?` propagates, `??` defaults, as `fetch`'s does.
// Not in the CLI's prelude: `import from "POSIX"` (libPOSIX.dylib sits
// beside the CLI), or `import POSIX from "POSIX"` for `POSIX.open`.
//
//     import from "POSIX"
//     let fd = open("notes.txt", [O_WRONLY, O_CREAT, O_TRUNC])!   // flags: an Int or an Array of them
//     write(fd, "hello\n")
//     close(fd)
//     readFile("notes.txt")!.String(.utf8)     // "hello\n"
//     stat("notes.txt")!["size"]               // 6
//     readdir(".")!.contains("notes.txt")      // true

private func failure(_ call: String) -> Swiftalk.Value {
    .failure("\(call): \(String(cString: strerror(errno)))")
}

private func string(_ v: Swiftalk.Value, _ what: String) throws -> String {
    guard case .string(let s) = v else { throw Swiftalk.Error.type("\(what) takes a String, not \(v.typeName)") }
    return s
}

private func int(_ v: Swiftalk.Value, _ what: String) throws -> Int {
    guard case .int(let i) = v else { throw Swiftalk.Error.type("\(what) takes an Int, not \(v.typeName)") }
    return Int(i)
}

/// Flags: an Int, or an Array of Ints ORed together — `[O_WRONLY,
/// O_CREAT]` — since `|` is swiftalk's Set operator.
private func flags(_ v: Swiftalk.Value, _ what: String) throws -> Int32 {
    switch v {
    case .int(let i): return Int32(i)
    case .array(let a, _):
        var out: Int32 = 0
        for e in a {
            guard case .int(let i) = e else { throw Swiftalk.Error.type("\(what): flags are Ints, not \(e.typeName)") }
            out |= Int32(i)
        }
        return out
    default: throw Swiftalk.Error.type("\(what) takes an Int or an Array of Ints for the flags, not \(v.typeName)")
    }
}

private func bytes(_ v: Swiftalk.Value, _ what: String) throws -> [UInt8] {
    switch v {
    case .data(let d):   return d
    case .string(let s): return Array(s.utf8)
    default: throw Swiftalk.Error.type("\(what) takes a Data or a String, not \(v.typeName)")
    }
}

/// A C char array (a tuple in Swift) as a String.
private func cString<T>(_ field: inout T) -> String {
    withUnsafeBytes(of: &field) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
}

private func arity(_ args: [Swiftalk.Value], _ counts: ClosedRange<Int>, _ what: String) throws {
    guard counts.contains(args.count) else {
        throw Swiftalk.Error.type("\(what) takes \(counts.lowerBound == counts.upperBound ? "\(counts.lowerBound)" : "\(counts.lowerBound) to \(counts.upperBound)") arguments, not \(args.count)")
    }
}

func build() -> Swiftalk.Module {
    let m = Swiftalk.Module(name: "POSIX")

    // ---- the environment (rounds 182–183, as Env) ----
    m.function("getenv") { args in
        try arity(args, 1...1, "getenv(name)")
        guard let value = getenv(try string(args[0], "getenv(name)")) else { return .nil }
        return .string(String(cString: value))
    }
    m.function("setenv") { args in
        try arity(args, 2...2, "setenv(name, value)")
        let name = try string(args[0], "setenv(name, value)"), value = try string(args[1], "setenv(name, value)")
        return setenv(name, value, 1) == 0 ? .success(.nil) : failure("setenv(\(name))")
    }
    m.function("unsetenv") { args in
        try arity(args, 1...1, "unsetenv(name)")
        let name = try string(args[0], "unsetenv(name)")
        return unsetenv(name) == 0 ? .success(.nil) : failure("unsetenv(\(name))")
    }
    m.function("environ") { args in
        try arity(args, 0...0, "environ()")
        var table: [Swiftalk.Value: Swiftalk.Value] = [:]
        var cursor = environ
        while let entry = cursor.pointee {
            let line = String(cString: entry)
            if let eq = line.firstIndex(of: "=") {
                table[.string(String(line[..<eq]))] = .string(String(line[line.index(after: eq)...]))
            }
            cursor += 1
        }
        return .dictionary(table)
    }

    // ---- the process ----
    m.function("getpid") { args in
        try arity(args, 0...0, "getpid()")
        return .int(Int64(getpid()))
    }
    m.function("getcwd") { args in
        try arity(args, 0...0, "getcwd()")
        var buffer = [CChar](repeating: 0, count: 4096)
        guard getcwd(&buffer, buffer.count) != nil else { return failure("getcwd()") }
        return .success(.string(String(cString: buffer)))
    }
    m.function("chdir") { args in
        try arity(args, 1...1, "chdir(path)")
        let path = try string(args[0], "chdir(path)")
        return chdir(path) == 0 ? .success(.nil) : failure("chdir(\(path))")
    }
    m.function("uname") { args in
        try arity(args, 0...0, "uname()")
        var u = utsname()
        guard uname(&u) == 0 else { return failure("uname()") }
        return .success(.dictionary([
            .string("sysname"): .string(cString(&u.sysname)), .string("nodename"): .string(cString(&u.nodename)),
            .string("release"): .string(cString(&u.release)), .string("version"): .string(cString(&u.version)),
            .string("machine"): .string(cString(&u.machine)),
        ]))
    }
    m.function("exit") { args in
        try arity(args, 0...1, "exit(code)")
        exit(args.isEmpty ? 0 : Int32(try int(args[0], "exit(code)")))
    }

    // ---- descriptors ----
    m.function("open") { args in
        try arity(args, 1...3, "open(path, flags, mode)")
        let path = try string(args[0], "open(path)")
        let flags = args.count > 1 ? try flags(args[1], "open(path, flags)") : O_RDONLY
        let mode = args.count > 2 ? mode_t(try int(args[2], "open(path, flags, mode)")) : 0o644
        let fd = open(path, flags, mode)
        return fd >= 0 ? .success(.int(Int64(fd))) : failure("open(\(path))")
    }
    m.function("close") { args in
        try arity(args, 1...1, "close(fd)")
        let fd = try int(args[0], "close(fd)")
        return close(Int32(fd)) == 0 ? .success(.nil) : failure("close(\(fd))")
    }
    m.function("read") { args in
        try arity(args, 1...2, "read(fd, count)")
        let fd = try int(args[0], "read(fd)")
        let count = args.count > 1 ? try int(args[1], "read(fd, count)") : 65536
        guard count >= 0 else { throw Swiftalk.Error.type("read(fd, count): a non-negative count") }
        var buffer = [UInt8](repeating: 0, count: count)
        let n = read(Int32(fd), &buffer, count)
        guard n >= 0 else { return failure("read(\(fd))") }
        return .success(.data(Array(buffer[0..<n])))
    }
    m.function("write") { args in
        try arity(args, 2...2, "write(fd, data)")
        let fd = try int(args[0], "write(fd, data)")
        let data = try bytes(args[1], "write(fd, data)")
        let n = data.withUnsafeBufferPointer { write(Int32(fd), $0.baseAddress, $0.count) }
        return n >= 0 ? .success(.int(Int64(n))) : failure("write(\(fd))")
    }
    m.function("lseek") { args in
        try arity(args, 2...3, "lseek(fd, offset, whence)")
        let fd = try int(args[0], "lseek(fd, offset)"), offset = try int(args[1], "lseek(fd, offset)")
        let whence = args.count > 2 ? Int32(try int(args[2], "lseek(fd, offset, whence)")) : SEEK_SET
        let position = lseek(Int32(fd), off_t(offset), whence)
        return position >= 0 ? .success(.int(Int64(position))) : failure("lseek(\(fd))")
    }

    // ---- files and directories ----
    m.function("readFile") { args in
        try arity(args, 1...1, "readFile(path)")
        let path = try string(args[0], "readFile(path)")
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return failure("readFile(\(path))") }
        defer { close(fd) }
        var data: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n < 0 { return failure("readFile(\(path))") }
            if n == 0 { break }
            data.append(contentsOf: chunk[0..<n])
        }
        return .success(.data(data))
    }
    m.function("writeFile") { args in
        try arity(args, 2...2, "writeFile(path, contents)")
        let path = try string(args[0], "writeFile(path, contents)")
        let data = try bytes(args[1], "writeFile(path, contents)")
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return failure("writeFile(\(path))") }
        defer { close(fd) }
        var written = 0
        while written < data.count {
            let n = data[written...].withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
            if n < 0 { return failure("writeFile(\(path))") }
            written += n
        }
        return .success(.int(Int64(written)))
    }
    m.function("stat") { args in
        try arity(args, 1...1, "stat(path)")
        let path = try string(args[0], "stat(path)")
        var st = stat()
        guard stat(path, &st) == 0 else { return failure("stat(\(path))") }
        #if canImport(Darwin)
        let mtime = st.st_mtimespec, atime = st.st_atimespec, ctime = st.st_ctimespec
        #else
        let mtime = st.st_mtim, atime = st.st_atim, ctime = st.st_ctim
        #endif
        func date(_ t: timespec) -> Swiftalk.Value { .date(Double(t.tv_sec) + Double(t.tv_nsec) / 1e9) }
        let kind = st.st_mode & S_IFMT
        return .success(.dictionary([
            .string("size"): .int(Int64(st.st_size)), .string("mode"): .int(Int64(st.st_mode & 0o7777)),
            .string("uid"): .int(Int64(st.st_uid)), .string("gid"): .int(Int64(st.st_gid)),
            .string("nlink"): .int(Int64(st.st_nlink)),
            .string("mtime"): date(mtime), .string("atime"): date(atime), .string("ctime"): date(ctime),
            .string("isFile"): .bool(kind == S_IFREG), .string("isDirectory"): .bool(kind == S_IFDIR),
            .string("isSymlink"): .bool(kind == S_IFLNK),
        ]))
    }
    m.function("readdir") { args in
        try arity(args, 1...1, "readdir(path)")
        let path = try string(args[0], "readdir(path)")
        guard let dir = opendir(path) else { return failure("readdir(\(path))") }
        defer { closedir(dir) }
        var names: [Swiftalk.Value] = []
        while let entry = readdir(dir) {
            let name = cString(&entry.pointee.d_name)
            if name != "." && name != ".." { names.append(.string(name)) }
        }
        return .success(.array(names, lock: TypeAnnotation("Array", parameters: [TypeAnnotation("String")])))
    }
    m.function("mkdir") { args in
        try arity(args, 1...2, "mkdir(path, mode)")
        let path = try string(args[0], "mkdir(path)")
        let mode = args.count > 1 ? mode_t(try int(args[1], "mkdir(path, mode)")) : 0o755
        return mkdir(path, mode) == 0 ? .success(.nil) : failure("mkdir(\(path))")
    }
    m.function("rmdir") { args in
        try arity(args, 1...1, "rmdir(path)")
        let path = try string(args[0], "rmdir(path)")
        return rmdir(path) == 0 ? .success(.nil) : failure("rmdir(\(path))")
    }
    m.function("unlink") { args in
        try arity(args, 1...1, "unlink(path)")
        let path = try string(args[0], "unlink(path)")
        return unlink(path) == 0 ? .success(.nil) : failure("unlink(\(path))")
    }
    m.function("rename") { args in
        try arity(args, 2...2, "rename(from, to)")
        let from = try string(args[0], "rename(from, to)"), to = try string(args[1], "rename(from, to)")
        return rename(from, to) == 0 ? .success(.nil) : failure("rename(\(from))")
    }

    // ---- constants ----
    for (name, value) in [
        ("O_RDONLY", O_RDONLY), ("O_WRONLY", O_WRONLY), ("O_RDWR", O_RDWR), ("O_CREAT", O_CREAT),
        ("O_TRUNC", O_TRUNC), ("O_APPEND", O_APPEND), ("O_EXCL", O_EXCL),
        ("SEEK_SET", SEEK_SET), ("SEEK_CUR", SEEK_CUR), ("SEEK_END", SEEK_END),
        ("STDIN_FILENO", STDIN_FILENO), ("STDOUT_FILENO", STDOUT_FILENO), ("STDERR_FILENO", STDERR_FILENO),
    ] {
        m.export(name, .int(Int64(value)))
    }
    return m
}

/// The entry point the interpreter calls after dlopen.
@_cdecl("swiftalk_module")
public func swiftalkModule() -> UnsafeMutableRawPointer {
    build().entryPoint()
}
