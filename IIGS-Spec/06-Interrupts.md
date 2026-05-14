# Apple IIGS Emulator Specification: Interrupts

## Feature: CPU interrupt entry

**Expected behavior:** Support `IRQ`, `NMI`, `RESET`, `BRK`, `COP`, and `ABORT` vector behavior for a 65C816. Maskable IRQ is taken only when `I=0` and at least one enabled interrupt source is pending. On interrupt entry, stack the proper frame for emulation or native mode, clear decimal mode, set interrupt disable, set `PBR=0`, and load the vector from bank `$00`.

**Registers affected:** CPU `P`, `S`, `PBR`, `PC`; memory stack; device interrupt pending state.

**Memory addresses involved:** Native vectors `$FFE4`..`$FFFF`, emulation vectors `$FFF0`..`$FFFF`, stack memory, I/O interrupt registers `$C023`, `$C032`, `$C041`, `$C046`, `$C047`, ADB `$C027`, DOC register `$E0`, SCC registers.

**Edge cases:** `BRK`/`COP` vectors differ from hardware IRQ vectors. Emulation-mode stack frames omit `PBR`; native frames include it. Pending IRQ after `CLI`, `PLP`, `REP`, or `RTI` must be recognized at an instruction boundary. Reading or writing status registers can clear interrupt sources while CPU `I` remains unchanged.

**Known compatibility notes:** GS/OS and the toolbox use VBL, ADB, DOC, and SCC interrupts. Games and demos can use scanline IRQs and expect stable phase. Masking a device at its enable register should drop the global IRQ if no other source is active.

**Test cases:**

- In native mode, force IRQ with `I=0`. Expected: stack contains `PBR`, PCH, PCL, `P`; `PBR=0`; `I=1`; vector from native IRQ.
- Set `I=1` with IRQ pending, then execute `CLI`. Expected: IRQ taken after `CLI` completes.
- Trigger `BRK` and IRQ back-to-back. Expected: `BRK` uses BRK vector and stacked break status; IRQ uses IRQ vector.

**References:**

- WDC W65C816S data sheet.
- Apple IIGS Hardware Reference.

## Feature: IIgs interrupt sources

**Expected behavior:** Model a logical OR of enabled interrupt sources. Sources include SCC channel interrupts, scanline interrupt, one-second interrupt, quarter-second interrupt, VBL interrupt, ADB keyboard service request, ADB data, ADB mouse, DOC oscillator completion, and optional expansion-card interrupts.

**Registers affected:** `$C023` scan/1-second status and enables; `$C041` IIgs interrupt enables; `$C046` VBL/quarter-second status; `$C047` clear; ADB `$C027`; DOC interrupt register `$E0`; SCC interrupt pending registers.

**Memory addresses involved:** `$C023`, `$C032`, `$C041`, `$C046`, `$C047`, `$C026`, `$C027`, `$C03C`..`$C03F`, SCC `$C038`..`$C03B`.

**Edge cases:** `$C046` status read can transform the VBL latch representation; `$C047` clears VBL and quarter-second status. `$C023` high bit should reflect any pending `$C023` source. Reading DOC interrupt register `$E0` clears the oldest DOC oscillator interrupt. ADB data valid and interrupt-enable bits interact: valid data without the enable bit should not assert CPU IRQ.

**Known compatibility notes:** Firmware expects no spurious SmartPort IRQs during boot. Some desktop sound code depends on DOC interrupts being queued by oscillator order and cleared one at a time.

**Test cases:**

- Enable `$C041` VBL interrupt and wait one frame. Expected: `$C046` VBL bit set and IRQ asserted; reading/writing `$C047` clears.
- Configure a DOC oscillator with interrupt enabled and a short sample ending in zero. Expected: IRQ asserts; reading DOC `$E0` reports oscillator number and clears that source.
- Enable ADB data interrupt, queue controller data. Expected: `$C027` reports data valid and IRQ asserts until data is read or interrupt disabled.

**References:**

- Apple IIGS Hardware Reference.
- Apple IIGS Firmware Reference.
