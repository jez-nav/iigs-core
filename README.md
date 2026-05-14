# IIGSCore

IIGSCore is a pure Swift Apple IIgs emulator core. It is intended to model the
machine-level parts of the Apple IIgs without owning any host UI, audio output
device, rendering surface, or app shell. The framework can therefore be embedded
in a debugger, desktop emulator, iOS app, test harness, or other front end.

The project currently includes:

- `IIGSCore.framework`, the reusable emulator core.
- `IIGSDebuggerCLI`, a small macOS command-line debugger and smoke-test tool.
- `IIGSCoreTests`, XCTest coverage for the CPU, memory, soft switches, video,
  input, storage, audio, machine runtime, and debugger behavior.
- `IIGS-Spec/`, local implementation notes and subsystem specifications.
- `references/`, Apple IIgs and Apple II reference material used while building
  the core.

The current implementation status is tracked in `IMPLEMENTATION_PLAN.md`.
At a high level, the core has MVP or partial coverage for the 65C816 CPU, banked
memory and ROM mapping, soft switches, video rendering buffers, ADB input,
SmartPort and IWM storage paths, Ensoniq/speaker audio state, machine stepping,
and debugger commands. Timing and full hardware-compatibility behavior are still
areas for future work.

## Requirements

- macOS with Xcode installed.
- Swift 6 support.
- The project is Xcode-based; there is currently no `Package.swift`.

The framework target is configured for macOS, iOS, and iOS Simulator. The
debugger CLI target is macOS-only.

## Repository Layout

```text
Sources/IIGSCore/          Core framework source
Sources/IIGSDebuggerCLI/   Standalone debugger CLI
Tests/IIGSCoreTests/       XCTest suite
IIGS-Spec/                 Local emulator/spec notes
references/                Reference documents
LocalAssets/               Optional local ROMs and private fixtures, ignored by git
```

## Build

Open the project in Xcode:

```sh
open IIGSCore.xcodeproj
```

Build the framework from the command line:

```sh
xcodebuild \
  -project IIGSCore.xcodeproj \
  -scheme IIGSCore \
  -destination 'platform=macOS' \
  -derivedDataPath Build/DerivedData \
  build
```

Build the debugger CLI:

```sh
xcodebuild \
  -project IIGSCore.xcodeproj \
  -target IIGSDebuggerCLI \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath Build/DerivedData \
  build
```

Build the framework for a generic iOS device:

```sh
xcodebuild \
  -project IIGSCore.xcodeproj \
  -scheme IIGSCore \
  -destination 'generic/platform=iOS' \
  -derivedDataPath Build/DerivedData \
  build
```

## Test

Run the macOS test suite:

```sh
xcodebuild test \
  -project IIGSCore.xcodeproj \
  -scheme IIGSCore \
  -destination 'platform=macOS' \
  -derivedDataPath Build/DerivedData
```

Some tests look for optional local ROM fixtures under `LocalAssets/ROMs/`.
Those assets are intentionally ignored by git. If a legal Apple IIgs ROM image is
not present, ROM-dependent smoke tests should skip rather than fail.

## Debugger CLI

After building the CLI with the `Build/DerivedData` path above, run:

```sh
Build/DerivedData/Build/Products/Debug/IIGSDebuggerCLI --help
```

Example command sequence with a local ROM:

```sh
Build/DerivedData/Build/Products/Debug/IIGSDebuggerCLI \
  --rom LocalAssets/ROMs/Apple_IIGS_ROM01.bin \
  --command "regs"
```

Example command sequence with a raw binary loaded at `$008000`:

```sh
Build/DerivedData/Build/Products/Debug/IIGSDebuggerCLI \
  --load sample.bin 008000 \
  --command "set FFFC 00" \
  --command "set FFFD 80" \
  --command "reset" \
  --command "step"
```

Interactive debugger commands include:

- `help`
- `regs`
- `step [count]`
- `run [limit]`
- `cycles <count>`
- `bp <addr>`, `bc <addr>`, `bl`
- `mem <addr> [count]`
- `set <addr> <byte>`
- `reset [cold|warm]`
- `loadrom <path>`
- `loadbin <path> <addr>`
- `quit`

## Using the Framework

`IIGSMachine` is the main integration point. It owns the CPU, memory bus,
SmartPort controller, and machine-level stepping/running helpers.

```swift
import IIGSCore

let machine = IIGSMachine()
machine.memory.load([0xEA, 0xCB], at: 0x008000) // NOP; WAI
machine.memory.write8(0x00, at: 0x00FFFC)
machine.memory.write8(0x80, at: 0x00FFFD)
machine.reset(.cold)

let result = try machine.runUntilStop(instructionLimit: 10)
print(result.stopReason)
```

The framework deliberately avoids AppKit, UIKit, SwiftUI, CoreAudio, and Metal.
Presentation, audio playback, input mapping, and host-window behavior should live
in whichever app embeds the core.

## Current Status and Limitations

IIGSCore is not yet a complete Apple IIgs emulator. The phase-13 audit marks many
subsystems as MVP or partial. Known future work includes fuller opcode and bus
timing fidelity, a central event scheduler, deeper ROM boot coverage, richer
disk-format behavior, more complete Ensoniq DOC emulation, and a separate macOS
debugger application.

See `IMPLEMENTATION_PLAN.md` for the detailed phase plan and subsystem audit.
