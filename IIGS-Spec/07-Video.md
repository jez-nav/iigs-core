# Apple IIGS Emulator Specification: Video

## Feature: Frame timing and counters

**Expected behavior:** Generate 262 scan lines per frame, 65 nominal 1 MHz cycles per line, and 17030 cycles per frame. Visible Apple II graphics occupy 200 super-hires lines or 192 classic lines plus borders. `$C019` reports vertical blank status in bit 7. `$C02E` and `$C02F` expose encoded vertical and horizontal counters.

**Registers affected:** `$C019`, `$C02E`, `$C02F`, video soft-switch latches, scanline interrupt state.

**Memory addresses involved:** `$C019`, `$C02E`, `$C02F`, `$C023`, `$C032`.

**Edge cases:** `$C02E` counts encoded line halves: visible lines begin around `$80`, VBL begins near line 192 for classic modes, the counter wraps through `$FF` and resumes near `$7D`. `$C02F` bit 7 contains the low line-counter bit; low 7 bits encode a horizontal counter that covers `$00`, then `$40`..`$7F`. The visible 40-cycle fetch window is approximately `$58`..`$7F`.

**Known compatibility notes:** Raster effects use `$C02E/$C02F` and floating bus values. A one-cycle discrepancy at VBL boundaries is visible in timing tests.

**Test cases:**

- Poll `$C02E/$C02F` through a frame. Expected: 262-line cadence and 65-cycle line period.
- Poll `$C019` at line 191/192 boundary. Expected: VBL status changes at the documented boundary with cycle-level consistency.

**References:**

- Apple IIGS Hardware Reference.
- Apple IIe Technical Reference.

## Feature: Classic Apple II modes

**Expected behavior:** Render text, lores, double-lores, hires, and double-hires modes using Apple II memory layout and IIgs color controls. Text supports 40/80 columns, alternate character set, flash, inverse, and text/background color register `$C022`. Hires uses the Apple II interleaved scanline address order. Double-hires combines main and auxiliary memory according to 80-column and AN3 state.

**Registers affected:** `$C00C/$C00D` 80-column video, `$C00E/$C00F` alternate character set, `$C050`..`$C057`, `$C05E/$C05F` AN3/double-hires, `$C021`, `$C022`, `$C029`, `$C068`.

**Memory addresses involved:** Text page 1 `$0400`..`$07FF`, text page 2 `$0800`..`$0BFF`, hires page 1 `$2000`..`$3FFF`, hires page 2 `$4000`..`$5FFF`, main/aux banks and `$E0` shadow.

**Edge cases:** Mixed mode displays graphics above line 160 and text below. Page selection interacts with `80STORE`. Color artifacting differs between monochrome, color, hires, and double-hires. Mid-line mode changes should affect the line from the switch point forward when practical.

**Known compatibility notes:** Double-hires software often assumes exact main/aux byte ordering. Some Apple II software uses floating bus reads during visible fetches to infer screen address.

**Test cases:**

- Fill `$0400` with text and toggle `$C00D`. Expected: 80-column display uses auxiliary bytes interleaved with main bytes.
- Fill hires page with known Apple II address pattern. Expected: scan lines map through the classic interleaved order.
- Toggle mixed mode at line 159/160. Expected: bottom text region appears only below the mixed boundary.

**References:**

- Apple IIe Technical Reference.
- Apple IIGS Hardware Reference.
- Sather, Understanding the Apple II.

## Feature: Super-hires

**Expected behavior:** When super-hires is enabled, display 200 lines from bank `$E1`, with pixel data at `$E1/2000`..`$E1/9DFF`, scan-line control bytes at `$E1/9D00`..`$E1/9DFF` as applicable, and palettes at `$E1/9E00`..`$E1/9FFF`. Each line can be 320 mode or 640 mode. 320 mode uses 4 bits per pixel and one of 16 palettes. 640 mode uses 2 bits per pixel with paired palette interpretation. Fill mode repeats the last nonzero color nibble according to the SCB fill bit.

**Registers affected:** `$C029` super-hires bit, `$C035` SHR shadow inhibit, `$C036` shadow-all, palette memory.

**Memory addresses involved:** `$E1/2000`..`$E1/9FFF`; optional bank `$E0`/expansion-bank sources when shadowing feeds `$E1`.

**Edge cases:** Palette changes during a frame affect later fetches using that palette. SCB bit 7 selects 640 mode; SCB low nibble selects palette; fill mode affects 320-mode zero nibbles. Lines can mix 320 and 640 modes across the frame.

**Known compatibility notes:** GS/OS desktop assumes correct 320-mode palette and shadowing. Demos may change SCBs and palettes mid-frame. VOC-style extensions may interlace or select alternate banks; they are optional unless targeting those demos.

**Test cases:**

- Write four bytes of SHR pixel data and palette 0. Expected: eight 320-mode pixels or sixteen 640-mode pixels depending on SCB.
- Change SCB on one line only. Expected: adjacent lines render with independent mode/palette.
- Write palette entries while displaying. Expected: changed palette is reflected without corrupting pixel bytes.

**References:**

- Apple IIGS Hardware Reference.
- Apple Programmer's Introduction to the Apple IIGS Hi-Res Graphics.
