# Apple IIGS Emulator Specification: ADB, Keyboard, and Mouse

## Feature: Apple II keyboard compatibility

**Expected behavior:** `$C000` returns the last Apple II character code with bit 7 set when the strobe is active. `$C010` clears the keyboard strobe. Modifier state is exposed through IIgs registers as well as through ADB commands. Repeated reads of `$C000` without `$C010` should keep returning the same strobed character.

**Registers affected:** Keyboard data/strobe latch, `$C025` modifier register, ADB interrupt/status registers.

**Memory addresses involved:** `$C000`, `$C010`, `$C025`, `$C026`, `$C027`.

**Edge cases:** Control characters, command/option keys, caps lock, keypad keys, and key-up/key-down events must map to Apple keycodes and ASCII consistently. Host key repeat should not create duplicate ADB key-downs if the emulated ADB controller supplies repeat behavior.

**Known compatibility notes:** Applesoft and old Apple II programs poll `$C000` constantly for Ctrl-C. Games may use both `$C000` and ADB commands in the same session.

**Test cases:**

- Inject `A`. Expected: `$C000` returns `$C1`; repeated reads stay `$C1`; `$C010` clears bit 7.
- Hold Control and press `C`. Expected: ASCII Ctrl-C appears and `$C025` control bit is set while held.

**References:**

- Apple IIGS Hardware Reference.
- Apple IIGS Firmware Reference.

## Feature: ADB controller registers

**Expected behavior:** Implement the IIgs ADB microcontroller interface at `$C024`..`$C027`. `$C026` is command/data. `$C027` is status/control. `$C025` reports modifiers. `$C024` returns mouse data/coordinates through the firmware-compatible path. The controller has idle, receiving-command, and sending-data phases. Commands can enqueue response bytes and assert data interrupts when enabled.

**Registers affected:** `$C024`, `$C025`, `$C026`, `$C027`; ADB mode byte; ADB configuration bytes; ADB RAM; keyboard and mouse device addresses.

**Memory addresses involved:** `$C024`, `$C025`, `$C026`, `$C027`; ADB RAM logical `$00`..`$FF`.

**Expected `$C027` bits:**

| Bit | Meaning |
| --- | --- |
| 7 | Mouse data available |
| 6 | Mouse interrupt enable/status control |
| 5 | Controller data valid |
| 4 | Controller data interrupt enable |
| 3 | Keyboard valid/SRQ |
| 2 | Keyboard interrupt enable |
| 1 | Mouse coordinate mode/status |
| 0 | Command full/busy |

**Edge cases:** Status bits for data valid, mouse data, keyboard valid, mouse coordinate, and command full are controller-generated; writes should only store writable control/interrupt-enable bits. Disabling data or mouse interrupts must clear the corresponding pending IRQ. ROM 01 expects controller revision 5; ROM 03 expects revision 6 or later.

**Known compatibility notes:** Some software uses ADB RAM reads for special key state. ROM 03 uses additional synchronization/configuration commands compared with ROM 01.

**Test cases:**

- Write command `$0D` to `$C026`. Expected: version byte response, revision depending on ROM generation.
- Enable data interrupt in `$C027`, issue read-modes command. Expected: `$C027` data-valid bit set and IRQ asserted until data is read from `$C026`.
- Write ADB RAM address/value via command `$08`, read via `$09`. Expected: same byte returned.

**References:**

- Apple IIGS Hardware Reference.
- Apple IIGS Firmware Reference.

## Feature: ADB device protocol

**Expected behavior:** Model at least a keyboard at ADB address 2 and mouse at address 3. Implement ADB talk register 0 for keyboard keycodes, talk/listen register 3 for device handler/address information, controller set/clear modes, set config, sync, read modes, read config, read available charsets/layouts, reset, and send-keycode commands.

**Registers affected:** ADB command byte, device register 0 and 3 values, controller mode/configuration, `$C027` valid/interrupt bits.

**Memory addresses involved:** `$C026`, `$C027`, `$C024`, ADB RAM.

**Edge cases:** ADB keycodes use bit 7 as key up/down indicator in common packet formats. Device address changes through listen register 3 should update the device address only when valid. Unknown devices should return no data rather than fabricating packets during firmware polling.

**Known compatibility notes:** Mouse movement is consumed both by ADB packets and by firmware-maintained low-memory cursor coordinates. Button transitions must not be lost when movement FIFO is full.

**Test cases:**

- Queue key down/up for keycode `$00`. Expected: keyboard talk register 0 returns the two events in order.
- Move mouse by `dx=5`, `dy=-3`, button down. Expected: mouse data valid, coordinates/button state returned through the mouse path, and mouse IRQ if enabled.
- Listen keyboard register 3 with a valid address. Expected: subsequent talk commands use the new address.

**References:**

- Apple Desktop Bus protocol documentation.
- Apple IIGS Hardware Reference.
