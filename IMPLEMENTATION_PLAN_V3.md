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
- Add mouse support so GS/OS desktop applications and mouse-driven demos can be exercised inside DiskTest. This is the next active V3 workstream.
- Add an in-session Classic Desk Accessory trigger using Apple-Control-Escape, separate from the current Option-Reset startup Control Panel path.
- Add partition/container selection for images with multiple mountable partitions.
- Add debugger/CLI disk mounting commands that share the same loader as `DiskTest`.

## Active V3 Sequencing

1. DiskTest mouse support:
   - Current status: implemented in DiskTest pending final manual UX confirmation.
   - Reuse the existing macOS debugger display pattern for AppKit mouse tracking.
   - Keep SwiftUI as the owner of app state and use `NSViewRepresentable` only for display focus, keyboard, and mouse event capture.
   - Queue host mouse movement/button events through `DiskTestEmulatorRunner`, so the emulation loop remains the only owner of `IIGSMachine` mutation.
   - Split or clamp large host deltas before forwarding them to the existing ADB mouse path.
   - Hide the host cursor only over the active render area, keep the blue border as normal host UI, and stop guest motion outside the active area.
   - Sync the guest pointer to the host pointer on active-area entry before resuming normal relative deltas.
   - Verify GS/OS Finder pointer movement, click, and double-click behavior after booting `System.Disk.po`.
2. Core audio hardening:
   - Keep deterministic speaker/DOC state and sample rendering inside `IIGSCore.framework`.
   - Keep CoreAudio and any host playback engine out of `IIGSCore.framework`.
   - Refactor audio rendering around emulated cycle ranges so `$C030` toggles, DOC register changes, oscillator events, and IRQ state are reproducible in tests.
   - Harden DOC oscillator timing, wave size/resolution, one-shot/free-run/sync/swap behavior, `$E0/$E1` IRQ semantics, and mixed speaker/DOC sample output.
3. DiskTest audio playback:
   - Current status: implemented in DiskTest pending manual audio-quality confirmation.
   - Add macOS-only CoreAudio/AVAudio plumbing in the DiskTest app/client layer.
   - Feed host audio from framework-owned deterministic sample buffers.
   - Add DiskTest mute/volume controls while preserving headless and XCTest paths.

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
  - Current implementation captures active-render-area motion, hides the host cursor over that active area only, releases/clears mouse state on exit or focus loss, and syncs the guest pointer to the host entry position.
  - Capture host mouse movement, button state, and window focus from the AppKit video surface.
  - Convert host movement into IIgs ADB mouse deltas.
  - Queue mouse events through the emulator runner so `IIGSMachine` mutation stays on the emulation loop.
  - Verify GS/OS Finder pointer movement, menu selection, and double-click/open behavior.
- Add Control Panel and desk accessory workflows:
  - Keep the current Option-Reset startup Control Panel button.
  - Current Classic Desk Accessory pass:
    - Add a DiskTest Desk Accessory button that sends a paced Open-Apple-Control-Escape chord in-session so the guest can poll latched modifiers before release.
    - Raise the IIgs ADB Desk Manager interrupt byte when Escape is pressed while Control and Open-Apple are latched, keeping it separate from normal ADB response payloads so it can combine with a pending response header.
    - Route host Control-Command-Escape to the same guest Escape chord when the display surface has keyboard focus.
    - Add a DiskTest app menu shortcut for the same action so command-key routing still works outside the raw display responder path.
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
- Current Core audio hardening pass:
  - Keep `IIGSCore` limited to deterministic raw stereo `Int16` sample buffers, with no CoreAudio framework dependency.
  - Render audio by emulated cycle range so `$C030` speaker toggles and DOC register changes are preserved before state mutation.
  - Expose memory-bus audio draining for app/client playback layers such as DiskTest.
  - Use the local ROM 01 startup beep as a fixture for speaker-toggle tone measurement; CoreAudio playback remains a DiskTest/client-layer follow-up.
- Current DiskTest audio playback pass:
  - Keep AVAudioEngine playback in the DiskTest app target, outside `IIGSCore.framework`.
  - Feed the host audio queue from `IIGSAudioBuffer` values drained once per emulated video frame.
  - Clear queued host samples on reset/power-cycle so old audio does not survive machine resets.
  - Add DiskTest mute and volume controls to the side panel.
  - Ensure default battery RAM starts with audible user volume so ROM 01 boot beep toggles produce nonzero raw samples.

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
