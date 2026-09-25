@testable import Swiftalk

// The public API is namespaced (Swiftalk.eval, Swiftalk.Interpreter, ...);
// tests keep the terse spellings via these shims. Value, Interpreter, and
// SwiftalkError come through @testable as the module's internal
// typealiases.
func eval(_ source: String) throws -> Value {
    try interpreter().eval(source)
}

/// A fresh Interpreter with the CLI's prelude (rounds 185–186): `print`,
/// `debugPrint`, `fetch`, `Response`, and `Regex` bound as the CLI binds
/// them — Regex from the module library beside the test.
func interpreter(relaxed: Bool = false) throws -> Interpreter {
    let i = Interpreter(relaxed: relaxed)
    i.modulePath = [buildDirectory()].compactMap { $0 }
    try i.preimport(["IO", "Net", "Regex", "Sequence", "Task"])
    return i
}

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The build directory — where libSwiftalk lives (dladdr on its metadata
/// on Darwin, /proc/self/maps on Linux), which is where the module
/// libraries (libEnv, libRegex) are built too.
func buildDirectory() -> String? {
    guard let library = libraryPath() else { return nil }
    var dir = ModuleSystem.directory(of: library)
    let file = Swiftalk.Module.fileName(for: "Swiftalk")
    for _ in 0..<4 {
        if access(dir + "/" + file, R_OK) == 0 { return dir }
        dir = ModuleSystem.directory(of: dir)
    }
    return nil
}

private func libraryPath() -> String? {
    #if canImport(Darwin)
    var info = Dl_info()
    let anchor = unsafeBitCast(Swiftalk.Interpreter.self, to: UnsafeRawPointer.self)
    guard dladdr(anchor, &info) != 0, let name = info.dli_fname else { return nil }
    return String(cString: name)
    #else
    guard let maps = try? ModuleSystem.readFile("/proc/self/maps") else { return nil }
    for line in maps.split(separator: "\n") {
        guard line.hasSuffix("/libSwiftalk.so"), let slash = line.firstIndex(of: "/") else { continue }
        return String(line[slash...])
    }
    return nil
    #endif
}

func needsMoreInput(_ source: String) -> Bool {
    Swiftalk.needsMoreInput(source)
}
