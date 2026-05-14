# Apple IIGS Emulator Specification: Disk II and IWM Floppy

## Feature: IWM switch interface

**Expected behavior:** Implement the Integrated Woz Machine at `$C0E0`..`$C0EF`. The low four addresses control phase lines 0..3 off/on in pairs, `$C0E8/$C0E9` control the IWM motor latch, `$C0EA/$C0EB` select drive 1/2, `$C0EC/$C0ED` control Q6, and `$C0EE/$C0EF` control Q7. With motor on and 5.25 mode selected, even-address reads return data/status according to Q6/Q7.

**Registers affected:** Phase latches, motor latch, drive select, Q6, Q7, IWM mode register, write latch, shift/read latch, write-protect status.

**Memory addresses involved:** `$C0E0`..`$C0EF`, `$C031` bit 6 for 3.5 select and bit 7 control input.

**Q6/Q7 behavior:**

| Q7 | Q6 | Read meaning | Write meaning |
| --- | --- | --- | --- |
| 0 | 0 | Data register | Data latch path |
| 0 | 1 | Status register | Mode/status path |
| 1 | 0 | Handshake register | Handshake path |
| 1 | 1 | Write path | Write data to disk when enabled |

**Edge cases:** Accessing any switch changes its latch before the data/status result is interpreted. Motor-off accesses use internal mode/status registers rather than rotating media data. 5.25 write operations must be cycle-accurate enough to place bits at the correct track position.

**Known compatibility notes:** Copy-protected disks and nibble copiers depend on raw bit timing, sync bytes, partial-shift-register reads, and write splice behavior. A fast path is acceptable only when accurate mode remains available.

**Test cases:**

- Turn motor on, select drive 1, Q6=0, Q7=0, read `$C0EC` repeatedly on a WOZ image. Expected: successive disk nibbles follow bit timing.
- Q6=1, Q7=0 with write-protected disk. Expected: status indicates write protect.
- Write in Q6=1,Q7=1 mode with motor on. Expected: modified raw track bits and dirty media state.

**References:**

- Apple IIGS Hardware Reference.
- Apple II Disk II documentation.
- WOZ disk image reference.

## Feature: 5.25 inch disk mechanics

**Expected behavior:** Represent a 5.25 inch disk as quarter tracks with raw bit streams. Phase line changes step the head inward/outward according to Disk II stepper behavior. Track data includes sync bits, address fields, data fields, and GCR 6-and-2 encoded sector payloads for standard DOS 3.3/ProDOS images, while WOZ/NIB images preserve raw nibble layout.

**Registers affected:** Phase latches, current head position, motor state, read/write latch.

**Memory addresses involved:** `$C0E0`..`$C0EF`; disk image backing store.

**Edge cases:** Tracks can be absent, weak, duplicated in quarter-track maps, or intentionally nonstandard. Reads during sync fields return bytes with high bit alignment only when sufficient one bits have shifted. Writes can alter sector structure so a formerly sector-ordered raw image must be treated as nibble/WOZ-like afterward.

**Known compatibility notes:** Standard 140 KB images use 35 tracks, 16 sectors, 256 bytes per sector. DOS 3.3 and ProDOS sector orders differ. NIB images usually store 0x1A00 bytes per track without full timing metadata.

**Test cases:**

- Mount a 140 KB DOS-order image and read track 0 sector 0 through firmware. Expected: sector data decoded correctly.
- Step phases through four half-track movements. Expected: current quarter-track updates in the correct direction and clamps at track 0.
- Write protect a disk and attempt a sector write. Expected: write-protect status and no media mutation.

**References:**

- Beneath Apple DOS.
- Beneath Apple ProDOS.
- WOZ disk image reference.

## Feature: 3.5 inch IWM mode

**Expected behavior:** `$C031` bit 6 selects 3.5 inch drive control. In this mode, phase lines plus `$C031` bit 7 form a controller command/status selector. Phase 3 assertion triggers commands such as stepping, motor on/off, and disk-eject status handling. Data timing is faster than 5.25 inch media and uses 800 KB two-sided disk layout.

**Registers affected:** `$C031`, phase latches, 3.5 motor state, side/track state, step direction, disk-switched/eject status.

**Memory addresses involved:** `$C031`, `$C0E0`..`$C0EF`.

**Edge cases:** The IWM motor latch `$C0E9` is not the actual 3.5 drive motor command. The 3.5 controller reports status bits selected by phase lines. Disk-switched status should remain set after eject/insert until cleared by the controller command.

**Known compatibility notes:** 800 KB images are 1600 ProDOS blocks. GS firmware expects the 3.5 drive to become ready quickly but with consistent status responses.

**Test cases:**

- Select 3.5 mode, issue motor-on command through phase/control sequence. Expected: 3.5 motor state becomes active.
- Read 800 KB boot block via slot 5 firmware. Expected: block 0 data loads correctly.
- Eject and reinsert media. Expected: disk-switched status reports change until cleared.

**References:**

- Apple IIGS Hardware Reference.
- Apple 3.5 Drive technical notes.
