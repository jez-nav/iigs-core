# Apple IIGS Emulator Specification: Boot Sequence

## Feature: Power-on reset

**Expected behavior:** On cold reset, initialize CPU to 65C816 emulation mode, clear direct/data banks, set stack to `$01FF`, set interrupt disable, force 8-bit accumulator and indexes, and fetch reset vector from `$00/FFFC`. Initialize hardware registers to IIgs power-on defaults closely enough for ROM self-test and boot firmware. ROM 03 should expose power-on status in `$C036` bit 6.

**Registers affected:** CPU `A`, `X`, `Y`, `S`, `D`, `DBR`, `PBR`, `PC`, `P`; `$C021`..`$C036`; `$C041`; `$C068`; ADB, DOC, IWM, SCC, clock/BRAM registers.

**Memory addresses involved:** Reset vector `$00/FFFC`; ROM banks; low RAM; I/O page `$C000`..`$C0FF`.

**Edge cases:** Warm reset should preserve more RAM and device state than cold reset. Control-Open-Apple-Reset behavior is firmware-mediated and should be represented through key/modifier state plus reset line. `STP` can require reset to resume CPU execution.

**Known compatibility notes:** ROM startup may inspect ADB revision, clock state, disk-switched flags, and memory size. Bad initial values can send firmware into diagnostics or configuration paths.

**Test cases:**

- Cold reset ROM 03. Expected: `$C036` power-on bit visible until firmware clears/uses it.
- Warm reset after writing RAM. Expected: RAM contents preserved except firmware-cleared regions.
- Reset while IWM motor is on. Expected: motor/device state returns to reset defaults per hardware model.

**References:**

- Apple IIGS Firmware Reference.
- Apple IIGS Hardware Reference.

## Feature: Device probing and boot selection

**Expected behavior:** Allow ROM firmware to probe slots and boot according to control-panel configuration. Slot 5 is normally 3.5 inch IWM media, slot 6 is 5.25 inch IWM media, and slot 7 is SmartPort/block device. Slot firmware must expose expected entry points and status so firmware can decide whether media is present.

**Registers affected:** CPU registers per slot firmware; IWM and SmartPort status; ADB keyboard modifiers for alternate boot commands.

**Memory addresses involved:** `$C500`, `$C600`, `$C700`, `$C70A`, `$C70D`, IWM `$C0E0`..`$C0EF`, SmartPort command buffers.

**Edge cases:** Empty drives should report no media without hanging boot. Write-protected boot media must still be readable. Disk-switched flags should be clear at initial boot unless media changed after power-on.

**Known compatibility notes:** ProDOS 8 scans devices differently from GS/OS. ROM 01 and ROM 03 have different control panel storage and SmartPort details.

**Test cases:**

- Boot with only slot 6 140 KB image. Expected: Disk II/ProDOS boot path reads block/sector 0 and starts loader.
- Boot with slot 7 hard disk and no floppies. Expected: SmartPort status/read path loads boot blocks.
- Boot with no media. Expected: firmware enters monitor/control-panel/no-boot path without emulator crash.

**References:**

- Apple IIGS Firmware Reference.
- ProDOS 8 Technical Reference Manual.

## Feature: Boot media reads

**Expected behavior:** During boot, IWM and SmartPort reads must be observable as normal hardware transactions. The emulator may cache decoded sectors/blocks internally, but the visible results must match hardware timing/status sufficiently for firmware and boot loaders.

**Registers affected:** IWM latches/status; CPU registers for firmware routines; SmartPort return registers.

**Memory addresses involved:** Boot blocks/sectors, firmware load buffers, `$C0E0`..`$C0EF`, `$C70A/$C70D`.

**Edge cases:** Some boot loaders switch CPU speed, memory mapping, or language-card state while loading. Disk reads can cross page and bank boundaries. SmartPort extended buffers can target banks above `$00`.

**Known compatibility notes:** GS/OS boot from hard disk uses SmartPort status capabilities; ProDOS 8 boot from 5.25 media uses sector order and slot firmware assumptions.

**Test cases:**

- Boot ProDOS 8 from `.po` image. Expected: correct sector order and loader execution.
- Boot GS/OS from SmartPort. Expected: extended memory buffers load correctly.
- Boot with fast mode enabled. Expected: device timing still returns stable data.

**References:**

- Apple IIGS Firmware Reference.
- ProDOS 16 Reference Manual.
- GS/OS Reference.
