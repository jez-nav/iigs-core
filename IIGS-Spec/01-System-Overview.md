# Apple IIGS Emulator Specification: System Overview

## Feature: Machine model

**Expected behavior:** Emulate an Apple IIGS with a 65C816 CPU, Mega II Apple II compatibility hardware, shadowed video memory, Apple Desktop Bus input, Ensoniq ES5503 DOC sound, SCC serial ports, battery-backed clock/parameter RAM, IWM floppy controller, and SmartPort block-device firmware. The emulator must boot ROM 01 and ROM 03 images and must preserve Apple IIe compatibility for soft switches, language card behavior, and slot firmware dispatch.

**Registers affected:** CPU registers `A`, `X`, `Y`, `S`, `D`, `DBR`, `PBR`, `PC`, `P`, the IIgs state register at `$C068`, shadow register `$C035`, speed register `$C036`, video mode latches, DOC registers, ADB controller registers, IWM phase/Q6/Q7 latches, and interrupt status registers.

**Memory addresses involved:** 24-bit address space `$00/0000` through `$FF/FFFF`; motherboard RAM in banks `$00` upward; system ROM in banks `$FC` through `$FF` for ROM 03 and `$FE` through `$FF` for ROM 01; I/O at `$00/C000` through `$00/CFFF` and mirrored/shadow-visible I/O in banks `$E0` and `$E1`; video shadow memory in banks `$E0` and `$E1`.

**Edge cases:** Bank `$00`/`$01` Apple II compatibility accesses can be redirected by soft switches while banks `$E0`/`$E1` supply the physical slow-memory view used by display hardware. Reads from many I/O addresses return the current floating bus value while also changing latch state. Reset and interrupt vectors must be fetched from the memory map selected by CPU mode and ROM mapping, not from an emulator-private shortcut.

**Known compatibility notes:** ROM 01 uses a 128 KB ROM image mapped into `$FE` and `$FF`. ROM 03 uses a 256 KB ROM image mapped into `$FC` through `$FF` and has different firmware expectations for ADB revision and power-on state. A compatibility target should pass ROM self-tests, boot ProDOS 8 and GS/OS, and run Apple II software that depends on //e soft-switch side effects.

**Test cases:**

- Cold reset with ROM 01 and ROM 03. Expected: CPU starts in emulation mode from reset vector `$00/FFFC`, ROM startup executes, keyboard/mouse firmware probes complete.
- Toggle `$C050`..`$C057`, then read `$C01A`..`$C01D`. Expected: readable status bits match the last video soft-switch state.
- Write different bytes to bank `$00/0400` and `$E0/0400` with shadowing enabled/disabled. Expected: display-visible bytes follow shadow-register rules.
- Boot slot 6 5.25 inch, slot 5 3.5 inch, and slot 7 SmartPort media. Expected: the correct firmware path and device protocol are used for each.

**References:**

- Apple IIGS Hardware Reference.
- Apple IIGS Firmware Reference.
- Apple Technical Introduction to the Apple IIGS.
- WDC W65C816S data sheet.

## Feature: Timing domains

**Expected behavior:** Maintain a master Apple II timing base using 17030 nominal 1 MHz cycles per video frame, 262 scan lines per frame, and 65 cycles per scan line. The effective frame rate is approximately 59.92 Hz because the IIgs derives timing from the 28.63636 MHz color crystal with periodic stretched cycles. CPU speed can switch between Apple II slow timing and IIgs fast timing, while some I/O devices force slower access timing.

**Registers affected:** `$C036` fast/slow bit, video counters `$C02E`/`$C02F`, VBL status `$C019`, interrupt enable/status `$C041`/`$C046`, IWM Q6/Q7 latches, DOC oscillator event state.

**Memory addresses involved:** `$C019`, `$C02E`, `$C02F`, `$C036`, `$C041`, `$C046`, `$C047`, `$C0E0`..`$C0EF`.

**Edge cases:** IWM accesses with the motor active must be cycle-sensitive for copy-protected media. Reads of `$C019` have a one-cycle boundary sensitivity relative to the video counter. Mid-scanline video-mode changes affect pixels already fetched differently from pixels fetched after the switch.

**Known compatibility notes:** Nibble copiers, raster-bar demos, scanline IRQ code, and software synthesizers expose timing shortcuts quickly. A fast disk path may be optional, but an accurate path must exist.

**Test cases:**

- Count `$C02F` for one scan line. Expected: the visible fetch window is 40 cycles wide, and the line period is 65 cycles.
- Enable fast mode at `$C036` and run a calibrated loop. Expected: CPU completes more instructions per frame except when device timing forces slow cycles.
- Run scanline interrupt code. Expected: interrupt occurs on the programmed scan line with stable phase from frame to frame.

**References:**

- Apple IIGS Hardware Reference, timing and video chapters.
- KansasFest FPI timing notes by Nathan Mates and contributors.
