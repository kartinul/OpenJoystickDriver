# #37: Flydigi Vader 4 Pro dongle in XInput mode: one identity, two transports

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/37
- **State:** OPEN
- **Author:** scraton
- **Created:** 2026-09-15T21:03:59Z
- **Updated:** 2026-09-15T21:03:59Z
- **Closed:** —
- **Labels:** —

## Report

Device: Flydigi Vader 4 Pro on its 2.4 GHz dongle, XInput mode, firmware 6.9.5.5
Host: macOS 26.5.2 (25F84), Apple silicon, OJD 0.5.0-beta.4

In this mode the controller enumerates as `045E:028E`, the generic Microsoft
Xbox 360 wired identity, and speaks the Xbox 360 protocol correctly: reports are
a uniform 20 bytes at the standard xpad offsets. It appears in `controller list`
with the right name, but no control registers.

macOS surfaces this dongle through the HID stack, while genuine Xbox 360 wired
controllers sharing the identity are opened as raw USB interfaces. The record
declares `transport: "usb"`, and `ParserRegistry` compares exactly
(`ParserRegistry.swift:22` and `:56`), so on macOS 15+ the CoreHID backend
resolves with `.hid`, misses, and falls back to `GenericHIDParser` — which
cannot decode a binary Xbox 360 report. The name still shows because the catalog
supplies it regardless of transport.

Confirmed against a captured A-press report:

```
via .hid -> GenericHIDParser  events: 0
via .usb -> Xbox360Parser     events: 1  [buttonPressed(.a)]
```

Patching the bundled record to `transport: "hid"` in a copy of the signed app
restores full input, verified on hardware: every button, stick, D-pad direction
and analog trigger maps correctly. But `transport` holds one value, so that
setting would strand every genuine Xbox 360 controller on the raw USB path.
One identity, one protocol, two access paths, and no way to express it.

## Why this is a design question

Widening the comparison works but contradicts two assertions that look
deliberate rather than incidental:

- `RawUSBAdmissionPolicyTests.specializedParsersRequireTheirCatalogedTransport`
  names `045E:028E` explicitly and requires it to fall back on the HID path;
- `HIDProfileDiscoveryTests.hidAndRawUSBCatalogPartitionsAreDisjoint` requires
  the two catalog partitions never to overlap.

I prototyped a third transport value that matches either path, leaving `usb`
and `hid` exactly as they are so no existing record changes meaning. It made
the dongle work and kept genuine Xbox 360 controllers on `XUSB`, but it breaks
both suites above, so I reverted it rather than rewrite your invariants.

## Priority

Low. Dongle DInput mode is strictly better on this controller — it carries
vibration and reports the back paddles separately — so this is completeness
rather than something a Vader owner needs. Filing it because the transport
mismatch is a property of the catalog model, not of this controller, and may
affect other devices that macOS surfaces over HID while their record says USB.

Happy to test a build or open a PR if you decide on a direction.

## Comments

_No comments._
