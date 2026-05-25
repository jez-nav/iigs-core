# IIGSCore Implementation Plan V3

This is the forward implementation plan after the DiskTest boot milestone. V2 remains the historical record of cloning ADBTest into DiskTest, making disk images ROM-visible, and fixing the GS/OS/Control Panel boot blockers. V3 starts from the assumption that `System.Disk.po` can cold boot to the GS/OS Finder desktop, Carmen `.2mg` can reach its GS/OS-style desktop, and the built-in Control Panel can open cleanly.

## Baseline To Preserve

- `DiskTest` can mount and eject SmartPort units, 5.25 drives, and 3.5 drives.
- `DiskTest` can parse and mount 2IMG/2MG, raw block images, raw 140K and 800K floppy images, NIB, and WOZ images.
- Cold Reset is a power-cycle path that clears RAM while preserving ROM, mounted media, and BRAM.
- BRAM has checksum-backed defaults and persists across DiskTest launches.
- Slot 5 3.5 drive support is good enough for ROM 01, ProDOS 16, GS/OS, and the built-in Control Panel.
- Super Hi-Res rendering, scanline interrupt clearing, `$C035` shadow inhibit, slow-bank separation, `$C046`, `WAI`, and emulation-mode IRQ status stacking are now boot-critical behavior and should not regress.
- Full `xcodebuild test -project IIGSCore.xcodeproj -scheme IIGSCore -configuration Debug -derivedDataPath Build/DerivedData` passed after the DiskTest boot fixes.

## Carried Forward From V2 And Boot Learnings

- Add file-backed write-through or explicit dirty-image export before allowing default writable host images.
- Deepen 3.5 IWM timing/handshake fidelity if more finicky media exposes gaps.
- Expand BRAM/RTC modeling with ROM 03-specific defaults and user-facing controls for startup slot/scan policy.
- Add mouse support so GS/OS desktop applications and mouse-driven demos can be exercised inside DiskTest.
- Add an in-session Classic Desk Accessory trigger using Apple-Control-Escape, separate from the current Option-Reset startup Control Panel path.
- Add partition/container selection for images with multiple mountable partitions.
- Add debugger/CLI disk mounting commands that share the same loader as `DiskTest`.

## Disk And Storage Hardening

- Implement a safe write strategy for mounted disk images:
  - Keep read-only as the default for known host files.
  - Track dirty mounted media in memory.
  - Add explicit export/save-copy flow before writing back to host images.
  - Add tests that prove eject preserves or discards dirty writes according to the selected mode.
- Improve 3.5 IWM fidelity:
  - Audit timing-sensitive handshakes against GS/OS, demos, and games.
  - Keep access tracing available for track/side/action/status reads.
  - Add fixtures for media that exercise disk-switched state, motor spin-up, and side changes.
- Add partition/container selection:
  - Detect multi-partition 2MG/HDV-style media.
  - Present mountable partitions in DiskTest before attaching media.
  - Preserve parsed container metadata in mounted status.
- Share mounting outside DiskTest:
  - Add debugger commands for mount, eject, and mounted-status.
  - Add CLI support that uses the same `IIGSDiskImageLoader`.
  - Keep one set of loader tests for app, debugger, and CLI paths.

## Desktop Interaction And Input

- Add ADB mouse support to DiskTest:
  - Capture host mouse movement, button state, and window focus from the AppKit video surface.
  - Convert host movement into IIgs ADB mouse deltas.
  - Queue mouse events through the emulator runner so `IIGSMachine` mutation stays on the emulation loop.
  - Verify GS/OS Finder pointer movement, menu selection, and double-click/open behavior.
- Add Control Panel and desk accessory workflows:
  - Keep the current Option-Reset startup Control Panel button.
  - Add Apple-Control-Escape for the in-session Classic Desk Accessory path.
  - Add tests for modifier/key event ordering so reset and CDA shortcuts preserve the intended modifier state.

## BRAM, RTC, And ROM Compatibility

- Expand BRAM defaults and settings:
  - Add ROM 03-specific defaults and compatibility tests.
  - Add user-facing controls for startup slot, scan policy, display defaults, and other safe Control Panel settings.
  - Preserve checksum integrity after user edits.
- Harden RTC behavior:
  - Audit clock register reads/writes against ROM startup and Control Panel expectations.
  - Add tests for time/date fields, BRAM transactions, invalid checksum fallback, and persisted snapshots.

## Audio And Ensoniq DOC

- Audit the current audio implementation:
  - Document what `IIGSSoundController` already models for speaker toggles, DOC registers, wave RAM, oscillator state, interrupts, and sample generation.
  - Compare existing behavior against ROM, GS/OS, demos, and simple game workloads.
- Complete the Ensoniq DOC register model:
  - Model the `$C03C-$C03F` sound control/data/pointer interface accurately enough for ROM and GS/OS software.
  - Cover oscillator frequency, volume, wave pointer, wave size, control/mode bits, halted/running state, and interrupt generation.
  - Preserve deterministic scheduler-driven oscillator events for tests and debugger snapshots.
- Add audio output plumbing:
  - Mix DOC output and speaker-click output into a host audio stream.
  - Add mute/volume controls to DiskTest and any reusable host harness layer.
  - Keep audio optional in tests and headless probes.
- Add audio-focused tests and fixtures:
  - Register read/write tests for DOC control, pointer, data, auto-increment, and interrupt registers.
  - Deterministic sample-generation tests for a small waveform and known oscillator settings.
  - Runtime smoke tests with software that is known to use IIgs DOC audio.

## Video And Whole-Machine Regression Coverage

- Preserve headless boot probes as repeatable tooling:
  - Capture final frame, registers, soft-switches, IWM counters, stack window, direct-page window, recent disassembly, and selected memory samples.
  - Keep boot modes for cold boot, `PR#5`, Option-Reset Control Panel, and targeted interrupt suppression.
- Add regression tests or scripts for:
  - `System.Disk.po` cold boot to GS/OS Finder.
  - Carmen `.2mg` `PR#5` boot past ProDOS 16 into the desktop.
  - Option-Reset then `1` into built-in Control Panel.
  - Demos that stress animation, Super Hi-Res, scanline interrupts, and audio once DOC output is active.

## Acceptance Targets

- DiskTest still cold boots `System.Disk.po` to GS/OS Finder.
- DiskTest can move and click the GS/OS mouse pointer.
- DiskTest can trigger the built-in Control Panel at startup and the Classic Desk Accessory menu in-session.
- Disk images can be safely mounted, ejected, and optionally exported when dirty.
- Debugger and CLI can mount/eject disks through the same loader path as DiskTest.
- DOC/speaker audio can be heard in DiskTest and has deterministic register/sample tests.
- Full `IIGSCore` XCTest suite stays green after each workstream lands.
