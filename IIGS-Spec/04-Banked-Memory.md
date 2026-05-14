# Apple IIGS Emulator Specification: Banked Memory

## Feature: Main, auxiliary, and slow-memory banking

**Expected behavior:** Model bank `$00` as Apple II main memory, bank `$01` as auxiliary memory, and banks `$E0`/`$E1` as slow-memory counterparts used by the Mega II and video subsystem. Compatibility soft switches affect reads and writes in bank `$00` and, on the IIgs, also affect bank `$E0` where applicable. CPU-native code can address all installed RAM banks directly by 24-bit address.

**Registers affected:** `$C068` bits `ALTZP`, `PAGE2`, `RAMRD`, `RAMWRT`; `$C000`/`$C001` 80-column store; `$C054`/`$C055` page select; `$C035` shadow inhibit; `$C036` shadow-all.

**Memory addresses involved:** `$00/0000`..`$01/FFFF`, `$E0/0000`..`$E1/FFFF`, text pages `$0400`..`$07FF` and `$0800`..`$0BFF`, hires pages `$2000`..`$3FFF` and `$4000`..`$5FFF`, super-hires `$E1/2000`..`$E1/9FFF`.

**Edge cases:** `ALTZP` redirects zero page, stack, and language-card bank selection as a group. `RAMRD` and `RAMWRT` can independently select main or auxiliary memory for reads and writes. `80STORE` changes how page-2 soft switching affects text and hires memory. Shadowing is a write side effect: CPU writes to a logical RAM page can update display-visible shadow storage even when CPU reads return a different bank.

**Known compatibility notes:** Double-hires and 80-column software often combines `80STORE`, `PAGE2`, `RAMRD`, and `RAMWRT` in unusual sequences. A correct emulator must update both CPU mapping and display shadow state on every relevant switch.

**Test cases:**

- Enable `RAMWRT` only, write `$AA` to `$0400`, disable `RAMWRT`, read `$0400`. Expected: main byte unchanged, auxiliary byte changed.
- Enable `80STORE`, toggle `PAGE2`, write to text-page address. Expected: write target follows page-2 and auxiliary selection rules.
- Toggle `ALTZP`, push bytes to stack. Expected: page `$0100` bank changes with `ALTZP`.

**References:**

- Apple IIGS Hardware Reference.
- Apple IIe Technical Reference.

## Feature: Video shadowing

**Expected behavior:** The IIgs shadows selected bank `$00`/`$01` writes into banks `$E0`/`$E1` so the display generator sees the correct memory without the CPU directly writing slow memory. `$C035` is an inhibit register: a set bit disables shadowing for its associated region. `$C036` bit 4 enables super-hires shadowing from odd expansion banks into `$E1` for software that uses extended-memory page flipping.

**Registers affected:** `$C035`, `$C036`, video mode latches, `RAMWRT`, `PAGE2`, `80STORE`.

**Memory addresses involved:**

| Region | Primary addresses | Display/shadow target |
| --- | --- | --- |
| Text page 1 | `$0400`..`$07FF` | `$E0/0400`..`$E0/07FF` |
| Text page 2 | `$0800`..`$0BFF` | `$E0/0800`..`$E0/0BFF` |
| Hires page 1 | `$2000`..`$3FFF` | `$E0/2000`..`$E0/3FFF` |
| Hires page 2 | `$4000`..`$5FFF` | `$E0/4000`..`$E0/5FFF` |
| Super-hires | `$2000`..`$9FFF` in selected banks | `$E1/2000`..`$E1/9FFF` |
| I/O and language card | `$C000`..`$FFFF` | `$E0`/`$E1` equivalents when enabled |

**Edge cases:** ROM 01 defaults differ for text-page-2 shadowing in common configurations. Super-hires uses bank `$E1`; classic modes use bank `$E0`. Writes into odd expansion banks can shadow into `$E1` when shadow-all is enabled and SHR shadowing is not inhibited.

**Known compatibility notes:** The ROM self-test, desktop graphics, demos using alternate SHR buffers, and VOC-style display tricks can expose incorrect shadow inhibition.

**Test cases:**

- Clear `$C035` bit for SHR shadowing, write bytes to `$01/2000`, enable SHR. Expected: pixels use `$E1/2000` mirror.
- Set the text-page-1 inhibit bit and write `$0400`. Expected: CPU memory changes but display shadow does not.
- Enable shadow-all, write to bank `$03/2000`. Expected: configured odd-bank writes can update `$E1/2000`.

**References:**

- Apple IIGS Hardware Reference, shadowing and memory expansion sections.
