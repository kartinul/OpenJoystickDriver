# #34: 8BitDo Ultimate 2C Wireless support

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/34
- **State:** OPEN
- **Author:** fmilioni
- **Created:** 2026-09-15T15:10:29Z
- **Updated:** 2026-09-15T17:15:58Z
- **Closed:** —
- **Labels:** —

## Report

Hi. Could you please add support for my controller?

## Hardware

- Controller: 8BitDo Ultimate 2C Wireless
- Bluetooth LE: VID `0x2DC8` / PID `0x301B` (11720 / 12315), product string `8BitDo Ultimate 2C Wireless`
- 2.4 GHz receiver: VID `0x2DC8` / PID `0x301C` (11720 / 12316), product string `8BitDo Ultimate 2C Wireless Controller`, 12 Mb/s, one HID interface
- Host: MacBook Pro M5 Max, macOS 26.6.2
- OpenJoystickDriver version tested: 0.5.0-beta.4

### Notes

- **`2DC8:301B`**: Bluetooth LE (mode switch `BT`, intended for Android).
- **`2DC8:301C`**: the bundled 2.4 GHz receiver (mode switch `2.4G`). On macOS the receiver enumerates as a single HID-class interface (`bInterfaceClass = 3`), **not** as the XUSB `2DC8:310A` identity that Linux xpad lists, so the existing `310A` record does not apply. While no controller is paired, the receiver reports the product string `IDLE`.

- **ZL/ZR are always reported as held.** The right stick is published on `Z`/`Rz`, which the standard layout reads as triggers. With the stick at rest (`0x7F`), both triggers read about 0.5.
- **The right stick does not work**, for the same reason.
- **The real analog triggers are ignored.** They are published on the Simulation page as `Accelerator`/`Brake`, which only the WR-007 layout accepts.
- **Buttons are shifted.** The controller uses Android button order (usages 3 and 6 = rear L4/R4, 9/10 = digital LT/RT), while the standard layout indexes usages 1–11 in Xbox order. As a result X → Y, Y → LB, LB → View, RB → Menu, LT → L3, RT → R3, View → Guide, and Menu, Home, L3, and R3 produce nothing.

## HID report descriptors

### Bluetooth LE (`301B`)

Raw, from `ioreg -l -r -c IOHIDDevice`:

```
05010905a1018501050115002507463b0195017504651409398142750195048101150026ff0009300931093209359504750881020502150026ff0009c409c5950275088102050919012910150025017501951081020506092015002564750895018102050f0970850515002564750895049102c0
```

Decoded:

```
Usage Page (Generic Desktop)
Usage (Game Pad)
Collection (Application)
  Report ID (1)
  Usage Page (Generic Desktop)
  Logical Min (0), Logical Max (7), Physical Max (315), Unit (Degrees)
  Report Size (4), Report Count (1)
  Usage (Hat Switch)                         Input (Data,Var,Abs,Null State)
  Report Size (1), Report Count (4)          Input (Const)            ; padding
  Logical Min (0), Logical Max (255)
  Usage (X), Usage (Y), Usage (Z), Usage (Rz)
  Report Count (4), Report Size (8)          Input (Data,Var,Abs)
  Usage Page (Simulation Controls)
  Logical Min (0), Logical Max (255)
  Usage (Accelerator), Usage (Brake)
  Report Count (2), Report Size (8)          Input (Data,Var,Abs)
  Usage Page (Button)
  Usage Min (1), Usage Max (16)
  Logical Min (0), Logical Max (1)
  Report Size (1), Report Count (16)         Input (Data,Var,Abs)
  Usage Page (Generic Device Controls)
  Usage (Battery Strength)
  Logical Min (0), Logical Max (100)
  Report Size (8), Report Count (1)          Input (Data,Var,Abs)
  Usage Page (PID)
  Usage (0x70)
  Report ID (5)
  Logical Min (0), Logical Max (100)
  Report Size (8), Report Count (4)          Output (Data,Var,Abs)    ; likely rumble
End Collection
```

### 2.4 GHz receiver (`301C`)

```
05010905a101850115002501350045017501950f05091901290f81029501810105012507463b017504950165140939814265009501810126ff0046ff0009300931093209357508950481020502150026ff0009c409c595027508810205080943150026ff00350046ff00750895029182094491820945918209469182850209027508953f8103858109037508953f9183c0
```

Same usages as Bluetooth in a different byte order: 15 buttons first, then the hat (with Null State, and the Unit reset afterwards), X/Y/Z/Rz, and Accelerator/Brake. There is no battery byte. Outputs are report 1 (LED page usages `0x43`–`0x46`, 2 bytes each) and a 63-byte vendor report `0x81`.

Because `GenericHIDParser` works from descriptor-decoded element values rather than byte offsets, one tuple layout covers both identities.

## Input report map, Bluetooth LE (Report ID `0x01`)

Offsets are relative to the first byte **after** the report ID. Captured with `hidapi` on macOS, which includes the report ID as byte 0 of the buffer.

| Offset | Control | Range / values |
|---|---|---|
| 0 (low nibble) | D-pad (hat) | `0` up, `2` right, `4` down, `6` left, `0xF` released (null state) |
| 1 | Left stick X | `0x00` left → `0xFF` right, center `0x7F` |
| 2 | Left stick Y | `0x00` up → `0xFF` down, center `0x7F` |
| 3 | Right stick X (declared `Z`) | `0x00` left → `0xFF` right, center `0x7F` |
| 4 | Right stick Y (declared `Rz`) | `0x00` up → `0xFF` down, center `0x7F` |
| 5 | Right trigger, analog (declared `Accelerator`) | `0x00` → `0xFF` |
| 6 | Left trigger, analog (declared `Brake`) | `0x00` → `0xFF` |
| 7–8 | Buttons, 16 bits little-endian | see below |
| 9 | Battery strength | always `0x00` in all captures |

## Input report map, 2.4 GHz receiver (Report ID `0x01`)

| Offset | Control |
|---|---|
| 0–1 | Buttons 1–15, little-endian (same bit assignment as below) |
| 2 (low nibble) | D-pad, same values as Bluetooth |
| 3–6 | Left stick X/Y, right stick X/Y (`Z`/`Rz`), same ranges |
| 7 | Right trigger (`Accelerator`) |
| 8 | Left trigger (`Brake`) |

## Buttons (both identities)

| Bit | HID usage | Button |
|---|---|---|
| 0 | 1 | A (bottom face) |
| 1 | 2 | B (right face) |
| 2 | 3 | rear L4/R4 (see Notes) |
| 3 | 4 | X (left face) |
| 4 | 5 | Y (top face) |
| 5 | 6 | rear L4/R4 (see Notes) |
| 6 | 7 | LB |
| 7 | 8 | RB |
| 8 | 9 | LT digital (redundant with byte 6) |
| 9 | 10 | RT digital (redundant with byte 5) |
| 10 | 11 | View / − |
| 11 | 12 | Menu / + |
| 12 | 13 | Home |
| 13 | 14 | L3 |
| 14 | 15 | R3 |
| 15 | 16 | unused (not declared on the receiver) |

Face-button names follow the Xbox-style labels printed on the controller (A bottom, B right, X left, Y top).

The digital trigger bits are asserted in addition to the analog values. They turn on partway through the pull (observed around `0x20`–`0x30`) and turn off near the end of the release. This parser uses the analog bytes and ignores bits 8–9.

## Raw captures (Bluetooth LE)

Each line is a full `hidapi` read (report ID first). Lines are only printed when the report changes.

### At rest
```
01 0f 7f 7f 7f 7f 00 00 00 00 00
```

### Left stick: left, right, up, down
```
01 0f 00 87 7f 7f 00 00 00 00 00   ; full left
01 0f ff 98 7f 7f 00 00 00 00 00   ; full right
01 0f 77 00 7f 7f 00 00 00 00 00   ; full up
01 0f 75 ff 7f 7f 00 00 00 00 00   ; full down
```

### Right stick: left, right, up, down
```
01 0f 7f 7f 00 95 00 00 00 00 00   ; full left
01 0f 7f 7f ff 85 00 00 00 00 00   ; full right
01 0f 7f 7f 98 00 00 00 00 00 00   ; full up
01 0f 7f 7f 8f ff 00 00 00 00 00   ; full down
```

### D-pad: left, right, up, down
```
01 06 7f 7f 7f 7f 00 00 00 00 00
01 02 7f 7f 7f 7f 00 00 00 00 00
01 00 7f 7f 7f 7f 00 00 00 00 00
01 04 7f 7f 7f 7f 00 00 00 00 00
```

### A, B, X, Y, LB, RB
```
01 0f 7f 7f 7f 7f 00 00 01 00 00   ; A
01 0f 7f 7f 7f 7f 00 00 02 00 00   ; B
01 0f 7f 7f 7f 7f 00 00 08 00 00   ; X
01 0f 7f 7f 7f 7f 00 00 10 00 00   ; Y
01 0f 7f 7f 7f 7f 00 00 40 00 00   ; LB
01 0f 7f 7f 7f 7f 00 00 80 00 00   ; RB
```

### LT full pull and release
```
01 0f 7f 7f 7f 7f 00 06 00 00 00
01 0f 7f 7f 7f 7f 00 2c 00 01 00
01 0f 7f 7f 7f 7f 00 87 00 01 00
01 0f 7f 7f 7f 7f 00 ff 00 01 00
01 0f 7f 7f 7f 7f 00 ab 00 01 00
01 0f 7f 7f 7f 7f 00 67 00 01 00
01 0f 7f 7f 7f 7f 00 38 00 01 00
01 0f 7f 7f 7f 7f 00 18 00 00 00
01 0f 7f 7f 7f 7f 00 04 00 00 00
```
### RT full pull and release
```
01 0f 7f 7f 7f 7f 04 00 00 00 00
01 0f 7f 7f 7f 7f 1e 00 00 00 00
01 0f 7f 7f 7f 7f 92 00 00 02 00
01 0f 7f 7f 7f 7f ff 00 00 02 00
01 0f 7f 7f 7f 7f f2 00 00 02 00
01 0f 7f 7f 7f 7f 76 00 00 02 00
01 0f 7f 7f 7f 7f 30 00 00 02 00
01 0f 7f 7f 7f 7f 0f 00 00 00 00
```
### −, +, Home, L3, R3, rear buttons
```
01 0f 7f 7f 7f 7f 00 00 00 04 00   ; View / −
01 0f 7f 7f 7f 7f 00 00 00 08 00   ; Menu / +
01 0f 7f 7f 7f 7f 00 00 00 10 00   ; Home
01 0f 7f 7f 7f 7f 00 00 00 20 00   ; L3
01 0f 7f 7f 7f 7f 00 00 00 40 00   ; R3
01 0f 7f 7f 7f 7f 00 00 20 00 00   ; rear button (pressed first as L4)
01 0f 7f 7f 7f 7f 00 00 04 00 00   ; rear button (pressed second as R4)
```

## Raw captures (2.4 GHz receiver)

###  Sticks, D-pad, and buttons
```
01 00 00 0f 7f 7f 7f 7f 00 00   ; at rest
01 00 00 0f 00 6c 7f 7f 00 00   ; left stick full left
01 00 00 0f ff 76 7f 7f 00 00   ; left stick full right
01 00 00 0f 83 00 7f 7f 00 00   ; left stick full up
01 00 00 0f 77 ff 7f 7f 00 00   ; left stick full down
01 00 00 0f 7f 7f 00 7c 00 00   ; right stick full left
01 00 00 0f 7f 7f ff 6a 00 00   ; right stick full right
01 00 00 0f 7f 7f 76 00 00 00   ; right stick full up
01 00 00 0f 7f 7f 84 ff 00 00   ; right stick full down
01 00 00 06 7f 7f 7f 7f 00 00   ; D-pad left
01 00 00 02 7f 7f 7f 7f 00 00   ; D-pad right
01 00 00 00 7f 7f 7f 7f 00 00   ; D-pad up
01 00 00 04 7f 7f 7f 7f 00 00   ; D-pad down
01 01 00 0f 7f 7f 7f 7f 00 00   ; A
01 02 00 0f 7f 7f 7f 7f 00 00   ; B
01 08 00 0f 7f 7f 7f 7f 00 00   ; X
01 10 00 0f 7f 7f 7f 7f 00 00   ; Y
01 40 00 0f 7f 7f 7f 7f 00 00   ; LB
01 80 00 0f 7f 7f 7f 7f 00 00   ; RB
01 04 00 0f 7f 7f 7f 7f 00 00   ; rear button
01 20 00 0f 7f 7f 7f 7f 00 00   ; rear button
01 00 04 0f 7f 7f 7f 7f 00 00   ; View / −
01 00 08 0f 7f 7f 7f 7f 00 00   ; Menu / +
01 00 10 0f 7f 7f 7f 7f 00 00   ; Home
```

### LT, then RT (excerpt)
```
01 00 00 0f 7f 7f 7f 7f 00 1b
01 00 01 0f 7f 7f 7f 7f 00 22   ; LT digital bit set
01 00 01 0f 7f 7f 7f 7f 00 ff   ; LT full (Brake)
01 00 00 0f 7f 7f 7f 7f 00 1b   ; LT digital bit cleared
01 00 00 0f 7f 7f 7f 7f 1e 00
01 00 02 0f 7f 7f 7f 7f 23 00   ; RT digital bit set
01 00 02 0f 7f 7f 7f 7f ff 00   ; RT full (Accelerator)
01 00 00 0f 7f 7f 7f 7f 1d 00   ; RT digital bit cleared
```

## Comments

### fmilioni — 2026-09-15T16:28:06Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/34#issuecomment-5684006139)

Maybe this patch file could do the trick, if you wanna take a look on it.

[8bitdo-ultimate-2c.patch.zip](https://github.com/user-attachments/files/32251927/8bitdo-ultimate-2c.patch.zip)

### xsyetopz — 2026-09-15T17:15:58Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/34#issuecomment-5684717517)

On it!
