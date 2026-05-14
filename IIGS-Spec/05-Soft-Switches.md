# Apple IIGS Emulator Specification: Soft Switches

## Feature: Apple II compatibility switches

**Expected behavior:** Implement `$C000`..`$C07F` as side-effecting I/O, not ordinary RAM. Reads and writes can set latches, clear strobes, return status in bit 7, or return floating bus. The classic switch pairs control 80-column store, main/aux RAM read/write, slot/internal ROM, alternate zero page, 80-column video, alternate character set, text/graphics, mixed mode, page 1/page 2, hires, annunciators, buttons, paddles, and speaker click.

**Registers affected:** `$C068` state bits; video state latches; keyboard strobe; modifier state; paddle timers; annunciator bits; speaker state; slot ROM selection.

**Memory addresses involved:**

| Address | Behavior |
| --- | --- |
| `$C000` read | Keyboard data/strobe status |
| `$C010` | Clear keyboard strobe / ADB access side effect |
| `$C000/$C001` write | Clear/set 80STORE |
| `$C002/$C003` | Select main/aux read RAM |
| `$C004/$C005` | Select main/aux write RAM |
| `$C006/$C007` | Select slot/internal Cx ROM |
| `$C008/$C009` | Select main/alternate zero page and language card |
| `$C00C/$C00D` | Clear/set 80-column video |
| `$C00E/$C00F` | Clear/set alternate character set |
| `$C050/$C051` | Graphics/text |
| `$C052/$C053` | Full/mixed graphics |
| `$C054/$C055` | Page 1/page 2 |
| `$C056/$C057` | Lores/hires |
| `$C058`..`$C05F` | Annunciators, including AN3 double-hires control |
| `$C060`..`$C063` | Button inputs |
| `$C064`..`$C067` | Paddle timer reads |
| `$C070` | Paddle trigger |

**Edge cases:** Reads of `$C050`..`$C057` both change video state and return floating bus. `AN3` is inverted in common naming: double-hires is enabled when the AN3 state selects the appropriate hardware mode. Paddle reads depend on elapsed cycles since `$C070`.

**Known compatibility notes:** Apple II games often poll keyboard and paddles at high frequency. Returning a fixed value from unused switches breaks floating-bus tricks and raster timing tests.

**Test cases:**

- Read `$C050`, then `$C01A`. Expected: graphics mode status set, return value from `$C050` is floating bus.
- Write `$C00D`, read `$C01F`. Expected: bit 7 reports 80-column video enabled.
- Trigger `$C070`, read `$C064` repeatedly with elapsed cycles. Expected: bit 7 clears after paddle-specific timeout.

**References:**

- Apple IIe Technical Reference.
- Apple IIGS Hardware Reference.

## Feature: IIgs-specific control registers

**Expected behavior:** Implement IIgs control/status registers used by firmware and native software. `$C021` controls monochrome/color text status in bit 7. `$C022` controls text foreground/background colors. `$C023` controls one-second and scanline interrupt status/enable bits. `$C029` enables IIgs video features, including super-hires and color double-hires disable. `$C02D` selects internal vs slot ROM per slot. `$C035` controls shadow inhibition. `$C036` controls speed and selected IIgs status bits. `$C068` mirrors and controls memory state.

**Registers affected:** `$C021`, `$C022`, `$C023`, `$C029`, `$C02D`, `$C035`, `$C036`, `$C068`.

**Memory addresses involved:** `$C021`, `$C022`, `$C023`, `$C029`, `$C02D`, `$C035`, `$C036`, `$C068`.

**Edge cases:** `$C023` high bit reflects pending enabled interrupt sources. Writing `$C032` clears selected `$C023` pending bits. `$C036` bit 7 switches fast/slow speed; bit 5 should read as clear; bit 6 is ROM 03 power-on status and is not generally valid on ROM 01. `$C068` writes must immediately recompute memory mapping.

**Known compatibility notes:** Some software writes undocumented combinations to `$C029` and expects only known bits to affect display. ROM 03 firmware can read/write the power-on bit in `$C036`.

**Test cases:**

- Write `$C068=$80`, then read `$C016`. Expected: alternate zero-page status bit set.
- Write `$C029` with SHR bit set, then render from `$E1/2000`. Expected: super-hires mode active.
- Enable scanline interrupt in `$C023` and clear through `$C032`. Expected: IRQ line asserts then deasserts.

**References:**

- Apple IIGS Hardware Reference.
