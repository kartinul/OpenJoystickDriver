# #33: Wired SCUF Envision Pro (2E95:434D): tested HID discovery/mapping patch and signed build request

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/33
- **State:** OPEN
- **Author:** zoltanerdelyic1
- **Created:** 2026-09-13T04:24:13Z
- **Updated:** 2026-09-15T00:32:52Z
- **Closed:** —
- **Labels:** —

## Report

I tested a small patch against OpenJoystickDriver 0.5.0-beta.3 (`f42ee3416a8a4a7d4aef904beaf4a5428db72ecb`) on Apple Silicon macOS 27.0. Could you review it and provide a properly signed test build containing the virtual-HID entitlement so I can finish testing it with Steam?

### Device and discovery issue

The wired SCUF Envision Pro is VID **11925 / 0x2E95**, PID **17229 / 0x434D**. Its HID descriptor has primary usage `FF58:0001` and a secondary Game Pad collection, so the default CoreHID primary-gamepad scan misses it. The other SCUF entry, `2E95:0504`, uses GIP and is not applicable. The installed app showed `controllers=[]` and `hidGamepads=[]`.

### Proposed patch

The attached patch adds an authored `GenericHID` catalog override and regenerated record, preserves report IDs in both HID element backends, and adds a mapping for this exact VID/PID. Only Report 6 is accepted. X/Y and Z/Rz are signed 16-bit sticks; Rx/Ry are independent 10-bit triggers. Buttons 1–10 map to A/B/X/Y, LB/RB, Back/Start and L3/R3. The standard eight-direction hat parser is retained. Other controllers keep their existing generic mappings. No schema or DriverKit change is needed.

### Live test results

A Terminal probe using the patched OJD CoreHID backend and parser verified:

- All ten buttons press and release with balanced event counts.
- Movement on both sticks, returning to raw zero.
- Both triggers reach 1023 and return to zero.
- All four cardinal D-pad directions and release to neutral.

All **872 Swift tests** passed, including new Envision tests and existing generic HID regressions. Catalog, profile and schema checks passed. The app compiled for arm64 using the installed macOS 26.5 SDK; this Mac's macOS 27 SDK has a missing SwiftUI macro component. SwiftLint was unavailable, and the separate macOS-14 parser harness hit existing stale API references (`mappingFlags`, `genericButton1`).

### Remaining work

The ad-hoc development build cannot publish virtual-controller output because it lacks `com.apple.developer.hid.virtual.device`. Steam, rumble, independent paddles, wireless operation and reconnect behavior are not yet verified. Rear paddles currently duplicate face buttons. Buttons 11–19 are left unmapped pending physical identification. Full stick travel/orientation and D-pad diagonals still need interactive verification. No SIP, firmware or system-driver modifications are included.

The initial probe inside Codex returned `notPermitted`; the subsequent user-run Terminal test succeeded. The separate CoreHID `hidGamepads` diagnostic scan still matches primary usages only, so its omission of the physical device should not be confused with the patched runtime discovery result.

### Attachment

The ZIP contains `SCUF-Envision-beta3.patch` and a concise `SCUF-Live-Test-Results.md` summary, without raw serial numbers or home-directory paths.

[SCUF-Envision-patch-and-live-test.zip](https://github.com/user-attachments/files/32154697/SCUF-Envision-patch-and-live-test.zip)

## Comments

### xsyetopz — 2026-09-15T00:32:52Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/33#issuecomment-5672843110)

OpenJoystickDriver 0.5.0-beta.4 is published: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.4

Thank you for the SCUF descriptor, report, and live-input evidence; the release notes credit `@zoltanerdelyic1`. The exact `2E95:434D` record now discovers report 6 through both HID backends and maps the reported sticks, independent triggers, buttons 1–10, and hat. Please complete the signed-build and reconnect procedure: https://github.com/xsyetopz/OpenJoystickDriver/blob/0.5.0-beta.4/docs/testing/scuf-envision-pro.md

Keeping this issue open. Buttons 11–19, physical output, wireless operation, and other SCUF identities still require separate evidence.
