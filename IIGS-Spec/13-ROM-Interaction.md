# Apple IIGS Emulator Specification: ROM Interaction

## Feature: ROM images and mapping

**Expected behavior:** Load either ROM 01 or ROM 03 images. ROM 01 is 128 KB and maps into banks `$FE` and `$FF`. ROM 03 is 256 KB and maps into `$FC` through `$FF`. The reset vector is read from `$00/FFFC` through the active ROM mapping. ROM contents should not be modified on disk by the emulator.

**Registers affected:** CPU reset state; `$C036` ROM 03 power-on bit; `$C068` ROM/language-card state; `$C02D` slot ROM state.

**Memory addresses involved:** `$FC/0000`..`$FF/FFFF`, `$00/FFFC`, slot ROM windows `$C100`..`$CFFF`.

**Edge cases:** ROM 0 is out of scope unless specifically targeted. ROM image byte order must match CPU byte order as dumped from the machine. ROM 03 firmware may probe ADB version and power-on status differently from ROM 01.

**Known compatibility notes:** ROM self-tests verify checksums and hardware status. Avoid applying silent ROM patches in a hardware-conformance mode; optional compatibility patches should be explicit and documented.

**Test cases:**

- Load 128 KB ROM and read `$FE/0000`. Expected: first byte of ROM image.
- Load 256 KB ROM and read `$FC/0000`. Expected: first byte of ROM image.
- Reset and verify `PC` equals little-endian word at `$FFFC/$FFFD`.

**References:**

- Apple IIGS Firmware Reference.
- Apple IIGS Hardware Reference.

## Feature: Slot firmware and C8 ROM handling

**Expected behavior:** Implement internal firmware and slot firmware selection for `$C100`..`$CFFF`. `$C02D` contains per-slot selection bits where the hardware chooses internal or external slot ROM according to IIgs rules. `INTCXROM` in `$C068` forces internal Cx ROM when enabled. Accessing slot ROMs can enable the shared `$C800` window for the active slot; returning through `$CFFF` or switching slots clears or changes the window as hardware does.

**Registers affected:** `$C02D`, `$C068` `INTCXROM`, internal `INTC8ROM`/slot-C8 latch, CPU `PC` during firmware calls.

**Memory addresses involved:** `$C100`..`$C7FF`, `$C800`..`$CFFF`, `$C02D`, `$C006`, `$C007`.

**Edge cases:** Slot 3 has special internal/external behavior for 80-column firmware compatibility. Accessing `$C3xx` can alter `INTC8ROM`. `$C800` should map to the ROM for the slot whose firmware was last selected, unless internal C8 ROM is forced.

**Known compatibility notes:** Older Disk II software may require a classic slot 6 boot ROM path. IIgs firmware defaults differ from IIe slot behavior and are configurable through the control panel.

**Test cases:**

- Select external slot 6 ROM and execute `$C600`. Expected: `$C800` maps to slot 6 expansion ROM after access.
- Force `INTCXROM`, read `$C300`. Expected: internal firmware bytes regardless of `$C02D`.
- Access `$CFFF`. Expected: shared C8 ROM latch clears where applicable.

**References:**

- Apple IIGS Firmware Reference.
- Apple IIe Technical Reference.

## Feature: Firmware services and low-memory contracts

**Expected behavior:** ROM firmware maintains low-memory vectors, keyboard/mouse state, clock/BRAM access, disk bootstrapping, and toolbox entry points. The emulator should provide hardware behavior that lets firmware perform these jobs naturally rather than replacing firmware routines with host callbacks, except for optional acceleration hooks that preserve register/memory results exactly.

**Registers affected:** CPU registers as specified by firmware calls; ADB/DOC/IWM/SCC hardware registers; low-memory firmware state.

**Memory addresses involved:** Apple II zero page and system globals, toolbox vectors, slot firmware areas, ADB mouse coordinate globals, parameter RAM.

**Edge cases:** Firmware can call hardware in unusual order during self-test. Reads from ADB RAM or clock registers during self-test must return stable values. Mouse firmware may update both bank `$00` and slow-memory mirror locations.

**Known compatibility notes:** GS/OS and toolboxes are sensitive to ROM 01 vs ROM 03 differences. Host shortcuts for disk or ADB must not bypass observable side effects if diagnostics are expected to pass.

**Test cases:**

- Run ROM self-test. Expected: no checksum or hardware failures in conformance mode with matching ROM.
- Boot GS/OS. Expected: firmware SmartPort, ADB, and clock probes complete.
- Call monitor or firmware keyboard input. Expected: hardware keyboard latches update as firmware expects.

**References:**

- Apple IIGS Firmware Reference.
- Apple IIGS Toolbox Reference volumes.
