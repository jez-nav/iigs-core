# IIGSCore Implementation Plan

This is the canonical phase plan for the Apple IIgs emulator core. Keep this file updated when a phase changes, is split, or is completed.

## Current Status

- Phase 0: completed.
- Phase 1: completed.
- Phase 2: completed.
- Phase 3: completed for ROM image validation/mapping.
- Phase 4: completed for the implemented soft-switch and language-card scope.
- Phase 5: partially completed earlier as video/slow-memory shadowing; superseded by the Phase 15 scheduler foundation, with remaining timing accuracy tracked in later hardening work.
- Phase 6: partially completed. It now includes timing-visible video registers, text/SHR rendering, and the Phase 6.5 classic lores/hires extension.
- Phase 6.5: completed as an unplanned extension for classic lores/hires rendering and mixed mode. This was originally labeled Phase 7 in code, but has been renamed to avoid conflict with the real Phase 7.
- Phase 7: completed for MVP ADB, keyboard, and mouse register behavior. Deeper firmware-accurate ADB timing and device negotiation can be expanded later.
- Phase 8: completed for raw block devices, 2IMG parsing, and SmartPort status/read/write/format parameter-block execution.
- Phase 9: completed for MVP IWM latches, 5.25 drive stepping, raw/NIB/WOZ media containers, write-protect status, raw track mutation, and minimal 3.5 mode control.
- Phase 10: completed for deterministic speaker toggle capture, Ensoniq DOC RAM/register access, delayed reads, oscillator stop IRQs, and framework-owned sample buffers.
- Phase 11: completed for ROM load/reset entry points, deterministic step/run results, breakpoint and cycle-budget stops, no-media smoke coverage, and storage mount API coverage.
- Phase 12: completed for debugger command parsing/session APIs, register/memory/step/run/breakpoint commands, binary loading, and the standalone `IIGSDebuggerCLI` target.
- Phase 13: completed for first-pass spec audit, CLI runtime tests, script-based command execution, ROM01 CLI smoke coverage, and subsystem status marking.
- Phase 14: completed for a separate macOS SwiftUI debugger app target built on `IIGSCore.framework`, with ROM/binary load, stepping/running, registers, memory dump, breakpoints, command log, shared scheme, and project-local run action.
- Phase 15: completed for deterministic scheduler ownership, video cadence events, VBL interrupt routing, same-cycle ordering, CPU IRQ-line aggregation, speed-mode state, and initial paddle/DOC/disk event hooks.
- Phase 16: completed for a full implementation-plan review and second gap map after Phases 14 and 15.
- Phase 17: completed for debugger assertions, scriptable runtime state checks, scheduler event visibility, run-to-PC, raw/2IMG SmartPort image mounting commands, and CLI/runtime tests.
- Phase 18: completed as a first core correctness pass for `$C023/$C032` interrupt state, scanline/one-second scheduler IRQ routing, deterministic paddle timer reads, and runtime harness coverage.
- Phase 19: completed as a first debugger quality pass with core disassembly APIs, CLI disassembly/register editing, macOS disassembly and inspector panels, and tests.

## Phase 13 Audit Snapshot

This first audit pass compares the implemented phases against `IIGS-Spec/01-System-Overview.md` through `IIGS-Spec/16-Test-Cases.md`. It is intentionally conservative: a subsystem is `MVP` only when its implemented contract is narrow and well covered; otherwise it remains `partial` until ROM booting, timing, and broader compatibility tests prove it out.

| Subsystem | Status | Notes |
| --- | --- | --- |
| Project/package foundation | MVP | Framework and tests build for macOS, and the framework builds for generic iOS. `IIGSCore.framework` remains presentation-neutral. |
| 65C816 CPU | partial | Programmer-visible state, many core opcodes, decimal arithmetic, interrupts, block move MVP, and reset behavior are covered. Remaining risk: every documented opcode/addressing mode, exact dummy reads, read-modify-write I/O bus sequences, optional emulation-mode `JMP ($xxFF)` compatibility behavior, and fuller cycle classes. |
| Memory and ROM mapping | partial | ROM01/ROM03 placement, reset vector mapping, banked memory, language-card MVP, and shadowing paths are covered. Remaining risk: absent-RAM/open-bus behavior, full installed-RAM sizing behavior, Cx/C8 slot ROM windows, and exact language-card side effects under unusual access sequences. |
| Soft switches and Apple II compatibility bus | partial | Keyboard strobe, main/aux switching, `ALTZP`, video latches, `$C035`, `$C036`, and `$C068` have tests. Remaining risk: floating bus values, paddles, annunciators, slot ROM switching, scanline/one-second interrupt registers, and read/write side effects for less common switches. |
| Timing and event scheduler | needs correction | Video counters and cycle accounting exist, but the original Phase 5 event scheduler is not complete. Needed: one master event queue, fast/slow CPU timing semantics, VBL/scanline/paddle/DOC/disk event ordering, and deterministic same-cycle priorities. |
| Video | partial | Text, lores, hires, mixed mode, SHR 320/640/fill rendering, palette behavior, and timing-visible registers have focused tests. Remaining risk: double-hires ordering, artifact color, mid-line mode changes, floating-bus video fetches, richer golden-frame coverage, and border timing. |
| Input / ADB | partial | Apple II keyboard compatibility and ADB keyboard/mouse MVP behavior are tested, including ROM01/ROM03 revision differences. Remaining risk: fuller ADB command set, firmware-accurate controller state timing, special key mappings, low-memory mouse contracts, and interrupt edge cases. |
| Storage / SmartPort / IWM | partial | Raw block media, 2IMG, SmartPort MVP commands, IWM latches, 5.25 stepping, basic raw/NIB/WOZ containers, write-protect, and 3.5 control MVP are tested. Remaining risk: slot firmware boot path, GCR sector encoding, WOZ CRC/writeback semantics, raw bit timing, disk-switched status, and partition/container support. |
| Sound / Ensoniq DOC | partial | Speaker toggles, DOC RAM/register access, delayed reads, oscillator stop IRQ queue, and deterministic sample buffers are tested. Remaining risk: full oscillator modes, scan-rate-derived timing, sync/swap behavior, decay model, and integration with the central event scheduler. |
| ROM boot harness | partial | ROM load/reset, deterministic step/run, cycle-budget stops, breakpoint stops, storage mount APIs, no-media smoke coverage, and local ROM01 reset are covered. Remaining risk: running ROM startup deeper, slot 5/6/7 boot selection through firmware-visible hardware, ROM03 fixture coverage, and self-test/diagnostic paths. |
| Debugger CLI/runtime harness | MVP | Parser/session APIs, CLI help, binary loading, reset-vector patching, stepping, register/memory inspection, breakpoints, script execution, invalid command errors, and local ROM01 reset smoke are covered by XCTest. |

## Phase 16 Audit Snapshot

This second audit pass reviews the post-Phase-15 codebase against `IIGS-Spec/01-System-Overview.md` through `IIGS-Spec/16-Test-Cases.md`. It does not demote the value of the MVP work already done; it marks the places where the current implementation is still too happy-path for ROM booting, GS/OS, timing-sensitive software, or debugger-driven conformance.

| Subsystem | Status | Phase 16 Gap Map |
| --- | --- | --- |
| Project/package foundation | MVP | The framework/test/app/CLI targets build cleanly and `IIGSCore.framework` remains platform-neutral. Keep this stable while adding more fixtures and generated test data. |
| 65C816 CPU | partial | The opcode switch covers all 256 opcodes and core register/stack/decimal/interruption behavior has tests. Missing hardening: independent opcode matrix fixtures, exact cycle classes, dummy reads, read-modify-write bus sequences, page/bank wrap edge cases, interrupt recognition after `CLI`/`PLP`/`RTI`, `WAI` edge cases, and compatibility checks against documented 65C816 behavior. |
| Memory and ROM mapping | partial | ROM01/ROM03 mapping, banked memory, language-card MVP, aux memory, and shadow writes exist. Missing hardening: installed RAM sizing model, absent-RAM/open-bus behavior, `$E0/$E1` I/O visibility rules, Cx/C8 slot ROM windows, `INTCXROM`/`INTC8ROM` details, ROMBANK behavior, and more language-card access-sequence tests. |
| Soft switches and Apple II compatibility bus | partial | Keyboard, aux RAM switches, `ALTZP`, classic video switches, `$C035`, `$C036`, `$C041/$C046/$C047`, `$C068`, DOC, ADB, and IWM ranges have modeled entry points. Missing hardening: floating-bus values, paddles/annunciators, `$C023` scanline/second interrupts, `$C032`, full `$C011..$C01F` status matrix, slot register side effects, and exact read/write behavior for rarely used switches. |
| Timing and scheduler | partial | A central deterministic scheduler now owns video cadence events, VBL interrupt routing, same-cycle ordering, and paddle/DOC/disk event hooks. Missing hardening: effective slow/fast CPU throughput, slow memory/I/O wait states, scanline IRQs, quarter/one-second events, DOC rescheduling on register changes, IWM motor/media delays, SCC/clock events, and event-driven run-until semantics. |
| Interrupt aggregation | partial | CPU IRQ line aggregation now includes IIgs interrupt state, ADB, and DOC pending state. Missing hardening: `$C023` sources, SCC, expansion-card IRQs, exact VBL latch transformations, DOC clear semantics through the bus, IRQ deassertion after masking, and NMI/ABORT device paths. |
| Video | partial | Classic text, lores, hires, mixed mode, SHR 320/640/fill, palette reads, and frame-owned pixel buffers exist. Missing hardening: real glyph shapes, 80-column/double-hires memory ordering, artifact color, border/display fetch timing, mid-line soft-switch effects, floating-bus video fetches, scanline IRQ interaction, and broader golden-frame hashes. |
| Input / ADB | partial | Apple II keyboard strobe and ADB keyboard/mouse MVP behavior are modeled, including ROM01/ROM03 revision values and basic interrupt gating. Missing hardening: fuller ADB command set, address negotiation/collision behavior, controller timing states, keymap translation, low-memory mouse firmware contracts, mode/config behavior, and interrupt edge cases during queued packets. |
| Storage / SmartPort | partial | Raw block media, 2IMG, unit status, read/write/format, write-protect, and direct firmware-entry helper APIs exist. Missing hardening: actual slot firmware bytes/entry execution, ProDOS global command path, extended status/control behavior, disk-switched transient status, partition/container metadata, and ROM-visible boot selection. |
| Storage / IWM and floppy media | partial | IWM latches, phase stepping, motor/drive select, write-protect, raw/NIB/WOZ containers, raw track reads/writes, and 3.5 control MVP exist. Missing hardening: GCR encode/decode, bit-cell timing, WOZ CRC/writeback semantics, 3.5 drive protocol depth, motor-off delay, disk-switched status, and copy-protection-sensitive timing. |
| Sound / Ensoniq DOC | partial | Speaker toggles, DOC RAM/register access, delayed reads, oscillator sample stepping, stop-on-zero IRQ queue, and deterministic sample buffers exist. Missing hardening: frequency-derived oscillator timing, wave-size behavior, swap/sync/free-run modes, volume/envelope accuracy, scheduler integration for oscillator completion, and mixed speaker/DOC timing. |
| ROM boot harness | partial | ROM load/reset, no-media smoke, breakpoints, cycle budgets, and storage mount APIs exist. Missing hardening: deeper ROM01 execution checkpoints, ROM03 smoke fixture, slot 5/6/7 firmware-visible boot paths, diagnostic/self-test paths, and runtime assertions for hardware-visible state during ROM startup. |
| Debugger CLI | MVP | Commands cover help/reset/registers/step/run/cycles/breakpoints/memory/set plus script execution and CLI tests. Missing hardening: assert commands, disassembly, event/IRQ inspection, trace controls, media mount commands, ROM startup scripts, and clearer machine-readable output for XCTest. |
| macOS debugger app | MVP | The app can load ROM/binaries, step/run, show registers/status/timing/mouse, display banked memory, manage breakpoints, and show command logs. Missing hardening: disassembly, editable registers/memory, watchpoints, event/IRQ panels, media management, better pause/run loop behavior, and UI smoke automation. |
| SCC serial, clock, and parameter RAM | missing | Specs identify SCC, clock, and PRAM as IIgs-visible hardware, but there is no implementation yet. These are not first in line unless ROM startup proves they block progress, but they need explicit phases before compatibility work is considered broad. |

Phase 16 priority conclusion:

1. Build a stronger runtime conformance harness before adding more large devices.
2. Use that harness to run ROM01 and small binaries to named checkpoints with assertions.
3. Fix CPU, memory, soft-switch, and interrupt gaps first because every later subsystem depends on those contracts.
4. Improve the GUI debugger after the runtime harness tells us which inspection workflows are most useful.

## Phase 0: Project Foundation

- Create `IIGSCore.xcodeproj`.
- Add `IIGSCore.framework` as a pure Swift multiplatform framework target.
- Add `IIGSCoreTests` with XCTest.
- Add a tiny CLI/debug target later, but keep it outside the framework.
- Core rule: no AppKit, UIKit, SwiftUI, CoreAudio, Metal, or host presentation code in `IIGSCore`.

Proposed core modules:

- `CPU`
- `Bus`
- `Memory`
- `Machine`
- `Timing`
- `Video`
- `Audio`
- `Input`
- `Storage`
- `Debugger`

## Phase 1: 65C816 CPU MVP

Goal: execute small hand-authored machine-code programs from memory.

Implement:

- CPU registers: `A`, `X`, `Y`, `S`, `D`, `DBR`, `PBR`, `PC`, `P`, `E`.
- Reset behavior from `$00/FFFC`.
- Emulation/native mode invariants.
- Bus protocol: `read8`, `write8`, cycle accounting hooks.
- First opcode set:
  - `LDA`, `LDX`, `LDY`
  - `STA`, `STX`, `STY`
  - `TAX`, `TAY`, `TXA`, `TYA`
  - `INX`, `INY`, `DEX`, `DEY`
  - `CLC`, `SEC`, `REP`, `SEP`, `XCE`
  - `JMP`, `JSR`, `RTS`, `BRK`, `NOP`

Tests:

- Reset vector/state.
- `CLC; XCE` native transition.
- `REP/SEP` register-width truncation.
- Stack push/pop basics.
- Run sample assembly byte sequences and assert final registers/memory.

## Phase 2: Complete 65C816 Core

Goal: trustworthy CPU before ROM/device complexity.

Implement:

- All documented 65C816 opcodes.
- Addressing modes, long addressing, stack-relative, block moves.
- Decimal `ADC/SBC`.
- Interrupt entry/return: `IRQ`, `NMI`, `BRK`, `COP`, `RESET`, `ABORT`.
- Cycle classification and visible read/write bus sequences.

Tests:

- Per-opcode XCTest groups.
- Decimal arithmetic matrix.
- Native/emulation interrupt stack frames.
- `MVN/MVP`.
- Direct-page misalignment cycle penalty.
- Optional emulation-mode `JMP ($xxFF)` compatibility mode.

## Phase 3: Physical Memory and ROM Mapping

Goal: real 24-bit Apple IIgs memory behavior.

Implement:

- 16 MB address space abstraction.
- Installed RAM sizing without aliasing absent RAM.
- ROM 01 mapping into `$FE/$FF`.
- ROM 03 mapping into `$FC..$FF`.
- Bank `$00`, `$01`, `$E0`, `$E1` roles.
- Language-card area model.

Tests:

- ROM byte placement.
- Reset PC loaded through mapped ROM.
- Absent RAM behavior.
- Bank wrapping rules.
- Language-card bank/common-region behavior.

## Phase 4: Soft Switches and Apple II Compatibility Bus

Goal: make `$C000..$C0FF` side-effectful, not plain memory.

Implement:

- Keyboard strobe basics.
- `80STORE`, `RAMRD`, `RAMWRT`, `ALTZP`.
- Video soft switches `$C050..$C057`.
- Status reads `$C011..$C01F`.
- `$C035`, `$C036`, `$C068`.
- Floating-bus placeholder with deterministic testable behavior.

Tests:

- Main/aux read/write independence.
- `ALTZP` zero-page/stack remapping.
- Video latch status reads.
- Language-card prewrite sequence.
- Shadow inhibit writes.

## Phase 5: Timing and Event Scheduler

Goal: every subsystem advances from one emulated time base.

Implement:

- Master cycle counter.
- Slow/fast CPU speed via `$C036`.
- 262 scan lines, 65 cycles per line, 17030 cycles per frame.
- Event queue for VBL, scanline, paddles, DOC, disk later.
- Interrupt aggregation.

Tests:

- Frame/line cadence.
- `$C019`, `$C02E`, `$C02F` counter behavior.
- IRQ taken after `CLI`.
- Multiple same-cycle events handled deterministically.

## Phase 6: Video Model

Goal: render to framework-owned pixel buffers, no UI.

Implement:

- Text page rendering.
- Hires address mapping.
- 80-column/double-hires memory ordering.
- SHR framebuffer from `$E1/2000..$E1/9FFF`.
- Palette and SCB handling.

Tests:

- Text memory to glyph/pixel buffer.
- Hires interleaved scanline mapping.
- SHR 320/640/fill mode pixel tests.
- Golden pixel hashes for tiny deterministic frames.

## Phase 6.5: Classic Video Extension

Goal: preserve the extra classic video work that was accidentally labeled Phase 7.

Implemented:

- Classic lores rendering from text-page nibbles.
- Classic hires address mapping and bit rendering.
- Page 1/page 2 graphics selection.
- Mixed-mode bottom text rows over classic graphics.

## Phase 7: ADB, Keyboard, Mouse

Goal: enough firmware-visible input behavior for ROM probing and basic interaction.

Implement:

- `$C000/$C010` Apple II keyboard compatibility.
- `$C024..$C027` ADB controller state machine.
- Keyboard and mouse event queues.
- ROM 01/ROM 03 ADB revision behavior.

Tests:

- Inject key, read strobe, clear strobe.
- ADB version command.
- Enable data IRQ and consume response.
- Mouse movement/button packet.

## Phase 8: Storage MVP

Goal: bootable block media first.

Implement:

- Raw sector/block image abstraction.
- 2IMG parser.
- SmartPort slot 7 firmware entry behavior.
- Read/write/status/format minimal commands.
- 512-byte block transfer across 16/24-bit memory.

Tests:

- Mount 800 KB/32 MB images.
- SmartPort status/read/write.
- Write-protect errors.
- Unsupported command errors.

## Phase 9: IWM and Disk II

Goal: floppy behavior after block boot path exists.

Implement:

- `$C0E0..$C0EF` IWM latches.
- 5.25 phase stepping and motor/drive select.
- Raw 140 KB sector media.
- WOZ/NIB parsing later in the phase.
- 3.5 inch mode after 5.25 basics.

Tests:

- Phase stepping.
- Write-protect status.
- Read standard track/sector.
- WOZ track map parsing.

## Phase 10: Sound / Ensoniq DOC

Goal: deterministic audio engine, not host playback.

Implement:

- `$C030` speaker toggle stream.
- `$C03C..$C03F` DOC access.
- DOC RAM/register mode.
- Delayed read behavior.
- Oscillator stepping and IRQ queue.
- Mixer returns sample buffers to host.

Tests:

- Speaker toggle timing.
- DOC auto-increment RAM writes.
- Delayed reads.
- Oscillator stop-on-zero IRQ behavior.

## Phase 11: ROM Boot Harness

Goal: run ROM 01/03 far enough to prove hardware contracts.

Implement:

- `IIGSMachine` orchestration.
- Cold/warm reset.
- ROM load API.
- Media mount API.
- Deterministic run loop: step instruction, run cycles, run until breakpoint/event.

Tests:

- ROM reset vector.
- ROM 01/03 startup smoke tests.
- No-media boot path does not crash.
- Slot 5/6/7 boot-selection smoke tests.

## Phase 12: Debugger MVP

Goal: make the core pleasant to inspect.

Start with CLI:

- Load ROM.
- Load binary at address.
- Step CPU.
- Run until PC/breakpoint.
- Dump registers.
- Read/write memory.
- Trace bus accesses optionally.

## Phase 13: Spec Audit, Runtime Harness, and Test Hardening

Goal: make the existing core less happy-path before expanding outward.

Implement:

- Re-read local specs and references against Phases 1-12.
- Mark each subsystem as `MVP`, `partial`, or `needs correction`.
- Add missing edge-case tests around CPU flags/addressing, memory mapping, soft switches, timing, ROM reset paths, SmartPort/IWM, DOC, and debugger commands.
- Add small conformance notes in tests where behavior comes directly from the specs.
- Update `IMPLEMENTATION_PLAN.md` with any revised or split phases.
- Add CLI end-to-end tests for `IIGSDebuggerCLI`.
- Add script-based debugger fixtures for small machine-code programs.
- Add runtime tests that load binaries, patch reset vectors, reset, step, run, inspect registers, inspect memory, and stop at breakpoints.
- Add ROM01 runtime smoke tests through the CLI when the local legal ROM is present.

Tests:

- `IIGSDebuggerCLI --help` succeeds.
- `IIGSDebuggerCLI --command help` succeeds.
- Load a tiny binary at `$008000`, patch reset vector, reset, step, and assert register output.
- Set a breakpoint, run, and assert execution stops before that address.
- Write memory with `set`, read it with `mem`, and assert round trip output.
- Run debugger commands from a script file.
- Invalid CLI commands return nonzero with useful error text.
- ROM01 reset reports the expected PC when `LocalAssets/ROMs/Apple_IIGS_ROM01.bin` is present.
- Existing macOS XCTest suite and generic iOS framework build continue to pass.

## Phase 14: macOS Debugger App MVP and Inspector Expansion

Goal: add a basic native debugger host, then expand it into a useful inspection surface without putting presentation code into `IIGSCore.framework`.

Implement:

- Add a separate macOS app target, likely `IIGSDebugger`.
- Use `IIGSDebuggerSession` as the app-facing debugging model.
- Add structured debugger snapshot APIs for registers, flags, status lines, counters, input state, and memory rows.
- ROM load flow.
- Binary load flow.
- Register panel with fixed fields for `PC`, `PBR`, `S`, `D`, `DBR`, `A`, `X`, and `Y`.
- Flag panel for `N`, `V`, `M`, `X`, `D`, `I`, `Z`, and `C`.
- Status panel for `RDY`, `IRQ`, `NMI`, `E`, stopped, and waiting state where available.
- Runtime counter panel for emulated cycles, approximate emulator refresh cadence, approximate UI refresh cadence, and elapsed time since reset/power.
- Mouse panel showing host coordinates over the debugger display area and ROM-visible mouse coordinates.
- Banked memory viewer with bank entry `00...FF`, rows showing full 24-bit address, 16 bytes, and printable ASCII.
- Memory viewer scrolling through offsets `$0000...$FFFF`; bank `$FF` should end on row `FFFFF0`.
- Step button.
- Run-until-breakpoint button.
- Breakpoint add/remove/list UI.
- Output/log pane showing debugger command results.
- Optional command input field that accepts the same commands as the CLI.
- Pause/snapshot behavior so register and memory panels can hold a stable state while execution is stopped.

Tests:

- macOS app target builds.
- Core debugger APIs remain covered by unit tests.
- CLI runtime tests remain the end-to-end command oracle.
- Banked memory row formatting, printable ASCII fallback, bank bounds, and final-row address math.
- Structured debugger snapshots report CPU registers, flags, status, cycle counters, and ADB mouse state.
- Minimal UI smoke tests can be added once the app has stable controls.

Boundary:

- `IIGSCore.framework` still gets no AppKit, SwiftUI, UIKit, CoreAudio, Metal, or presentation code.
- The macOS app is only a host/debugger shell around the framework.

## Phase 15: Timing/Event Scheduler Revisit

Goal: replace the partial timing work with one coherent emulated time base shared by CPU, video, input, sound, storage, and interrupts.

Status: completed as a scheduler foundation. Detailed scanline IRQ register semantics, fully analog paddle timing, DOC oscillator rescheduling, disk rotational timing, SCC events, and clock events remain future hardening work.

Implement:

- Create a central deterministic event scheduler owned by the machine layer.
- Model slow/fast CPU speed through `$C036` without resetting absolute emulated time.
- Preserve the 262-line, 65-cycle, 17030-cycle video cadence as scheduled events.
- Route VBL, scanline, paddle, DOC, disk, and future SCC/clock events through one priority order.
- Aggregate interrupt sources from device state instead of ad hoc polling.
- Define same-cycle event ordering and make it testable.
- Keep host wall-clock throttling out of `IIGSCore`; hosts can throttle outside the framework later.

Tests:

- Frame and scanline cadence from the master scheduler.
- `$C019`, `$C02E`, and `$C02F` at boundary cycles.
- Slow/fast `$C036` switching preserves monotonic event time.
- IRQ is taken at the next instruction boundary after an enabled event source asserts.
- Multiple same-cycle events are serviced deterministically.
- Paddle timeout and DOC oscillator completion are driven by scheduler time, not host time.

## Phase 16: Full Core Audit and Gap Map

Goal: review the whole implementation after the first debugger and scheduler passes, then turn the remaining unknowns into an explicit roadmap.

Status: completed. See `Phase 16 Audit Snapshot` above.

Implement:

- Re-read the current plan against the local specs and implemented source/tests.
- Classify every subsystem as `MVP`, `partial`, `needs correction`, or `missing`.
- Identify boot-critical gaps separately from polish/debugger gaps.
- Add Phases 17, 18, and 19 to keep the next work ordered.
- Preserve the rule that `IIGSCore.framework` remains host-platform neutral.

Tests:

- No new emulator behavior is required in this phase.
- Run the existing macOS XCTest suite after plan edits to make sure the audit did not disturb project files.
- Build the generic iOS framework if project files change.

## Phase 17: Runtime Conformance Harness Expansion

Goal: make `IIGSDebuggerCLI` a stronger scriptable test runner for emulator runtime behavior.

Status: completed as the first runtime conformance harness expansion. The CLI can now assert CPU/memory/flag/status/cycle state, print structured snapshots, inspect scheduler events, schedule device events, run until a PC, and mount raw/2IMG SmartPort block images. Future harness work can add disassembly, richer trace streams, floppy mounting commands, and deeper ROM checkpoint scripts.

Implement:

- Add debugger script assertions for registers, flags, memory bytes/ranges, PC, cycle counts, soft-switch state, interrupt state, and scheduler state.
- Add commands to load ROMs, load binaries, mount block/floppy media fixtures, and run until PC, breakpoint, cycle, event, or named stop reason.
- Add machine-readable command output mode for XCTest-friendly parsing.
- Add trace controls for CPU steps, bus reads/writes, interrupt changes, and scheduled events.
- Add fixture scripts for tiny binaries that exercise CPU/memory/soft-switch/timing behavior.
- Add ROM01 startup scripts that run to conservative checkpoints when the local legal ROM fixture exists.
- Keep CLI behavior deterministic and independent of host wall-clock timing.

Tests:

- Assertion pass/fail commands return useful output and exit status.
- Runtime scripts can validate register, memory, flag, soft-switch, and scheduler state.
- ROM01 fixture smoke can run to multiple named checkpoints without crashing when the local ROM is present.
- Invalid assertions fail clearly.
- Existing CLI commands remain backward compatible.

## Phase 18: Core Correctness Pass 1

Goal: fix the highest-risk core gaps revealed by Phase 16 and exercised by Phase 17 before adding more debugger polish.

Status: completed as a first correctness slice. This pass adds observable `$C023/$C032` interrupt behavior, scheduler-driven scanline and one-second interrupt pending state, deterministic `$C064..$C067/$C070` paddle timing, and CLI runtime assertions that exercise the new soft-switch/interrupt behavior. CPU opcode conformance, slot ROM windows, floating bus, full scanline IRQ programming, SCC/clock/PRAM, disk timing, and deeper ROM startup checkpoints remain future correctness work.

Implement:

- CPU conformance pass for opcode/addressing/flag/cycle edge cases that block runtime scripts.
- Memory-map pass for installed RAM sizing, absent-RAM/open-bus behavior, slot ROM windows, and `$E0/$E1` I/O visibility.
- Soft-switch pass for `$C023`, `$C032`, paddles, floating bus, slot register side effects, and less common `$C000..$C0FF` behavior.
- Interrupt pass for scanline, quarter/one-second, DOC clear, ADB masking, and IRQ deassertion.
- Timing pass for effective slow/fast throughput and wait-state visible behavior where tests can observe it.
- ROM boot pass that advances ROM01 farther through startup checkpoints.

Tests:

- CPU opcode/addressing fixtures for edge cases from `IIGS-Spec/16-Test-Cases.md`.
- Runtime conformance scripts for memory mapping, soft switches, interrupts, and scheduler events.
- ROM01 checkpoint tests with local legal ROM fixture.
- Regression tests for every corrected bug found during the pass.

## Phase 19: Debugger Quality Pass

Goal: improve the macOS debugger after Phase 17 and 18 clarify which inspection tools are needed most.

Status: completed as a first quality pass. This adds framework-neutral disassembly/decode APIs, CLI `disasm` and `setreg` commands, editable macOS register/memory controls, a disassembly panel, and lightweight interrupt/scheduler inspector data in debugger snapshots. Future debugger passes can broaden opcode formatting coverage, add watchpoints, media-mount controls, device-specific inspector panes, and exportable trace streams.

Implement:

- Add a disassembly panel backed by framework-neutral decode APIs.
- Add editable register and memory controls with validation.
- Add watchpoints and richer breakpoint management.
- Add event scheduler, IRQ source, soft-switch, ADB, DOC, SmartPort, and IWM inspector panels.
- Add media mounting controls for ROM, raw/2IMG block images, and floppy image fixtures.
- Improve pause/resume/run-loop behavior so snapshots are stable during inspection.
- Add exportable traces for CPU, bus, interrupt, and device events.

Tests:

- Core decode/format APIs are covered by unit tests.
- Debugger snapshot APIs expose all new inspector data without importing AppKit/SwiftUI into `IIGSCore`.
- macOS app target builds.
- CLI conformance tests remain the oracle for debugger command behavior.

## Definition of Done Per Phase

- Implementation is covered by focused XCTest cases.
- Public APIs remain platform-neutral.
- Hardware behavior is modeled through bus/register effects, not host shortcuts.
- Specs in `IIGS-Spec` are linked in test names/comments where helpful.
- No emulator source-code references are used.
