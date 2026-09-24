# #35: Flydigi Vader 4 Pro: dongle DInput and Bluetooth XInput reach only the generic fallback

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/35
- **State:** OPEN
- **Author:** scraton
- **Created:** 2026-09-15T20:53:53Z
- **Updated:** 2026-09-15T20:53:53Z
- **Closed:** —
- **Labels:** —

## Report

Device: Flydigi Vader 4 Pro, firmware 6.9.5.5
Host: macOS 26.5.2 (25F84), Apple silicon, OJD 0.5.0-beta.4

The Vader 4 Pro presents a different VID/PID for each combination of its rear
slider position and DInput/XInput toggle, and macOS treats each as a separate
device. Bluetooth DInput works since beta.4. Two of the others enumerate fine
but reach only `GenericHIDParser`, which cannot decode either protocol.

| Mode | Identity | In catalog | Parser reached | Result |
| --- | --- | --- | --- | --- |
| Bluetooth DInput | `D7D7:0041` | yes | `Flydigi` | works |
| Switch | `057E:2009` | yes | `SwitchPro` | works |
| **Dongle DInput** | **`04B4:2412`** | **no** | `GenericHID` | see below |
| **Bluetooth XInput** | **`045E:02E0`** | **no** | `GenericHID` | see below |

## Bluetooth XInput — `045E:02E0`

In this mode the controller advertises the Xbox One S Bluetooth identity. Most
controls survive the descriptor-driven fallback, but two do not.

**Sticks are confined to one quadrant.** The axes are unsigned 16-bit words
centred at `0x7FFF`, so reading them as signed wraps every value at or above
`0x8000` to a negative number. Captured neutral report:

```
01 00 7F FF 7F 00 7F FF 7F 00 00 00 00 00 00 00
   ^^^^^ LX = 0x7F00      ^^^^^ RX = 0x7F00
```

Holding the left stick fully right moves byte 2 from `7F` to `FF`, giving
`0xFF00`; fully left gives `0x0000`. Both Y axes rest at `0x7FFF`.

**Home never registers.** Pressing it changes the report ID from `0x01` to
`0x02`, matching the System Control collection in the report descriptor. A
parser that decodes only report `0x01` never sees it.

Observed in the input tester: buttons, bumpers, triggers and D-pad correct;
both sticks limited to one quadrant; Home absent.

## Dongle DInput — `04B4:2412`

This is the identity SDL's Flydigi driver matches. The device is composite:

| Usage page:usage | maxIn | maxOut | Role |
| --- | --- | --- | --- |
| `1:5` | 9 | 0 | gamepad collection |
| `65440:1` (`0xFFA0`) | 32 | 32 | vendor protocol: input and vibration |
| `65518:0` (`0xFFEE`) | 64 | 64 | unused |
| `1:2` | 7 | 1 | mouse collection; the gyro drives the pointer here |

Enumeration order is not stable between runs, so the vendor interface has to be
matched on usage page rather than index.

The vendor interface streams a 32-byte report on ID 4 prefixed `04 FE 66`:

| Byte | Contents |
| --- | --- |
| 7 | `0x01` C, `0x02` Z, `0x04` M1, `0x08` M2, `0x10` M3, `0x20` M4 |
| 8 | `0x08` Home |
| 9 | low nibble D-pad up/right/down/left; `0x10` A, `0x20` B, `0x40` Select, `0x80` X |
| 10 | `0x01` Y, `0x02` Start, `0x04` LB, `0x08` RB, `0x10` LT digital, `0x20` RT digital, `0x40` L3, `0x80` R3 |
| 17, 19, 21, 22 | LX, LY, RX, RY, single bytes centred at `0x7F` |
| 23, 24 | LT and RT, unsigned, full `0...255` |

Bytes 4-6, 26, 27, 29 and 30 carry motion data that changes continuously even
at rest; bytes 11-15 behave as a counter. Neither correlates with any control.

**This is the only mode where the back paddles are addressable.** C, Z and
M1-M4 each own a bit in byte 7. In every other mode they repeat whichever
button the controller's firmware assigns them, so the driver receives an
ordinary press and cannot tell them apart.

**Vibration works on this transport.** The controller accepts a four-byte frame
on report 5 of the same `0xFFA0` interface:

```
05 0F <left magnitude> <right magnitude>
```

Verified by driving the motors directly: magnitude is honoured, the two motors
are independently addressable and differ in strength, and the effect latches —
the motors run until a frame carrying the `0x0F` command byte with zero
magnitudes arrives. An empty or all-zero payload is ignored, and killing the
writing process leaves them running until the dongle is unplugged. Sustained
vibration needs the frame resent at roughly 10 Hz; a single frame decays.

## What each identity needs

Both need a catalog record and a parser. Neither existing parser can absorb
them: `FlydigiParser` accepts only the 15-byte Bluetooth report, and
`Xbox360Parser` speaks the Xbox 360 wire protocol rather than the Bluetooth HID
layout, so widening either would change behaviour for the controllers it
already serves.

## Method

Reports were captured by reading raw HID input through
`IOHIDDeviceRegisterInputReportCallback` with an explicit buffer, one control
held per sample. Vibration results are physical observations, not inferred from
return codes.

One caution for anyone reproducing this: `OpenJoystickDriverHIDTool --monitor`
registers through `IOHIDManagerRegisterInputReportCallback`, which takes no
report buffer, and delivers short and inconsistent reports under load. Several
early conclusions in this investigation were wrong because of it. That looks
like a separate bug worth its own report.

I have the hardware and am happy to test a signed build.

## Comments

_No comments._
