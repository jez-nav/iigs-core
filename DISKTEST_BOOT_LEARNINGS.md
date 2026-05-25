# DiskTest Boot And Disk Mounting Learnings

This note records the DiskTest work since the last committed baseline, starting with the clone of the successful ADBTest harness and ending with GS/OS and the built-in Control Panel booting cleanly from mounted 3.5 media.

## Starting Point

- `ADBTest` had already proven the window, video surface, ROM boot loop, and host keyboard bridge.
- `DiskTest` reused that shape and added disk image loading, mounted-drive status, mount/eject UI, reset controls, and a Control Panel button.
- The first disk goal was modest: mount 2MG, PO, raw floppy/block, NIB, and WOZ-style images into emulator-visible slots/drives, then let ROM 01 discover them.
- The first visible disk target was slot 5 drive 1, because 800K 3.5 media exercises IWM behavior, BRAM startup settings, ROM disk probing, GS/OS, QuickDraw, VBL IRQs, and Super Hi-Res together.

## Milestones

1. DiskTest target created
   - Cloned the ADBTest harness into `DiskTest`.
   - Added mount/eject controls for SmartPort units, 5.25 drives, and 3.5 drives.
   - Added parsed mount status so the UI shows slot/drive, filename, image kind, size, and read-only state.

2. Disk image loader and mount API
   - Added a shared loader for 2IMG/2MG, raw PO/HDV/RAW, raw 140K, raw 800K, NIB, and WOZ.
   - Added machine-level mount/eject/status APIs.
   - Added tests for image classification, mount state, and eject behavior.

3. Cold Reset became a real power cycle
   - Early Cold Reset behaved like a warm reset and only appended another prompt character.
   - Fixed by adding a power-cycle path that clears RAM and resets CPU/hardware while preserving ROM, mounted media, and BRAM.
   - This made ROM startup probe mounted disks after reset.

4. Slot 5 became ROM-visible
   - `PR#5` initially reported "No device connected".
   - The 3.5 IWM status path was answering the wrong status function.
   - Fixed status decoding, motor/head/step controls, disk-switched behavior, and raw 800K encoded-track reads.

5. BRAM was added
   - ROM startup depends on Battery RAM settings, including startup scan/default slot behavior.
   - Added checksum-backed 256-byte BRAM defaults and snapshot/load APIs.
   - DiskTest persists BRAM across launches.

6. GS/OS began loading, then failed with `$002E`
   - After the 3.5 fixes, ROM and ProDOS could find the disk.
   - GS/OS reported `Unable to load START.GS.OS file. Error=$002E`.
   - Disk-switched status and 3.5 media state were tightened so GS/OS no longer thought the mounted disk had changed or disappeared mid-boot.

7. GS/OS and Control Panel reached QuickDraw, then patterned out
   - `System.Disk.po` briefly showed the GS/OS splash, then collapsed into a regular colored pattern.
   - Option-Reset Control Panel did the same after selecting `1`.
   - Demos such as XMAS_DEMO and NUCLEUS03 could animate, which suggested the renderer was mostly fine and the failure was in deeper ROM/Toolbox/interrupt state.

8. The first QuickDraw-era blockers were removed
   - Fixed Super Hi-Res display scaling in DiskTest so GS/OS was not horizontally squashed.
   - Fixed `$C02E/$C02F` video-counter reads to clear `$C023` scanline pending state.
   - Fixed `$C035` Super Hi-Res shadow inhibit to use bit 3 (`$08`), not bit 4.
   - Fixed slow memory banks `$E0/$E1` below `$C000` so they do not alias fast banks `$00/$01`; this protected ROM/Toolbox jump-table memory from auxiliary RAM writes.

9. VBL IRQ handling exposed the final boot blocker
   - With VBL suppressed after Super Hi-Res first appeared, `System.Disk.po` reached the Finder desktop.
   - With normal VBL enabled, it stalled near the splash.
   - That narrowed the problem to interrupt delivery, not disk decoding or graphics rendering.

10. Final CPU interrupt fix
    - In emulation mode, hardware IRQs were stacking the status byte with the Break bit set.
    - ROM 01 uses that stacked Break bit to distinguish real IRQs from BRK/monitor entries.
    - Because the bit was wrong, VBL IRQs chained through the monitor/old-vector path and accumulated page-1 stack frames.
    - Fixed by making hardware IRQ/NMI/ABORT stack Break clear, while BRK/PHP stack Break set.
    - Added CPU tests for emulation IRQ and BRK stacked status bytes.

## Root Causes

| Symptom | Root Cause | Fix |
| --- | --- | --- |
| Cold Reset looked warm | Reset path did not clear RAM/power-cycle hardware | Added `powerCycle` path and wired DiskTest Cold Reset to it |
| `PR#5` said no device connected | Slot 5 3.5 status reads were not decoding the requested status function | Implemented function-specific 3.5 status behavior |
| GS/OS `$002E` loading `START.GS.OS` | Mounted 3.5 disk state and disk-switched status were not stable enough for GS/OS | Fixed disk-switched tracking and 3.5 controller reset/control handling |
| GS/OS splash was squashed | DiskTest displayed bordered Super Hi-Res with the wrong pixel aspect | Used the same double-height aspect as the 640x200 raw frame path |
| QuickDraw/Control Panel patterned display | Several hardware fidelity gaps surfaced only once Toolbox graphics and interrupts started | Fixed scanline IRQ clear behavior, `$C035` shadow inhibit, slow-bank separation, and emulation IRQ status stacking |
| VBL-on boot stalled but VBL-suppressed boot reached Finder | Hardware IRQs in emulation mode stacked Break set, so ROM treated VBL as BRK/monitor flow | Added `statusByteForStack(breakFlag:)` and pushed Break clear for hardware interrupts |
| Concern about 16 MB RAM exposure | The backing array represents 24-bit address space, not installed RAM | `maximumExpansionRAMSize` caps backed expansion RAM at 8 MB; unmapped high banks return unmapped behavior |

## Probing Methods

- Headless Swift probes linked against the built `IIGSCore.framework`.
- Frame-by-frame boot runs with mounted local disk fixtures:
  - `System.Disk.po`
  - `Where in the USA is Carmen Sandiego (Disk 1 of 2).2mg`
  - `XMAS_DEMO`
  - `NUCLEUS03`
- PPM frame dumps converted to PNG with `sips` to inspect the exact emulator frame at the end of a run.
- Boot modes in the temporary probe:
  - cold boot with mounted media
  - warm reset plus typed `PR#5`
  - Option-Reset Control Panel path
  - VBL-suppressed control run
- Runtime sampling:
  - current PC/registers per milestone frame
  - recent disassembly
  - IWM access counters and track reads
  - `$C041`, `$C046`, `$C047`, `$C023`, `$C032`, `$C035`, and `$C036` state
  - stack and direct-page memory windows
  - Super Hi-Res memory, SCB, and palette samples
- Focused late-IRQ probe to inspect VBL IRQ entry, vector flow, and page-1 stack growth.
- DiskTest app builds and screen-level checks, with Computer Use attempted for UI inspection and headless renderer captures used as the reliable visual proof.
- XCTest passes at each stabilization point, ending with a full `IIGSCore` test run.

## Verification Results

- `System.Disk.po` cold boots to the GS/OS Finder desktop.
- Carmen `.2mg` no longer drops into the ProDOS 16 memory dump; it reaches the GS/OS-style desktop with the game disk mounted.
- Option-Reset shows the startup Control Panel menu.
- Selecting `1` opens the built-in Control Panel cleanly.
- `DiskTest` builds successfully.
- Full `xcodebuild test -project IIGSCore.xcodeproj -scheme IIGSCore -configuration Debug -derivedDataPath Build/DerivedData` passes.

## Useful Takeaways

- Disk boot failures are often not storage failures. Once the ROM can see a disk, GS/OS quickly exercises memory mapping, BRAM, interrupts, shadowing, video counters, and Toolbox entry points.
- The `System.Disk.po` VBL-suppressed run was the decisive isolation test: disk and graphics could complete if VBL IRQs were kept out of the equation.
- The Apple IIgs ROM relies on small CPU details, especially the emulation-mode stacked status byte, to route interrupts correctly.
- Demos are useful graphics smoke tests, but GS/OS and the Control Panel are better whole-machine fidelity tests.
- Keep future probes able to dump a final frame, register state, I/O soft-switch state, recent disassembly, and stack memory in one run. The failure pattern was only obvious after correlating all of those.

## Remaining Future Work

- Mouse support, needed for GS/OS desktop interaction and some demos.
- File-backed writable disk images or explicit dirty-image export.
- Deeper 3.5 IWM timing if more finicky media exposes gaps.
- ROM 03 BRAM defaults and compatibility checks.
- Classic Desk Accessory trigger using Apple-Control-Escape, separate from startup Option-Reset.
- Multi-partition/container selection for larger images.
- Shared debugger/CLI mount commands using the same disk loader as DiskTest.
