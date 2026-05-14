# Apple IIGS Emulator Specification: Sound and Ensoniq DOC

## Feature: Speaker click

**Expected behavior:** Any read or write of `$C030` toggles the Apple II speaker latch and returns floating bus on reads. The analog output is a click waveform whose amplitude is affected by the IIgs master DOC volume, as on hardware.

**Registers affected:** Speaker latch; DOC master volume nibble in `$C03C`.

**Memory addresses involved:** `$C030`, `$C03C`.

**Edge cases:** Very high click rates must not drop toggles within a video frame. If no toggles occur for a short decay period, output should decay toward zero rather than hold a DC level indefinitely.

**Known compatibility notes:** Apple II games depend on exact toggle timing; GS software can change DOC volume while using `$C030`.

**Test cases:**

- Toggle `$C030` at 1 kHz. Expected: square-like audio at 1 kHz / 2 latch frequency behavior.
- Set DOC volume 0 then toggle `$C030`. Expected: silent or near-silent output.

**References:**

- Apple IIe Technical Reference.
- Apple IIGS Hardware Reference.

## Feature: Ensoniq ES5503 DOC register access

**Expected behavior:** Expose the DOC through the Sound GLU at `$C03C`..`$C03F`. `$C03E/$C03F` form a 16-bit pointer. `$C03D` is the data port. `$C03C` contains global volume in bits 0..3, auto-increment in bit 5, and RAM-vs-register select in bit 6. Reads from `$C03D` are delayed: the returned value is the previously latched data, while the addressed byte is loaded for the next read. When auto-increment is set, the pointer increments after each data access.

**Registers affected:** `$C03C` sound control, `$C03D` data latch, `$C03E/$C03F` pointer, DOC RAM, oscillator registers.

**Memory addresses involved:** `$C03C`, `$C03D`, `$C03E`, `$C03F`; DOC RAM logical `$0000`..`$FFFF`; register pointer space `$0000`..`$00FF`.

**Edge cases:** Register mode decodes pointer bits 0..4 as oscillator number and bits 5..7 as register group. RAM mode accesses 64 KB DOC RAM. Pointer wraps at 16 bits. Writes to unsupported global registers should be ignored or safely logged, not crash compatible software.

**Known compatibility notes:** Some games rely on the delayed-read behavior. Paperboy GS and similar software read the oscillator data register while playback is active and expect the last sample value to be current.

**Test cases:**

- Set pointer to DOC RAM `$1234`, enable RAM and auto-increment, write `$56` then `$78`. Expected: RAM `$1234=$56`, `$1235=$78`, pointer `$1236`.
- Set register pointer to frequency low for oscillator 0, write `$34`; set high, write `$12`. Expected: frequency register is `$1234`.
- Read `$C03D` twice from a known RAM byte. Expected: first read returns old latch, second returns the addressed byte.

**References:**

- Apple IIGS Hardware Reference, Ensoniq DOC section.
- Ensoniq ES5503 DOC documentation.

## Feature: Oscillators, wave RAM, and interrupts

**Expected behavior:** Implement up to 32 DOC oscillators. Each oscillator has frequency low/high, volume, data, wave pointer, control, and wave-size/resolution registers. The DOC scan clock is derived from the 7 MHz clock divided by 8, and the effective oscillator update rate is the scan rate divided by enabled oscillator count plus refresh slots. A zero sample byte or end condition stops or repeats according to control mode. Interrupt-enabled oscillators assert DOC IRQ when they stop or reach their programmed event.

**Registers affected:** Per-oscillator registers: frequency, volume, data/last sample, wave pointer, control, wave size; global `$E0` interrupt register; `$E1` oscillator-enable register.

**Memory addresses involved:** DOC register groups: `$00`..`$1F` frequency low, `$20`..`$3F` frequency high, `$40`..`$5F` volume, `$60`..`$7F` data, `$80`..`$9F` wave pointer, `$A0`..`$BF` control, `$C0`..`$DF` wave size, `$E0`..`$FF` global registers.

**Edge cases:** Control bit 0 halts an oscillator. Free-run, one-shot, sync, and swap modes interact with paired oscillators. Reading `$E0` returns the oldest pending oscillator interrupt encoded with bit 7 clear and clears that pending source. When no DOC IRQ is pending, `$E0` reads as `$FF`. `$E1` sets the number of enabled oscillators as `((value & $3E) >> 1) + 1`.

**Known compatibility notes:** Many programs configure all 32 oscillators even if only a few are audible. Stopping oscillators disabled by `$E1` is required to avoid stale interrupts. Mixing should be signed/centered and volume scaled by oscillator volume and master volume.

**Test cases:**

- Program oscillator 0 with a wave containing nonzero bytes followed by zero, clear halt bit, enable interrupt. Expected: playback stops at zero and DOC IRQ asserts.
- Read `$E0` after two oscillators interrupt. Expected: first read reports first pending oscillator and clears it; second read reports the next.
- Write `$E1=$3E`. Expected: 32 oscillators enabled.

**References:**

- Apple IIGS Hardware Reference.
- Ensoniq ES5503 DOC documentation.
