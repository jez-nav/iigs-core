# Apple IIGS Emulator Specification: Test Cases

## Feature: Conformance test matrix

**Expected behavior:** Use a layered test matrix: CPU unit tests, memory-map tests, I/O side-effect tests, video rendering tests, audio/DOC tests, ADB input tests, disk-format tests, boot tests, and long-running compatibility tests. Tests should compare externally visible CPU registers, memory bytes, device status bits, audio events, video pixels, or boot outcomes.

**Registers affected:** All CPU and device registers as covered by individual subsystem tests.

**Memory addresses involved:** Entire address space, with focus on `$00/0000`..`$00/FFFF`, banks `$E0/$E1`, ROM banks, and `$C000`..`$C0FF`.

**Edge cases:** Tests must include read side effects, write side effects, timing boundaries, bank wrapping, absent media, write protection, and missing RAM. Avoid tests that depend on host rendering latency.

**Known compatibility notes:** Passing CPU instruction tests is insufficient; many IIgs failures are soft-switch or timing failures. Passing GS/OS boot is necessary but still misses copy-protected disk and raster behavior.

**Test cases:**

- Run 65C816 functional test suites for all opcodes in emulation and native modes.
- Run ROM 01 and ROM 03 self-tests.
- Boot ProDOS 8 from slot 6, boot 800 KB system disk from slot 5, boot GS/OS from slot 7.
- Render known text, hires, double-hires, and SHR screenshots and compare pixel hashes.
- Play known DOC sample program and verify oscillator interrupts and mixed sample envelope.
- Exercise ADB keyboard/mouse packets and firmware low-memory mouse coordinates.
- Read/write WOZ media and verify CRC and track mutation.

**References:**

- Apple IIGS Hardware Reference.
- Apple IIGS Firmware Reference.
- WDC W65C816S data sheet.
- WOZ disk image reference.

## Feature: CPU tests

**Expected behavior:** Validate every opcode, addressing mode, flag transition, stack frame, interrupt vector, and cycle class. Include decimal arithmetic and native/emulation transitions.

**Registers affected:** CPU registers and flags.

**Memory addresses involved:** Test RAM in multiple banks, stack, vector table, I/O trap pages.

**Edge cases:** `BRK/COP`, `RTI`, `XCE`, `REP/SEP`, `MVN/MVP`, direct page misalignment, page-cross dummy reads, emulation-mode stack wrap, long addressing bank wrap.

**Known compatibility notes:** Read-modify-write instructions against I/O must be tested as bus sequences, not just final values.

**Test cases:**

- `ADC/SBC` binary and decimal, 8- and 16-bit, all carry/overflow combinations.
- `JMP ($xxFF)` with optional 6502 bug mode.
- IRQ during `WAI`; IRQ after `CLI`; IRQ pending while `I=1`.

**References:** WDC W65C816S data sheet.

## Feature: Memory and soft-switch tests

**Expected behavior:** Validate memory mapping after every soft-switch and direct state-register write. Confirm shadow writes update display-visible memory only when enabled.

**Registers affected:** `$C000`..`$C01F`, `$C035`, `$C036`, `$C068`, `$C080`..`$C08F`.

**Memory addresses involved:** `$0000`..`$01FF`, `$0400`..`$0BFF`, `$2000`..`$9FFF`, `$C000`..`$FFFF`, banks `$00/$01/$E0/$E1`.

**Edge cases:** Independent read/write bank selection, `ALTZP`, language-card prewrite, I/O shadow inhibit, ROM 01 text-page-2 behavior.

**Test cases:**

- Exhaustively toggle `RAMRD`, `RAMWRT`, `ALTZP`, `PAGE2`, `80STORE` and verify target bank for read/write.
- Toggle each `$C035` inhibit bit and write to corresponding region.
- Validate `$C011`..`$C01F` status reads after each switch.

**References:** Apple IIGS Hardware Reference.

## Feature: Video tests

**Expected behavior:** Compare rendered output and timing counters against known expected values. Include frame-level and scanline-level checks.

**Registers affected:** Video soft switches, `$C019`, `$C021`, `$C022`, `$C029`, `$C02E`, `$C02F`.

**Memory addresses involved:** Classic video pages and SHR memory/palettes.

**Edge cases:** Mixed mode, 80-column text, double-hires AN3, SHR 320/640/fill/palette changes, mid-line switches, VBL boundary.

**Test cases:**

- Pixel-hash golden images for text, lores, hires, double-hires, SHR.
- Counter trace for one full frame.
- Floating bus trace over a known text/hires page.

**References:** Apple IIGS Hardware Reference; Apple Programmer's Introduction to the Apple IIGS Hi-Res Graphics.

## Feature: Device tests

**Expected behavior:** Validate ADB, DOC, IWM, SmartPort, SCC, and clock behavior through their public registers and firmware calls.

**Registers affected:** `$C024`..`$C027`, `$C030`, `$C03C`..`$C03F`, `$C041/$C046/$C047`, `$C0E0`..`$C0EF`, slot firmware registers.

**Memory addresses involved:** ADB RAM, DOC RAM, disk buffers, SmartPort command blocks.

**Edge cases:** ADB interrupt masking, DOC delayed reads and interrupt queue, IWM write protect and disk-switched flags, SmartPort extended pointers.

**Test cases:**

- ADB read-config, set-config, keycode, mouse movement, and interrupt-enable tests.
- DOC RAM auto-increment, oscillator start/stop, `$E0` IRQ clear tests.
- IWM read raw WOZ nibbles and write a sector to writable media.
- SmartPort status/read/write/format/error-code tests.

**References:** Apple IIGS Hardware Reference; Apple IIGS Firmware Reference; WOZ reference.
