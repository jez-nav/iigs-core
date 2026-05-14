# Apple IIGS Emulator Specification: Image Formats

## Feature: Raw sector images

**Expected behavior:** Support raw sector images for 5.25 inch, 3.5 inch, and SmartPort media. A 140 KB image is a 5.25 inch disk with 35 tracks * 16 sectors * 256 bytes. An 800 KB image is a 3.5 inch disk with 1600 512-byte blocks. SmartPort images are linear 512-byte block devices.

**Registers affected:** Disk controller state only through media contents; no CPU registers during mount except firmware-visible status.

**Memory addresses involved:** Media backing store; IWM nibblization buffers; SmartPort block buffers.

**Edge cases:** `.dsk` and `.po` extensions are not reliable by themselves. DOS 3.3 sector order and ProDOS sector order must be selectable or detected. Slot 6 defaults to 140 KB 5.25; slot 5 defaults to 800 KB 3.5; slot 7 defaults to block-device media.

**Known compatibility notes:** If low-level writes make a raw sector image nonstandard, the emulator should preserve the new low-level representation using a nibble-capable format rather than forcing it back to sectors.

**Test cases:**

- Mount 143360-byte image in slot 6. Expected: 5.25 sector media.
- Mount 819200-byte image in slot 5. Expected: 3.5 800 KB media.
- Mount 32 MB image in slot 7. Expected: SmartPort block count 65536, or capped to ProDOS-compatible 65535 when creating ProDOS volumes.

**References:**

- Beneath Apple DOS.
- Beneath Apple ProDOS.
- ProDOS 8 Technical Reference Manual.

## Feature: 2IMG

**Expected behavior:** Parse 2IMG headers with magic `"2IMG"`, creator/type fields, flags, data offset, and data length. Honor write-protect flag. Honor DOS-sector-order vs ProDOS-order image type. Use data offset and length rather than assuming image payload begins immediately after the header.

**Registers affected:** Media write-protect and image type metadata.

**Memory addresses involved:** 2IMG header bytes and image data payload.

**Edge cases:** Some historical images store payload length with byte-order mistakes; tolerate known reversed 800 KB length when safely detectable. Some 2IMG DOS images include a DOS volume number flag; preserve it for DOS 3.3 address fields.

**Known compatibility notes:** Incorrect sector-order handling boots some ProDOS images but breaks DOS 3.3 images and vice versa.

**Test cases:**

- Parse 2IMG with DOS-order type. Expected: 5.25 decoder uses DOS logical sector order.
- Parse write-protected 2IMG. Expected: media status reports write protect.
- Parse 2IMG with non-512 payload offset. Expected: reads begin at declared payload.

**References:**

- 2IMG disk image format documentation.

## Feature: WOZ and nibble images

**Expected behavior:** Support WOZ1 and WOZ2 images with header, CRC, INFO, TMAP, TRKS, and optional META chunks. Track maps can contain absent tracks and repeated quarter-track entries. Preserve raw bit streams and track bit counts. NIB images should be treated as raw 5.25 nibble tracks, typically 0x1A00 bytes per track, without WOZ timing metadata.

**Registers affected:** IWM media state, write-protect status, dirty/modified media state.

**Memory addresses involved:** WOZ chunks; IWM raw bit-track representation.

**Edge cases:** WOZ TMAP repeats can represent half/quarter-track readability and should not create duplicate writable tracks unless intended. CRC should be verified and rewritten after media mutation. Empty/absent tracks should read as no-data or floating media behavior rather than crashing.

**Known compatibility notes:** Copy-protected software depends on WOZ timing and sync preservation. NIB lacks enough timing metadata for all protections but should support common nibble images.

**Test cases:**

- Open WOZ2 with valid CRC. Expected: INFO/TMAP/TRKS parsed and tracks available.
- Modify a writable WOZ track. Expected: track data changes and CRC updates.
- Mount NIB and read address prolog bytes. Expected: raw nibble stream is visible through IWM.

**References:**

- Applesauce WOZ Reference 1.0/2.0.

## Feature: Containers and partitions

**Expected behavior:** Support compressed or archived images when practical: gzip, zip entries, and NuFX/ShrinkIt disk archives. Support partitioned devices by presenting selectable embedded ProDOS/HFS/Apple partition entries and mapping the selected partition as the emulated media range.

**Registers affected:** Media write-through/write-protect metadata.

**Memory addresses involved:** Container headers, selected partition offset, selected partition length.

**Edge cases:** Compressed images loaded into memory may be read-only unless explicit write-back support exists. Zip files may contain multiple candidate images; selection should be deterministic and visible to the user. Partition offsets and lengths must be bounds-checked before media I/O.

**Known compatibility notes:** CD-ROM and hard-drive images can contain partition maps; GS/OS expects the mounted partition's block 0 to be the ProDOS/HFS volume block, not the host container's block 0 unless whole-device mode is selected.

**Test cases:**

- Mount gzip-compressed 140 KB image. Expected: decompressed media boots read-only or with documented write policy.
- Mount zip with multiple images. Expected: chosen entry's size/type determines slot behavior.
- Mount partition 2 of a larger image. Expected: block 0 reads from partition start offset.

**References:**

- gzip RFC 1952.
- ZIP AppNote.
- NuFX/ShrinkIt file format notes.
- Apple Partition Map documentation.
