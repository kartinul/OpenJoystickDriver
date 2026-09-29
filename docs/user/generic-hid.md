# Generic HID

An uncatalogued HID gamepad binds to `hid.descriptor` only when its report descriptor passes OJD's
descriptor contract: a directional input and a button inside one Joystick, Game Pad, or Multi-axis
Controller collection, with no unsupported or inconsistent items. Otherwise it stays unbound and
`status` lists the reason. It is not a fallback: a known record keeps its protocol-specific parser,
and a device that fails that parser's checks is never retried as generic HID. Controllers that macOS
already supports natively are left to macOS.

The parser uses parsed IOKit elements instead of guessed byte offsets.

The generic HID parser maps button usages 1 through 19. It also maps X/Y and Rx/Ry stick pairs, Z/Rz
triggers, and an eight-position hat. Logical ranges are clamped and normalized. Repeated button
values do not emit duplicate transitions. An invalid hat value becomes neutral.

The sixteenth virtual button carries the first extra generic button. Further buttons remain visible
in OJD diagnostics but do not fit the 16-button compatibility reports.

HID descriptors name fields, not a universal physical button order. Vendor reports and unusual axes
need a record and parser. So do handshakes, paddles, and extra controls. Verify every control in
Controller Settings Live or the headless input diagnostic before claiming support.
