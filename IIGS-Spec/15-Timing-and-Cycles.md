# Apple IIGS Emulator Specification: Timing and Cycles

## Feature: Master clock and CPU speed

**Expected behavior:** Base all emulated time on the IIgs 28.63636 MHz crystal. Slow Apple II timing is approximately 1.020484 MHz after periodic stretched cycles. Fast CPU timing is 28 MHz divided by 8, approximately 3.579545 MHz, subject to memory and I/O wait states. `$C036` bit 7 selects fast mode when set and slow mode when clear.

**Registers affected:** `$C036`, CPU cycle counter, event scheduler, IWM forced-slow state.

**Memory addresses involved:** `$C036`, I/O page, memory regions with slow access behavior.

**Edge cases:** Every 65th slow cycle has a stretch component. Some I/O, especially disk, must force slow timing regardless of fast-mode state. Switching speed mid-frame must preserve absolute time, not restart device timers.

**Known compatibility notes:** Benchmarks, music players, serial baud rates, and disk code can expose inaccurate speed switching. Optional accelerator-card behavior should be separated from stock IIgs timing.

**Test cases:**

- Run fixed instruction loop for one frame in slow and fast mode. Expected: fast mode executes about 3.5x as many simple cycles absent wait states.
- Toggle `$C036` during a loop. Expected: event times remain monotonic and no frame is skipped.

**References:**

- Apple IIGS Hardware Reference.
- WDC W65C816S data sheet.

## Feature: Video schedule

**Expected behavior:** Schedule one video frame every 17030 slow cycles. A scan line is 65 slow cycles. Visible fetches occur during the 40-cycle display window; borders and blanking occupy the rest. VBL and scanline events should be generated from this schedule.

**Registers affected:** `$C019`, `$C02E`, `$C02F`, `$C023`, `$C041`, `$C046`.

**Memory addresses involved:** Video memory, counter/status registers.

**Edge cases:** `$C019` and `$C02E/$C02F` have boundary-phase differences. Mid-line soft-switch writes should be ordered by cycle time relative to the fetch window. Floating-bus reads should derive from the byte currently or recently fetched by video when in visible display.

**Known compatibility notes:** Raster split demos and floating-bus tests require line and horizontal counter behavior close to hardware.

**Test cases:**

- Write border color at several horizontal positions. Expected: visible border split positions track cycle timing.
- Poll floating bus while displaying a known hires pattern. Expected: returned bytes correlate with current display address.

**References:**

- Apple IIGS Hardware Reference.
- Sather, Understanding the Apple II.

## Feature: Device event scheduling

**Expected behavior:** Maintain future events for VBL, scanline IRQ, one-second/quarter-second ticks, DOC oscillator completions, SCC baud/timer events, IWM motor-off delay and media writeback, and paddle timeouts. The CPU core should execute until the nearest event or interrupt boundary, service it, then continue.

**Registers affected:** Device-specific status and interrupt registers; CPU IRQ state.

**Memory addresses involved:** `$C023`, `$C041`, `$C046`, `$C047`, `$C03C`..`$C03F`, `$C0E0`..`$C0EF`, SCC registers, `$C064`..`$C070`.

**Edge cases:** Multiple events at the same cycle must be serviced in a deterministic hardware-compatible priority. If an event enables IRQ while `I=0`, IRQ should be taken at the next instruction boundary. Changing DOC frequency or wave size while playing must reschedule the oscillator completion.

**Known compatibility notes:** Sound and serial timing are sensitive to accumulating fractional samples/cycles. Avoid using host wall-clock time for device phase except to throttle final execution speed.

**Test cases:**

- Program DOC oscillator, then change frequency mid-note. Expected: current output is rendered up to change time and future event is recalculated.
- Trigger paddle and advance cycles. Expected: paddle status changes at the configured timeout independent of host frame pacing.
- Queue VBL and DOC event same cycle. Expected: both sources are reflected and IRQ remains asserted until both are cleared.

**References:**

- Apple IIGS Hardware Reference.
- Ensoniq ES5503 DOC documentation.
