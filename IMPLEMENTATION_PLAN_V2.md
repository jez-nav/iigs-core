# IIGSCore Implementation Plan V2

This plan tracks the next feature-completion pass using small, runnable shell Swift apps as focused integration harnesses.

## ADBTest Harness

- Clone the successful `VideoTest` harness into a new macOS app target named `ADBTest`.
- Keep the same ROM loading, emulator frame loop, and SwiftUI/AppKit video surface approach that made video integration easy to verify.
- Add a focused keyboard-input bridge on the macOS presentation side.
- Translate macOS `NSEvent` keyboard input into Apple IIgs-compatible ADB key codes and Apple II compatibility ASCII/strobe input.
- Treat Open-Apple and Closed-Apple as first-class IIgs modifier states:
  - macOS Command maps to Open-Apple / Command.
  - macOS Option maps to Closed-Apple / Option.
  - F1 aliases Open-Apple.
  - F2 aliases Closed-Apple.
- Remap modern macOS arrow key scan codes into the classic IIgs ADB arrow positions.
- Capture key down, key up, modifier-only changes, and Command-key equivalents from the focused video surface.
- Queue host input into the emulator runner so the background emulation loop owns all `IIGSMachine` mutation.
- Update `IIGSDebugger` to use the same key mapper instead of forwarding raw macOS key codes directly.
- Add XCTest coverage for key translation, modifier bit layout, and key down/up ordering.
- Acceptance target: boot ROM 01, enter BASIC mode, type and run a small BASIC sample from the `ADBTest` window.

## Validation

- Build `ADBTest` with `xcodebuild`.
- Run focused XCTest coverage for keyboard mapping and existing ADB controller behavior.
- Optionally launch `ADBTest` through the project run script for manual BASIC typing verification.

## ADBTest Review Pass

- Fix physical F1/F2/F12 aliases so they carry the IIgs modifier state expected by the ADB controller, matching the working bottom-bar commands.
- Keep alphanumeric, shifted capitals, Return, and left/right/down arrow handling covered by shared mapper tests.
- Send macOS Up Arrow as the firmware escape cursor-up sequence for BASIC/Monitor editing, because the raw control character is not a visible cursor-up command in the ROM text input path.
- Render the active firmware cursor with the IIgs checkerboard block glyph instead of a solid rectangle.
- Preserve ROM-faithful Delete/Backspace behavior for now: BASIC backs up the input buffer and display cursor, and the next typed character overwrites the previous location.

## DiskTest Harness

- Clone the successful `ADBTest` harness into a new macOS app target named `DiskTest`.
- Keep the same ROM loading, emulator frame loop, keyboard bridge, window title updater, and AppKit-backed video surface.
- Add a core disk-image loading path that classifies:
  - `2IMG` / `.2mg` / `.2img` images.
  - raw 512-byte block images such as `.po`, `.hdv`, and `.raw`.
  - raw 140K 5.25 images with DOS 3.3 / ProDOS sector-order hints from `.do`, `.dsk`, and `.po`.
  - raw 800K 3.5 images.
  - `.nib` track images.
  - `WOZ1` / `WOZ2` images.
- Add machine-level mount, eject, and mounted-status APIs for:
  - SmartPort slot 7 units.
  - IWM slot 6 5.25 drives.
  - IWM slot 5 3.5 drive containers.
- Add `DiskTest` UI controls for `s7u1`, `s7u2`, `s6d1`, `s6d2`, `s5d1`, and `s5d2`.
- Route disk mount/eject requests through the emulator runner queue so the background emulation loop owns all `IIGSMachine` mutation.
- Show which slot/unit/drive currently has media mounted, the image name, the parsed image kind, block count where applicable, and read-only state.
- Keep writes in memory for this first pass; file writeback and dirty-image prompts are future work.
- Treat 3.5 raw media as mounted state now, with deeper ROM-visible 3.5 IWM protocol behavior left as future hardening.

## DiskTest Validation

- Build `DiskTest` with `xcodebuild`.
- Run focused XCTest coverage for disk image loading, SmartPort mount/eject status, and floppy mount/eject status.
- Manually mount a bootable SmartPort image before reset and verify the ROM-visible boot path once a local disk fixture is available.

## DiskTest Review Pass

- Fixed: `Cold Reset` now uses an emulator power-cycle path that clears RAM, resets CPU/hardware state, keeps ROM installed, and preserves mounted media so the ROM can probe it after reset.
- Fixed: slot 5 3.5 IWM status reads now decode the selected 3.5 status function instead of reporting write-protect for every query, so mounted media is no longer misreported as "no drive connected".
- Fixed: raw 800K 3.5 images now expose encoded 3.5 address/data fields through IWM reads, including zone-based sectors-per-track and 2:1 physical-sector interleave.
- Fixed: slot 5 3.5 drive control now handles motor-on/off, inward/outward step commands, and upper/lower head selection well enough for ROM-visible media reads.
- Fixed: Battery RAM now ships with checksum-backed slot/startup defaults, exposes safe snapshot/load APIs, and DiskTest persists the 256-byte BRAM image across app launches.
- Fixed: slot 5 3.5 disk-switched status now follows eject/unmount state and is cleared by the ROM control action or controller reset, addressing GS/OS boot error `$002E`.
- Fixed: `DiskTest` and `ADBTest` now include a `Control Panel` button that issues an Option-Reset through the ADB reset/modifier path.
- Fixed: bordered Super Hi-Res frames are now displayed with the same double-height pixel aspect as raw 640x200 frames, so GS/OS no longer appears horizontally squashed in the test harness.
- Fixed: reading the video counters at `$C02E/$C02F` now clears the `$C023` scanline interrupt pending bit, matching the hardware behavior GS/OS and the built-in Control Panel expect when QuickDraw starts using scanline interrupts.
- Fixed: Super Hi-Res shadow inhibit now honors `$C035` bit 3 (`$08`) instead of bit 4, matching the IIgs Shadow register behavior and preventing ROM/QuickDraw-era code from prematurely shadowing bank `$01` graphics memory into `$E1`.
- Fixed: slow memory banks `$E0/$E1` below `$C000` are now separate from fast banks `$00/$01`, so auxiliary RAM writes do not clobber ROM/Toolbox jump-table state used during GS/OS and Control Panel startup.
- Fixed: `$C046` now reports the system IRQ line on bit 0 alongside video pending bits, matching ROM polling expectations while keeping VBL off the sign bit that would trigger diagnostics.
- Fixed: CPU `WAI` now wakes when an interrupt line is already asserted, which avoids sleeping through pending scheduler-driven IRQ sources.
- Fixed: emulation-mode hardware interrupts now stack the status byte with the Break bit clear, while `BRK`/`PHP` stack it set. This stopped ROM 01 from routing VBL IRQs through BRK/monitor flow and leaking page-1 stack frames.
- Fixed: native direct-indexed indirect addressing now uses the full 16-bit direct-page pointer address, protecting Toolbox-era code paths that move the direct page away from zero.
- Verified: `System.Disk.po` cold boots from slot 5 drive 1 to the GS/OS Finder desktop with normal VBL enabled.
- Verified: `Where in the USA is Carmen Sandiego (Disk 1 of 2).2mg` no longer drops into the ProDOS 16 memory dump and reaches its GS/OS-style desktop when booted via `PR#5`.
- Verified: Option-Reset reaches the startup Control Panel menu and selecting `1` opens the built-in Control Panel without the patterned display.
- Documented: DiskTest boot failures, probing methods, milestones, and root causes are captured in `DISKTEST_BOOT_LEARNINGS.md` for future reference.

## DiskTest Future Hardening

- Add file-backed write-through or explicit dirty-image export before allowing default writable host images.
- Deepen 3.5 IWM timing/handshake fidelity if boot media still stalls after encoded-track support.
- Expand BRAM/RTC modeling with ROM 03-specific defaults and user-facing controls for startup slot/scan policy.
- Add mouse support so GS/OS desktop applications and mouse-driven demos can be exercised inside DiskTest.
- Add an in-session Classic Desk Accessory trigger using Apple-Control-Escape, separate from the current Option-Reset startup Control Panel path.
- Add partition/container selection for images with multiple mountable partitions.
- Add debugger/CLI disk mounting commands that share the same loader as `DiskTest`.
