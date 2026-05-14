#if os(macOS)
import Foundation
import XCTest

final class Phase13CLIRuntimeTests: XCTestCase {
    func testHelpCommandsSucceed() throws {
        let usage = try runCLI(["--help"])
        XCTAssertEqual(usage.status, 0)
        XCTAssertTrue(usage.stdout.contains("IIGSDebuggerCLI"))
        XCTAssertTrue(usage.stdout.contains("--rom path"))

        let help = try runCLI(["--command", "help"])
        XCTAssertEqual(help.status, 0)
        XCTAssertTrue(help.stdout.contains("Commands:"))
        XCTAssertTrue(help.stdout.contains("step [count]"))
    }

    func testLoadBinaryPatchResetVectorStepAndInspectMemory() throws {
        // IIGS-Spec/16-Test-Cases.md calls for externally visible register and memory checks.
        let binary = try writeTempFile(bytes: [
            0xA9, 0x42,       // LDA #$42
            0x8D, 0x00, 0x20  // STA $2000
        ])
        defer { removeTempFile(binary) }

        let result = try runCLI([
            "--load", binary.path, "008000",
            "--command", "set FFFC 00",
            "--command", "set FFFD 80",
            "--command", "reset",
            "--command", "step 2",
            "--command", "regs",
            "--command", "mem 2000 1"
        ])

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("Loaded 5 byte(s) at $008000"))
        XCTAssertTrue(result.stdout.contains("Reset cold PC=$008000"))
        XCTAssertTrue(result.stdout.contains("Stepped 2 instruction(s), last $008002"))
        XCTAssertTrue(result.stdout.contains("PC=$008005 A=$0042"))
        XCTAssertTrue(result.stdout.contains("$002000: $42"))
    }

    func testBreakpointStopsBeforeExecutingAddress() throws {
        let binary = try writeTempFile(bytes: [
            0xEA, // NOP
            0xEA, // NOP
            0xCB  // WAI
        ])
        defer { removeTempFile(binary) }

        let result = try runCLI([
            "--load", binary.path, "008000",
            "--command", "set FFFC 00",
            "--command", "set FFFD 80",
            "--command", "reset",
            "--command", "bp 008002",
            "--command", "run 10",
            "--command", "regs"
        ])

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("Breakpoint set at $008002"))
        XCTAssertTrue(result.stdout.contains("Stopped: breakpoint $008002 instructions=2"))
        XCTAssertTrue(result.stdout.contains("PC=$008002"))
    }

    func testScriptFileRunsDebuggerCommands() throws {
        let binary = try writeTempFile(bytes: [
            0xA9, 0x7E, // LDA #$7E
            0xCB        // WAI
        ])
        let script = try writeTempFile(text: """
        # Phase 13 CLI runtime fixture
        set FFFC 00
        set FFFD 80
        reset
        step
        regs
        """)
        defer {
            removeTempFile(binary)
            removeTempFile(script)
        }

        let result = try runCLI([
            "--load", binary.path, "008000",
            "--script", script.path
        ])

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("Stepped 1 instruction(s), last $008000"))
        XCTAssertTrue(result.stdout.contains("PC=$008002 A=$007E"))
    }

    func testInvalidCommandReturnsNonzeroAndUsefulError() throws {
        let result = try runCLI(["--command", "not-a-command"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("Unknown debugger command: not-a-command"))
    }

    func testROM01RuntimeSmokeWhenLocalROMIsPresent() throws {
        let romURL = workspaceRoot()
            .appendingPathComponent("LocalAssets")
            .appendingPathComponent("ROMs")
            .appendingPathComponent("Apple_IIGS_ROM01.bin")

        guard FileManager.default.fileExists(atPath: romURL.path) else {
            throw XCTSkip("Local legal ROM01 fixture is not present")
        }

        // IIGS-Spec/14-Boot-Sequence.md starts cold boot at the ROM reset vector.
        let result = try runCLI(["--rom", romURL.path, "--command", "regs"])

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("Reset cold PC=$00FA62"))
        XCTAssertTrue(result.stdout.contains("PC=$00FA62"))
        XCTAssertTrue(result.stdout.contains("E=1"))
    }

    private struct CLIResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func runCLI(_ arguments: [String]) throws -> CLIResult {
        let process = Process()
        process.executableURL = cliURL()
        process.arguments = arguments
        process.currentDirectoryURL = workspaceRoot()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CLIResult(status: process.terminationStatus, stdout: stdoutText, stderr: stderrText)
    }

    private func cliURL() -> URL {
        Bundle(for: Self.self)
            .bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("IIGSDebuggerCLI")
    }

    private func workspaceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func writeTempFile(bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IIGSCore-\(UUID().uuidString)")
            .appendingPathExtension("bin")
        try Data(bytes).write(to: url)
        return url
    }

    private func writeTempFile(text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IIGSCore-\(UUID().uuidString)")
            .appendingPathExtension("debug")
        try Data(text.utf8).write(to: url)
        return url
    }

    private func removeTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
