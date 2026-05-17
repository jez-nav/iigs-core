# Apple IIGS Memory Map

Below is a practical Apple IIGS memory map from a programmer/emulator-writer perspective.

This separates the **logical 65816 address space** from the Apple II compatibility I/O holes, video memory behavior, ROM areas, and expansion RAM.

---

## Big Picture: 65816 Address Space

The Apple IIGS uses the **65C816 / 65816**, so addresses are **24-bit**:

```text
Bank / Offset

$00/0000 through $FF/FFFF
```

That gives a theoretical 16 MB address space:

```text
256 banks × 64 KB = 16 MB
```

But the IIGS does **not** treat all banks as plain RAM. Some banks are special:

- Apple II compatibility memory
- I/O space
- ROM
- Video shadowing
- Expansion RAM

---

## Simplified Apple IIGS Memory Map

```text
Bank(s)        General role
-------        ------------
$00            Main Apple II-compatible bank
$01            Auxiliary Apple II-compatible bank
$02-$7F        Expansion / fast RAM, when installed
$80-$DF        Usually unmapped or expansion-dependent
$E0            Mega II slow RAM mirror of bank $00 / video area
$E1            Mega II slow RAM mirror of bank $01 / video area
$E2-$EF        Usually not normal RAM on stock machines
$F0-$FF        ROM / firmware area, depending on ROM version
```

The most important banks for normal software are:

```text
$00, $01, $02-$7F, $E0, $E1, $F0-$FF
```

Banks `$00` and `$01` preserve Apple II / IIe compatibility behavior.

Banks `$E0` and `$E1` contain the “slow RAM” side used by the Mega II compatibility hardware and real video memory behavior. The IIGS can shadow writes from banks `$00/$01` into `$E0/$E1` for display-related regions.

---

## Bank `$00`: Main Apple II Compatibility Bank

```text
$00/0000-$00/00FF    Zero page
$00/0100-$00/01FF    Stack
$00/0200-$00/03FF    System / monitor / vectors / scratch areas
$00/0400-$00/07FF    Text page 1
$00/0800-$00/1FFF    General RAM / program area
$00/2000-$00/3FFF    Hi-res graphics page 1
$00/4000-$00/5FFF    Hi-res graphics page 2
$00/6000-$00/BFFF    General RAM, depending on OS/use
$00/C000-$00/CFFF    I/O space, soft switches, firmware entry points
$00/D000-$00/FFFF    ROM or language-card bank-switched RAM
```

This is the classic Apple II-style 64 KB map.

The key pain point is:

```text
$C000-$CFFF is not normal RAM.
```

That area contains hardware registers, soft switches, slot firmware windows, and system control locations.

---

## Bank `$01`: Auxiliary Memory Bank

```text
$01/0000-$01/01FF    Aux zero page / aux stack area
$01/0400-$01/07FF    80-column text / auxiliary text memory
$01/2000-$01/9FFF    Super Hi-Res graphics memory area
$01/C000-$01/CFFF    I/O space mirror / compatibility behavior
$01/D000-$01/FFFF    Auxiliary language-card style area
```

Bank `$01` is heavily tied to Apple IIe auxiliary-memory compatibility and IIGS graphics.

The **Super Hi-Res screen buffer** is commonly associated with:

```text
$01/2000-$01/9FFF
```

But hardware display behavior is more subtle: the actual slow video memory lives in the Mega II slow RAM area, particularly banks `$E0` and `$E1`, and the system can shadow writes there.

---

## Banks `$02-$7F`: Fast Expansion RAM

```text
$02/0000-$7F/FFFF    Fast RAM / expansion RAM
```

This is the cleanest region for large 16-bit IIGS-native programs.

If you are writing a modern IIGS program, emulator, or memory manager, think of banks `$02+` as the “nice” linear-ish RAM area, assuming the machine has enough RAM installed.

Examples:

```text
$02/0000
$03/8000
$10/0000
$7F/FFFF
```

These are normal 65816 banked addresses, not Apple II-style weirdness.

---

## Banks `$E0` and `$E1`: Slow RAM / Mega II / Video Backing Memory

```text
$E0/0000-$E0/FFFF    Slow RAM corresponding broadly to bank $00
$E1/0000-$E1/FFFF    Slow RAM corresponding broadly to bank $01
```

These banks are extremely important for an emulator.

They are not merely “extra RAM.” They are tied to:

```text
Apple II compatibility
Mega II chip behavior
Video memory
Shadowing
1 MHz slow memory behavior
```

The IIGS has hardware shadowing so writes to certain areas in banks `$00` and `$01` can also update corresponding areas in `$E0` and `$E1`.

This lets software write to fast memory while the video hardware sees the correct slow-memory contents.

For emulator design, this means you should not treat `$00` and `$E0` as totally unrelated RAM if shadowing is enabled.

---

## Banks `$F0-$FF`: ROM / Firmware

```text
$F0/0000-$FF/FFFF    System ROM / firmware space
```

ROM layout depends on machine ROM version:

```text
ROM 00 / ROM 01    128 KB ROM
ROM 03             256 KB ROM
```

A ROM 03 machine has more firmware in ROM than ROM 00/01 machines.

For emulation, this means ROM mapping is version-dependent. Model ROM version explicitly rather than hardcoding one universal map.

---

## Important Special Region: `$C000-$CFFF`

This is the big one.

In bank `$00`:

```text
$00/C000-$00/CFFF
```

is the Apple II / IIGS I/O and firmware control area.

It includes things like:

```text
soft switches
keyboard access
speaker/bell access
display mode switches
slot firmware areas
disk/controller entry areas
Mega II / IIGS hardware registers
system control registers
```

This region is not ordinary RAM and should be decoded specially in an emulator.

Also, bank `$01/C000-$01/CFFF` has related compatibility behavior, so do not assume bank `$01` is purely normal RAM either.

---

## Programmer-Friendly Memory Model

For normal IIGS-native development, you can think like this:

```text
Bank $00       Dangerous but important compatibility bank
Bank $01       Aux/video/graphics-related compatibility bank
Banks $02+     Best place for clean native program/data memory
Banks $E0/E1   Slow/video/Mega II backing memory
Banks $F0+     ROM
```

For emulator development, think like this:

```text
Address range              Handling
-------------              --------
$00/0000-$00/BFFF          Main RAM, with special video/shadow considerations
$00/C000-$00/CFFF          I/O, soft switches, firmware window
$00/D000-$00/FFFF          ROM/language-card bank switching
$01/0000-$01/BFFF          Auxiliary RAM / graphics memory
$01/C000-$01/CFFF          I/O-like compatibility behavior
$01/D000-$01/FFFF          Aux language-card area
$02/0000-$7F/FFFF          Expansion RAM
$E0/0000-$E1/FFFF          Slow RAM / Mega II / video backing RAM
$F0/0000-$FF/FFFF          ROM, firmware
```

---

## Very Simplified Visual Map

```text
65816 24-bit address space

$00:0000 ┌─────────────────────────────┐
         │ Main Apple II-compatible RAM │
$00:BFFF ├─────────────────────────────┤
$00:C000 │ I/O / soft switches          │
$00:CFFF ├─────────────────────────────┤
$00:D000 │ ROM or bank-switched RAM     │
$00:FFFF └─────────────────────────────┘

$01:0000 ┌─────────────────────────────┐
         │ Auxiliary RAM                │
         │ Text / double-hires / SHR    │
$01:BFFF ├─────────────────────────────┤
$01:C000 │ I/O compatibility area       │
$01:CFFF ├─────────────────────────────┤
$01:D000 │ Aux language-card area       │
$01:FFFF └─────────────────────────────┘

$02:0000 ┌─────────────────────────────┐
         │ Fast expansion RAM           │
$7F:FFFF └─────────────────────────────┘

$E0:0000 ┌─────────────────────────────┐
         │ Slow RAM / Mega II / video   │
$E1:FFFF └─────────────────────────────┘

$F0:0000 ┌─────────────────────────────┐
         │ ROM / firmware               │
$FF:FFFF └─────────────────────────────┘
```

---

## Emulator Takeaway

For an Apple IIGS emulator, do not start with “16 MB flat RAM.”

Start with a **memory bus decoder**:

```text
read(bank, address)
write(bank, address, value)
```

Then route accesses based on:

```text
bank number
offset address
ROM version
shadowing state
language-card state
I/O soft switches
slot firmware mapping
speed/slow-memory behavior
```

A clean first-pass emulator memory model could be:

```text
mainRAM[64 KB]        // bank $00 visible RAM portions
auxRAM[64 KB]         // bank $01 visible RAM portions
expansionRAM[...]     // banks $02-$7F
slowRAM_E0[64 KB]
slowRAM_E1[64 KB]
rom[...]              // ROM 01 or ROM 03 image
ioRead/write handlers // $C000-$CFFF
```

Then refine `$C000-$CFFF`, shadowing, and language-card behavior as you implement more compatibility.

---

## Notes for Further Research

The simplified model above is suitable for orientation, course notes, and early emulator planning.

For a more accurate emulator, the next areas to document in detail are:

1. `$C000-$CFFF` soft switches and I/O decoding
2. Language-card bank switching
3. Shadowing rules between `$00/$01` and `$E0/$E1`
4. Super Hi-Res memory layout
5. ROM 01 vs ROM 03 mapping differences
6. Slot firmware and SmartPort behavior
7. Slow vs fast memory timing behavior
