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

    func testPhase17ScriptAssertionsAndSnapshotCommands() throws {
        let binary = try writeTempFile(bytes: [
            0xA9, 0x42,       // LDA #$42
            0x8D, 0x00, 0x20, // STA $2000
            0xCB              // WAI
        ])
        let script = try writeTempFile(text: """
        set FFFC 00
        set FFFD 80
        reset
        step 2
        assert pc 008005
        assert reg A 42
        assert mem 2000 42
        assert flag Z 0
        assert status ready 1
        assert cycles >= 1
        snapshot
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
        XCTAssertTrue(result.stdout.contains("ASSERT OK pc $008005"))
        XCTAssertTrue(result.stdout.contains("ASSERT OK reg A $0042"))
        XCTAssertTrue(result.stdout.contains("ASSERT OK mem $002000 $42"))
        XCTAssertTrue(result.stdout.contains("flags=N0"))
        XCTAssertTrue(result.stdout.contains("status=RDY1"))
        XCTAssertTrue(result.stdout.contains("timing=cycles:"))
    }

    func testPhase17EventsAndRunPCCommands() throws {
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
            "--command", "schedule paddle 2 1",
            "--command", "runpc 008002 10",
            "--command", "events",
            "--command", "assert pc 008002"
        ])

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("Scheduled paddleTimeout after 2 cycle(s) payload=000001"))
        XCTAssertTrue(result.stdout.contains("Stopped: breakpoint $008002"))
        XCTAssertTrue(result.stdout.contains("serviced"))
        XCTAssertTrue(result.stdout.contains("paddleTimeout"))
        XCTAssertTrue(result.stdout.contains("ASSERT OK pc $008002"))
    }

    func testPhase17AssertionFailureReturnsNonzero() throws {
        let result = try runCLI([
            "--command", "assert pc 008000"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("Assertion failed: PC expected $008000 got $000000"))
    }

    func testPhase17MountRawBlockImageCommand() throws {
        let image = try writeTempFile(bytes: Array(repeating: 0xE5, count: 512))
        defer { removeTempFile(image) }

        let result = try runCLI([
            "--command", "mountraw \(image.path) 2 1"
        ])

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("Mounted raw block image unit=2 blocks=1 readOnly=1"))
    }

    func testPhase18RuntimeScriptCanAssertScanlineIRQAndClearIt() throws {
        let binary = try writeTempFile(bytes: Array(repeating: 0xEA, count: 80))
        let script = try writeTempFile(text: """
        set FFFC 00
        set FFFD 80
        reset
        set C023 04
        cycles 65
        assert status irq 1
        assert mem C023 C4
        set C032 40
        assert mem C023 04
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
        XCTAssertTrue(result.stdout.contains("ASSERT OK status IRQ 1"))
        XCTAssertTrue(result.stdout.contains("ASSERT OK mem $00C023 $C4"))
        XCTAssertTrue(result.stdout.contains("ASSERT OK mem $00C023 $04"))
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
