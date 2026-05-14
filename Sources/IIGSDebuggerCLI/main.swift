import Darwin
import Foundation
import IIGSCore

final class IIGSDebuggerCLI {
    private let parser = IIGSDebuggerCommandParser()
    private let session = IIGSDebuggerSession()
    private var shouldQuit = false

    func run(arguments: [String]) -> Int {
        do {
            var commands: [String] = []
            var scriptPath: String?
            var index = 0

            while index < arguments.count {
                let argument = arguments[index]
                switch argument {
                case "--help", "-h":
                    print(Self.usage)
                    return 0
                case "--rom":
                    let path = try requiredValue(after: argument, in: arguments, index: &index)
                    try loadROM(path: path)
                    try printCommand(.reset(.cold))
                case "--load":
                    let path = try requiredValue(after: argument, in: arguments, index: &index)
                    let addressText = try requiredValue(after: argument, in: arguments, index: &index)
                    try loadBinary(path: path, addressText: addressText)
                case "--script":
                    scriptPath = try requiredValue(after: argument, in: arguments, index: &index)
                case "--command", "-c":
                    commands.append(try requiredValue(after: argument, in: arguments, index: &index))
                case "--run":
                    commands.append("run \(try requiredValue(after: argument, in: arguments, index: &index))")
                default:
                    throw IIGSDebuggerError.invalidArgument(argument)
                }
                index += 1
            }

            if let scriptPath {
                commands.append(contentsOf: try readScript(path: scriptPath))
            }

            if !commands.isEmpty {
                for command in commands where !shouldQuit {
                    try execute(line: command)
                }
                return 0
            }

            repl()
            return 0
        } catch {
            printError(error)
            return 1
        }
    }

    private func repl() {
        print("IIGSDebuggerCLI. Type 'help' for commands, 'quit' to exit.")
        while !shouldQuit {
            print("iigs> ", terminator: "")
            guard let line = readLine() else {
                break
            }
            do {
                try execute(line: line)
            } catch {
                printError(error)
            }
        }
    }

    private func execute(line: String) throws {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        switch parts.first?.lowercased() {
        case "loadrom", "rom":
            guard parts.count >= 2 else {
                throw IIGSDebuggerError.missingArgument("ROM path")
            }
            try loadROM(path: parts[1])
            print("Loaded ROM \(parts[1])")
            return
        case "loadbin", "load":
            guard parts.count >= 3 else {
                throw IIGSDebuggerError.missingArgument("binary path and address")
            }
            try loadBinary(path: parts[1], addressText: parts[2])
            return
        case "mountraw":
            guard parts.count >= 2 else {
                throw IIGSDebuggerError.missingArgument("raw block image path")
            }
            try mountRawBlockDevice(path: parts[1], unitText: parts.dropFirst(2).first, readOnlyText: parts.dropFirst(3).first)
            return
        case "mount2img":
            guard parts.count >= 2 else {
                throw IIGSDebuggerError.missingArgument("2IMG path")
            }
            try mount2IMGBlockDevice(path: parts[1], unitText: parts.dropFirst(2).first)
            return
        default:
            break
        }

        guard let command = try parser.parse(trimmed) else {
            return
        }
        try printCommand(command)
    }

    private func printCommand(_ command: IIGSDebuggerCommand) throws {
        if command == .quit {
            shouldQuit = true
            return
        }
        print(try session.execute(command))
    }

    private func loadROM(path: String) throws {
        try session.loadROM(bytes: Array(readFile(path: path)))
    }

    private func loadBinary(path: String, addressText: String) throws {
        let address = try parser.parseAddress(addressText)
        let bytes = Array(try readFile(path: path))
        session.loadBinary(bytes, at: address)
        print("Loaded \(bytes.count) byte(s) at \(formatAddress(address))")
    }

    private func mountRawBlockDevice(path: String, unitText: String?, readOnlyText: String?) throws {
        let unit = try parseUnit(unitText)
        let readOnly = try readOnlyText.map(parser.parseBool) ?? false
        let device = try IIGSBlockDevice.raw(
            bytes: Array(readFile(path: path)),
            name: URL(fileURLWithPath: path).lastPathComponent,
            isWriteProtected: readOnly
        )
        session.machine.mountSmartPortDevice(device, unit: unit)
        print("Mounted raw block image unit=\(unit) blocks=\(device.blockCount) readOnly=\(readOnly ? 1 : 0)")
    }

    private func mount2IMGBlockDevice(path: String, unitText: String?) throws {
        let unit = try parseUnit(unitText)
        let device = try IIGSBlockDevice.twoIMG(
            bytes: Array(readFile(path: path)),
            name: URL(fileURLWithPath: path).lastPathComponent
        )
        session.machine.mountSmartPortDevice(device, unit: unit)
        print("Mounted 2IMG block image unit=\(unit) blocks=\(device.blockCount) readOnly=\(device.isWriteProtected ? 1 : 0)")
    }

    private func parseUnit(_ text: String?) throws -> UInt8 {
        guard let text else {
            return 1
        }
        let value = try parser.parseByte(text)
        guard (1...127).contains(value) else {
            throw IIGSDebuggerError.invalidArgument(text)
        }
        return value
    }

    private func readFile(path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    private func readScript(path: String) throws -> [String] {
        let data = try readFile(path: path)
        guard let text = String(data: data, encoding: .utf8) else {
            throw IIGSDebuggerError.invalidArgument("script is not UTF-8")
        }
        return text.components(separatedBy: .newlines)
    }

    private func requiredValue(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw IIGSDebuggerError.missingArgument(option)
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private func printError(_ error: Error) {
        let text: String
        if let debuggerError = error as? IIGSDebuggerError {
            text = debuggerError.description
        } else if let romError = error as? IIGSROMError {
            text = romError.description
        } else if let cpuError = error as? CPUError {
            text = cpuError.description
        } else {
            text = String(describing: error)
        }
        FileHandle.standardError.write(Data("error: \(text)\n".utf8))
    }

    private func formatAddress(_ address: UInt32) -> String {
        let text = String(masked24(address), radix: 16, uppercase: true)
        return "$" + String(repeating: "0", count: max(0, 6 - text.count)) + text
    }

    static let usage = """
    IIGSDebuggerCLI

    Usage:
      IIGSDebuggerCLI [--rom path] [--load path address] [--command command] [--script path] [--run count]

    Examples:
      IIGSDebuggerCLI --rom LocalAssets/ROMs/Apple_IIGS_ROM01.bin --command "regs"
      IIGSDebuggerCLI --load sample.bin 008000 --command "set FFFC 00" --command "set FFFD 80" --command "reset" --command "step"

    Interactive commands:
      help, regs, step [count], run [limit], cycles <count>, bp <addr>, bc <addr>, bl,
      mem <addr> [count], set <addr> <byte>, reset [cold|warm], loadrom <path>,
      loadbin <path> <addr>, mountraw <path> [unit] [readOnly], mount2img <path> [unit], quit
    """
}

let exitCode = IIGSDebuggerCLI().run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(Int32(exitCode))
