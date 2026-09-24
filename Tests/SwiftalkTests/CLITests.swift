import Testing
@testable import Swiftalk
import Foundation

// Round 187: the CLI's options — `--no-prelude` starts bare, `--help`.
// These run the built executable beside the test's libraries.
struct CLITests {
    private func run(_ options: String, input: String) throws -> String {
        let dir = try #require(buildDirectory())
        let exe = dir + "/swiftalk"
        guard FileManager.default.isExecutableFile(atPath: exe) else { throw Swiftalk.Error.type("no CLI at \(exe) — swift build") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = options.isEmpty ? [] : options.split(separator: " ").map(String.init)
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stdout
        try process.run()
        stdin.fileHandleForWriting.write(Data((input + "\n").utf8))
        try stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test("--no-prelude: no print, no /re/, no fetch — eval remains, and import from \"IO\" brings print back")
    func noPrelude() throws {
        #expect(try run("", input: "print(1)") == "1\n")
        let bare = try run("--no-prelude", input: "print(1)")
        #expect(bare.contains("undefined variable 'print'"))
        #expect(try run("--no-prelude", input: "eval(\"1 + 1\")!") == "2\n")
        #expect(try run("--no-prelude", input: "/a/").contains("Regex module"))
        #expect(try run("--no-prelude", input: "import from \"IO\"\nprint(2)") == "2\n")
        #expect(try run("--no-prelude", input: "import (Regex) from \"Regex\"\n/ab/.pattern") == "\"ab\"\n")
    }

    @Test("--help prints the usage; an unknown option is refused")
    func help() throws {
        #expect(try run("--help", input: "").hasPrefix("usage: swiftalk"))
        #expect(try run("--bogus", input: "").contains("unknown option"))
    }
}
