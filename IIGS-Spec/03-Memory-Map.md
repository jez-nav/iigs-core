# Apple IIGS Emulator Specification: Memory Map

## Feature: 24-bit address space

**Expected behavior:** Present a 16 MB 65C816 address space divided into 256 banks of 64 KB. Physical RAM occupies contiguous banks starting at `$00`, with at least 256 KB for a base IIgs and commonly 1 MB or more. Banks `$E0` and `$E1` are the slow-memory/shadow banks used by video hardware and Apple II compatibility. ROM occupies the top banks and is selected according to ROM version.

**Registers affected:** `$C068` (`ALTZP`, `RAMRD`, `RAMWRT`, `RDROM`, `LCBANK2`, `ROMBANK`, `INTCXROM`), `$C035` shadow inhibit register, `$C036` speed/shadow-all register, `$C02D` slot ROM register, language-card soft switches `$C080`..`$C08F`.

**Memory addresses involved:**

| Address range | Expected mapping |
| --- | --- |
| `$00/0000`..`$00/01FF` | Zero page and stack, optionally alternate zero page/stack in bank `$01` or `$E1` via `ALTZP` |
| `$00/0200`..`$00/BFFF` | Main/aux RAM with Apple II video-page and RAMRD/RAMWRT remaps |
| `$00/C000`..`$00/C0FF` | Soft switches and motherboard I/O |
| `$00/C100`..`$00/C7FF` | Slot firmware windows |
| `$00/C800`..`$00/CFFF` | Shared expansion ROM window, internal or slot-selected |
| `$00/D000`..`$00/FFFF` | Language-card RAM or ROM depending on `$C080`..`$C08F` and `$C068` |
| `$E0/0000`..`$E1/FFFF` | Slow memory and display-visible shadow banks |
| `$FC/0000`..`$FF/FFFF` | ROM 03 image |
| `$FE/0000`..`$FF/FFFF` | ROM 01 image |

**Edge cases:** The CPU can access bank `$E0/C000` and `$E1/C000`; these accesses must behave consistently with IIgs I/O shadowing rules. Bank `$00` and `$01` language-card areas can be mapped differently from `$E0`/`$E1` when I/O and language-card shadowing are inhibited. Writes to non-installed RAM should either ignore or return open-bus-like values; avoid wrapping into installed RAM unless explicitly modeling a known card.

**Known compatibility notes:** ROM 03 expects writable power-on status in `$C036` bit 6. Programs that test memory size may probe banks above installed RAM and expect no destructive aliasing. ROM checksums and diagnostics are sensitive to ROM bank placement.

**Test cases:**

- With ROM 01, read `$FE/0000` and `$FF/FFFF`. Expected: bytes come from the 128 KB ROM image.
- With ROM 03, read `$FC/0000`..`$FF/FFFF`. Expected: bytes cover the 256 KB ROM image.
- Write `$12` to `$00/0000`, enable `ALTZP`, write `$34` to `$00/0000`, disable `ALTZP`. Expected: original `$12` is visible again.
- Access `$00/C300` then `$00/C800`. Expected: slot-3/internal-ROM selection follows `$C02D` and `INTCXROM` state.

**References:**

- Apple IIGS Hardware Reference.
- Apple IIGS Firmware Reference.

## Feature: Language card and ROM selection

**Expected behavior:** Support Apple II language-card soft switches `$C080`..`$C08F`. These select read ROM vs RAM, write-enable/prewrite state, and bank 1 vs bank 2 for `$D000`..`$DFFF`; `$E000`..`$FFFF` maps the common language-card region. The IIgs state register `$C068` exposes and can directly control the effective state.

**Registers affected:** `$C068` bits 3 (`RDROM`), 2 (`LCBANK2`), internal prewrite/write-enable latch, and optional ROM bank bit.

**Memory addresses involved:** `$C080`..`$C08F`, `$00/D000`..`$00/FFFF`, `$01/D000`..`$01/FFFF`, `$E0/D000`..`$E1/FFFF`.

**Edge cases:** Some language-card switches require a prewrite access before writes are enabled. Reads and writes to `$C080`..`$C08F` both alter latch state and generally return floating bus. Accesses can also affect `INTC8ROM` behavior when C3/C8 ROM windows are active.

**Known compatibility notes:** Apple II diagnostics and DOS/ProDOS loaders depend on exact language-card state transitions. Treat these switches as bus transactions with side effects, not as plain RAM-control variables.

**Test cases:**

- Perform the canonical two-access sequence to enable language-card writes, write to `$D000`, disable writes, and read back through RAM mode. Expected: data persists only after the valid write-enable sequence.
- Toggle `LCBANK2`. Expected: `$D000`..`$DFFF` switches banks while `$E000`..`$FFFF` remains common.

**References:**

- Apple IIe Technical Reference.
- Apple IIGS Hardware Reference.
