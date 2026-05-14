# Apple IIGS Emulator Specification: SmartPort

## Feature: SmartPort firmware entry points

**Expected behavior:** Provide slot-7 block-device firmware compatible with ProDOS 8 and GS/OS. Support the ProDOS block driver entry at `$Cn0A` and SmartPort entry at `$Cn0D` for the selected slot, normally slot 7. The firmware must parse command parameter blocks from emulated memory, perform block I/O, set carry and accumulator error code on failure, and return byte counts/status in `X`/`Y` as expected by firmware conventions.

**Registers affected:** CPU `A` low byte error code, `X`, `Y`, carry flag, direct-page command bytes for ProDOS calls.

**Memory addresses involved:** Slot firmware `$C700`..`$C7FF`, ProDOS global command area at `D+$42`..`D+$47` for `$Cn0A`, SmartPort command lists addressed by `$Cn0D`, block buffers anywhere in 16-bit or 24-bit memory.

**Edge cases:** Extended SmartPort commands have bit 6 set and use 24-bit pointers plus 32-bit block numbers. Standard commands use 16-bit pointers and 24-bit block counts where applicable. If a unit was just ejected, status should report disk-switched once, then clear that transient state.

**Known compatibility notes:** ProDOS 8 can access a limited number of slot-7 units; GS/OS can use more. Firmware polling may issue unsupported commands while probing; unsupported commands should return documented errors rather than halt.

**Test cases:**

- Call `$C70A` with command 0 status for unit 0. Expected: block count returned in `X/Y`, carry clear.
- Call `$C70D` status command `$00` unit 0 status code 0. Expected: driver status block with unit count, vendor/version fields, carry clear.
- Call unsupported command `$4B`. Expected: carry set, error `$01` bad command.

**References:**

- Apple IIGS Firmware Reference.
- ProDOS 8 Technical Reference Manual.
- Apple SmartPort technical notes.

## Feature: SmartPort commands

**Expected behavior:** Implement status, read block, write block, format, and minimal control. Unit numbers are one-based for SmartPort calls. Blocks are 512 bytes. Status code 0 for a unit reports device status and block count. Status code 3 returns a Device Information Block with device type, name, and capability bits. Read/write transfer one 512-byte block between media and emulated memory.

**Registers affected:** CPU `A`, `X`, `Y`, carry; media write-protect and disk-switched state.

**Memory addresses involved:** SmartPort parameter list: parameter count, unit, buffer/status pointer, block number, control/status code; media backing store.

**Edge cases:** Unit 0 is the driver, not media. Missing units should generally report no device or no drive without corrupting the status buffer. Write-protected media returns write-protect error. Block number beyond media size returns I/O or range error. Format should zero or initialize media only when writable.

**Known compatibility notes:** GS/OS may use extended status and extended block numbers. ProDOS volumes should normally be <= 65535 blocks for ProDOS 8 compatibility, even if SmartPort extended calls can describe larger devices.

**Test cases:**

- Read block 0 from mounted unit 1 into `$2000`. Expected: 512 bytes copied, carry clear.
- Write block 2 to write-protected unit. Expected: carry set, write-protect error, media unchanged.
- Request DIB for unit 1. Expected: status byte, 24/32-bit block count, printable device name, and capability bits.

**References:**

- Apple IIGS Firmware Reference.
- ProDOS 16 and GS/OS references.
