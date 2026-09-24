# #22: ZD Ultimate Legend Support

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/22
- **State:** OPEN
- **Author:** lunarephemera
- **Created:** 2026-07-30T18:46:37Z
- **Updated:** 2026-09-23T17:37:28Z
- **Closed:** —
- **Labels:** bug, help wanted

## Report

Device: ZD Ultimate Legend in XInput mode, wired USB
VID 0x413D, PID 0x2104 ("XBOX 360 For Windows")
macOS 26.6.0, OJD v0.4.1

Profile 413d-2104.json already exists in the catalog, but the device
is never detected. `diagnose report` prints:

  USB Game Controllers (class 0xFF):
    (none detected)

Cause: this controller reports bDeviceClass = 0 and declares the
vendor-specific class only at the interface level. Confirmed via
ioreg: "bDeviceClass" = 0 for this device.

Both discovery paths filter on the device descriptor class:

  USBDetection.swift:73
    context.findDevices(deviceClass: usbVendorSpecificClass, findAll: true)
  USBControllerScanner.swift
    context.findDevices(deviceClass: .vendorSpecific, findAll: true)

So the device is skipped before the catalog lookup ever happens.

USBDescriptorTransportResolver.swift:94 already does the right thing
elsewhere (`for interface in interfaces where interface.interfaceClass == 0xFF`),
so discovery probably needs the same interface-level check as a fallback
when bDeviceClass is 0.

Happy to test a build.

## Comments

### xsyetopz — 2026-07-31T03:21:35Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5138901236)

Damn, some controllers just *cannot* be standard, huh? Gotta love providers just doing their own thing. Alright, that's another thing to get going.

### lunarephemera — 2026-08-01T08:10:32Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5150559853)

Thanks for turning this around so fast.

I still have the hardware here (ZD Ultimate Legend, 413D:2104), so I'm happy to test the fix before it ships. Is there a build of main I could grab somewhere? I don't have a Swift toolchain set up on my side, so a packaged .app would be ideal — but no rush if you'd rather just fold it into the next release.

One thing worth checking while I'm at it: 413d-2104.json is marked verified: false and came from linux-xpad.c, so the button mapping has never been confirmed on real hardware. Once detection works I can go through Input Test and report back on whether the mapping is correct, and you can flip the flag if it is.

### xsyetopz — 2026-08-01T12:56:04Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151514770)

> Thanks for turning this around so fast.
>
> I still have the hardware here (ZD Ultimate Legend, 413D:2104), so I'm happy to test the fix before it ships. Is there a build of main I could grab somewhere? I don't have a Swift toolchain set up on my side, so a packaged .app would be ideal — but no rush if you'd rather just fold it into the next release.
>
> One thing worth checking while I'm at it: 413d-2104.json is marked verified: false and came from linux-xpad.c, so the button mapping has never been confirmed on real hardware. Once detection works I can go through Input Test and report back on whether the mapping is correct, and you can flip the flag if it is.

I've yet to make a new release (beta) as 0.5.0 is supposed to be a giant update that breaks some changes, therefore there's time before I get there. It needs a new MenuApp GUI.

### lunarephemera — 2026-08-01T13:50:40Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151707639)

Ran the unsigned CLI path against the hardware. Summary: the raw USB side works perfectly and the record's mapping is correct, but `diagnose record` itself fails. Details below.

**Descriptors confirm the fix targets the right thing**

```
bDeviceClass = 0
  interface 0: bInterfaceClass = 255, bInterfaceSubClass = 93   <- XInput
  interface 1: bInterfaceClass = 3,   bInterfaceSubClass = 1
  interface 2: bInterfaceClass = 3,   bInterfaceSubClass = 0
```

So this is a composite device: a vendor-specific XInput interface plus two HID interfaces. The HID ones are already matched by macOS (`IOClass = AppleUserHIDDevice`, `com.apple.AppleUserHIDDrivers`); the vendor-specific interface is unclaimed.

**Raw USB monitor works**

```
OpenJoystickDriverHIDTool --usb-monitor --vid 0x413d --pid 0x2104 --interface 0 --seconds 20
-> USB_SUMMARY packets=159617 disabled_endpoints=14
```

Endpoint 0x81, 20-byte reports, standard wired Xbox 360 layout, e.g.

```
00 14 00 00 00 00 35 77 e9 c2 77 eb 22 dc 00 00 00 00 00 00
```

**Mapping verified, 16/16**

Taken from the raw capture, one control at a time (byte 2 / byte 3):

```
01 00  dpad up        00 01  LB
02 00  dpad down      00 02  RB
04 00  dpad left      00 04  Guide
08 00  dpad right     00 10  A
10 00  Start          00 20  B
20 00  Back           00 40  X
40 00  L3             00 80  Y
80 00  R3
```

Every control matches the standard wired Xbox 360 layout bit for bit — no remapping needed. Triggers are fully analog: byte 4 takes 252 distinct values and byte 5 takes 255 across the capture. Sticks read near zero at rest with no drift and reach full range.

So the identity and parsing side of 413d-2104.json looks correct. I haven't checked reconnect stability or LED/rumble behavior, so I'll leave the call on flipping `verified` to you.

**But `diagnose record` fails**

```
RECORD identity="Controller 413d:2104" vid=16701 pid=8452 driver=Xbox360 interface=0 in=0x81 out=0x1 configuration=current startup=none
USB_MATCHES count=1
USB_DEVICE bus=3 address=2 class=0x0 subclass=0x0 protocol=0x0
USB_STRING manufacturer=Microsoft
USB_STRING product=XBOX 360 For Windows
USB_CLAIM interface=0 result=claimed
RECORD_HANDSHAKE driver=Xbox360 result=complete
ERROR: record probe failed: The operation couldn't be completed. (SwiftUSB.USBError error 1.)
```

No USB_RX, no RECORD_SUMMARY. Same result under sudo. With `--detach` it fails earlier with `LIBUSB_ERROR_ACCESS (code: -3)`, which I assume is expected on macOS.

So: claiming works, the handshake completes, and raw reads on the same endpoint work fine outside the probe — but the probe's first read throws. The read loop only continues on `error.isTimeout`, so anything else aborts.

Two things that made this harder to diagnose, in case they're worth fixing:

- The real libusb code never surfaces. `isExpectedError` suppresses logging for IO / NOT_FOUND / NO_DEVICE, and `USBError` has no `LocalizedError` conformance, so the message degrades to "error 1". Printing the code on probe abort would have made this a one-line report.
- `startup=none` on a wired Xbox 360 record — I wasn't sure whether that's expected, given the docs mention a steady Player 1 ring-light packet.

Happy to run anything else against the hardware.

macOS 26.6.0, MacBook Pro M5, commit 559933f, record is the bundled 413d-2104.json copied verbatim.

### xsyetopz — 2026-08-01T13:52:20Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151713106)

> Ran the unsigned CLI path against the hardware. Summary: the raw USB side works perfectly and the record's mapping is correct, but `diagnose record` itself fails. Details below.
>
> **Descriptors confirm the fix targets the right thing**
>
> ```
> bDeviceClass = 0
>   interface 0: bInterfaceClass = 255, bInterfaceSubClass = 93   <- XInput
>   interface 1: bInterfaceClass = 3,   bInterfaceSubClass = 1
>   interface 2: bInterfaceClass = 3,   bInterfaceSubClass = 0
> ```
>
> So this is a composite device: a vendor-specific XInput interface plus two HID interfaces. The HID ones are already matched by macOS (`IOClass = AppleUserHIDDevice`, `com.apple.AppleUserHIDDrivers`); the vendor-specific interface is unclaimed.
>
> **Raw USB monitor works**
>
> ```
> OpenJoystickDriverHIDTool --usb-monitor --vid 0x413d --pid 0x2104 --interface 0 --seconds 20
> -> USB_SUMMARY packets=159617 disabled_endpoints=14
> ```
>
> Endpoint 0x81, 20-byte reports, standard wired Xbox 360 layout, e.g.
>
> ```
> 00 14 00 00 00 00 35 77 e9 c2 77 eb 22 dc 00 00 00 00 00 00
> ```
>
> **Mapping verified, 16/16**
>
> Taken from the raw capture, one control at a time (byte 2 / byte 3):
>
> ```
> 01 00  dpad up        00 01  LB
> 02 00  dpad down      00 02  RB
> 04 00  dpad left      00 04  Guide
> 08 00  dpad right     00 10  A
> 10 00  Start          00 20  B
> 20 00  Back           00 40  X
> 40 00  L3             00 80  Y
> 80 00  R3
> ```
>
> Every control matches the standard wired Xbox 360 layout bit for bit — no remapping needed. Triggers are fully analog: byte 4 takes 252 distinct values and byte 5 takes 255 across the capture. Sticks read near zero at rest with no drift and reach full range.
>
> So the identity and parsing side of 413d-2104.json looks correct. I haven't checked reconnect stability or LED/rumble behavior, so I'll leave the call on flipping `verified` to you.
>
> **But `diagnose record` fails**
>
> ```
> RECORD identity="Controller 413d:2104" vid=16701 pid=8452 driver=Xbox360 interface=0 in=0x81 out=0x1 configuration=current startup=none
> USB_MATCHES count=1
> USB_DEVICE bus=3 address=2 class=0x0 subclass=0x0 protocol=0x0
> USB_STRING manufacturer=Microsoft
> USB_STRING product=XBOX 360 For Windows
> USB_CLAIM interface=0 result=claimed
> RECORD_HANDSHAKE driver=Xbox360 result=complete
> ERROR: record probe failed: The operation couldn't be completed. (SwiftUSB.USBError error 1.)
> ```
>
> No USB_RX, no RECORD_SUMMARY. Same result under sudo. With `--detach` it fails earlier with `LIBUSB_ERROR_ACCESS (code: -3)`, which I assume is expected on macOS.
>
> So: claiming works, the handshake completes, and raw reads on the same endpoint work fine outside the probe — but the probe's first read throws. The read loop only continues on `error.isTimeout`, so anything else aborts.
>
> Two things that made this harder to diagnose, in case they're worth fixing:
>
> * The real libusb code never surfaces. `isExpectedError` suppresses logging for IO / NOT_FOUND / NO_DEVICE, and `USBError` has no `LocalizedError` conformance, so the message degrades to "error 1". Printing the code on probe abort would have made this a one-line report.
> * `startup=none` on a wired Xbox 360 record — I wasn't sure whether that's expected, given the docs mention a steady Player 1 ring-light packet.
>
> Happy to run anything else against the hardware.
>
> macOS 26.6.0, MacBook Pro M5, commit [559933f](https://github.com/xsyetopz/OpenJoystickDriver/commit/559933fe1afaf7c26bd544e14a3e2ade62e5030e), record is the bundled 413d-2104.json copied verbatim.

Motherf##ing ZD, man. Why do they do this? *siiiiiiigh* back to the code we go...

### xsyetopz — 2026-08-01T13:54:21Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151720347)

<img width="1600" height="1200" alt="Image" src="https://github.com/user-attachments/assets/9901c4fc-e51c-46d5-a74e-5c03b38a29c9" />

### lunarephemera — 2026-08-01T13:57:07Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151735439)

Sorry about the extra work, didn't mean to ruin your weekend with a no-name controller

For what it's worth, the hardware's here and the CLI builds fine on my side, so I'm around whenever you want something tested or captured. Just say what you need and I'll run it

### xsyetopz — 2026-08-01T13:59:56Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5151745523)

> Sorry about the extra work, didn't mean to ruin your weekend with a no-name controller
>
> For what it's worth, the hardware's here and the CLI builds fine on my side, so I'm around whenever you want something tested or captured. Just say what you need and I'll run it

Haha, it's all good. Nothing was ruint. Trust. I *REALLY* appreciate people actually finding this project useful and contributing. HOWEVER, ZD... the company... yeah, they can take a walk in the forest.

### xsyetopz — 2026-08-25T16:21:01Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5413398474)

Try [0.5.0-beta.1](https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.1) and tell me if it works!

### lunarephemera — 2026-08-27T11:21:34Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5438245132)

Tested 0.5.0-beta.1 against the same hardware (ZD Ultimate Legend, 413D:2104). Good news first: detection and handshake both work now, which they didn't in the pre-beta build. But there's a regression that breaks the record probe and, from the app's Console log, the real pipeline too.

**CLI record probe**

```
RECORD identity="Controller 413d:2104" vid=16701 pid=8452 driver=Xbox360 interface=0 in=0x81 out=0x1 configuration=current profile_startup=none usb_startup=01 03 06
USB_MATCHES count=1
USB_DEVICE service=4295047396 location=51380224
USB_STRING product=XBOX 360 For Windows
USB_OPEN interface=0 route=ioUSBHost result=opened
RECORD_HANDSHAKE driver=Xbox360 result=complete
ERROR: record probe failed: The operation couldn't be completed. (OpenJoystickDriverKit.USBTransportError error 5.)
```

Error 5 is `.notSupported`. It happens right after the handshake completes, i.e. while sending the `01 03 06` player-1 LED packet.

**Root cause, I think**

Both `ControllerRecordProbeRunner.sendStartupPackets` and `USBPipeline.isIgnorableUSBStartupOutputError` only forgive this specific rejection when `error.isInputOutput`:

```swift
catch let error as USBTransportError
  where parser is Xbox360Parser && packet == [0x01, 0x03, 0x06] && error.isInputOutput
```

Under the old libusb-backed transport, this pad's LED-set rejection surfaced as an IO error, so it got swallowed here. Under the new IOUSBHostTransport, the same rejection surfaces as `kIOReturnUnsupported`/`kIOReturnBadArgument`, which maps to `.notSupported` — not `.isInputOutput` — so the guard no longer matches and the error propagates instead of being ignored.

**App behavior (Console.app, filtered to OJD)**

Same failure signature in the real pipeline, looping continuously:

```
[DeviceManager] USB device added: XBOX 360 For Windows (DeviceIdentifier(VID:0x413D PID:0x2104 loc=51380224))
[DevicePipeline] Handshake failed for DeviceIdentifier(VID:0x413D PID:0x2104 loc=51380224): notFound
... (repeats)
[DevicePipeline] Controller sleeping after idle: DeviceIdentifier(VID:0x413D PID:0x2104 loc=51380224)
```

Note the app logs `notFound` rather than `notSupported` — possibly a different failure point, or the error gets remapped somewhere in the pipeline vs. the CLI path. Menu bar icon blinks roughly once a minute, and macOS's own Controllers system pane lists the pad and forwards "Identify" rumble requests to OJD's virtual device (visible in Console as repeated "App rumble report"), but nothing reaches the hardware since the real handshake never completes on that path.

Controller identity in Controllers pane: tried all four options (Generic HID, Xbox One HID, SDL2/3, Apple GameController), same result under each.

Happy to test a patch or run more diagnostics. macOS 26.6.0, MacBook Pro (Apple Silicon)

### xsyetopz — 2026-08-27T12:37:58Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5439243062)

Alright, patch coming up. I really should probably create a Discord specifically to share temporary patch builds... Or something.

### xsyetopz — 2026-08-27T12:53:44Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5439420564)

> Alright, patch coming up. I really should probably create a Discord specifically to share temporary patch builds... Or something.

https://discord.gg/zdaRa9zy5c meanwhile patch is on the way.

### lunarephemera — 2026-08-27T17:21:24Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5442711879)

### Update: remaining `0.5.0-beta.2` failure localized to `IOUSBHost copyPipe()` on OUT endpoint `0x01`

I managed to localize the remaining failure more precisely.

**Version confirmed:**
- Checkout: `192c926`
- Tag: `0.5.0-beta.2`
- Installed app: `0.5.0-beta.2`

**What is working:**
- Controller is detected
- USB device is matched
- `IOUSBHost` opens interface `0`
- Xbox 360 handshake completes successfully

The normal probe reaches:

```text
USB_OPEN interface=0 route=ioUSBHost result=opened
RECORD_HANDSHAKE driver=Xbox360 result=complete
```

I added temporary logging around the `IOUSBHost` transfer path to determine the exact failure point.

The failure happens **before any input read**.

It occurs when the Xbox 360 startup packet `01 03 06` is about to be sent through OUT endpoint `0x01`.

The debug output is:

```text
DEBUG transfer start endpoint=1
DEBUG copyPipe failed endpoint=1 raw=Error Domain=IOUSBHostErrorDomain Code=-536870160 "Unable to copy pipe." UserInfo={NSLocalizedRecoverySuggestion=Select a valid endpoint address, NSLocalizedDescription=Unable to copy pipe., NSLocalizedFailureReason=Endpoint address not found.} mapped=notFound
ERROR: record probe failed: The operation couldn’t be completed. (OpenJoystickDriverKit.USBTransportError error 5.)
```

So the failure is specifically happening here:

```swift
interface.copyPipe(withAddress: Int(endpoint))
```

for endpoint `0x01`.

`IOUSBHost` reports:

```text
Unable to copy pipe.
Endpoint address not found.
```

and OJD maps that error to:

```text
USBTransportError.notFound
```

This also appears to explain why the GUI was previously showing:

```text
Handshake failed ... notFound
```

The important detail is that the beta.2 startup-output ignore helper currently handles:

```swift
case .inputOutput, .notSupported:
    return true
```

but the actual error returned on my controller/Mac is `.notFound`.

So the beta.2 `.notSupported` fix does not catch this case.

At this point, the remaining issue appears to be:

> `IOUSBHost` cannot resolve the OUT pipe for endpoint `0x01` on this controller/interface, and the resulting `.notFound` escapes when OJD tries to send the Xbox 360 startup packet `01 03 06`.

If useful, I can test a patch that also treats `.notFound` as ignorable for this specific Xbox 360 startup packet, or run any additional diagnostics you want.

### lunarephemera — 2026-08-29T10:40:16Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5461854120)

After the latest patch, USB open, handshake, and startup output all succeed. Here's what each virtual output mode actually does on this hardware (ZD Ultimate Legend, 413D:2104, macOS 26.6.0, Apple Silicon).

---

**Generic HID** — detected as "OJD Generic"

Steam Test Device Inputs: mostly works, with occasional dropped button events.
Games: no response.
Vibration: not tested yet.

This is the most functional mode right now. Input physically reaches Steam, buttons and sticks are read correctly most of the time.

---

**SDL2/3** — detected as "ASTRO C40 TR"

Steam Test Device Inputs: works, but:
- buttons are remapped to PlayStation layout
- both sticks are inverted on Y axis (in addition to the hardware inversion already applied by Xbox360Parser)
- identity is obviously wrong

Games: no response.
Vibration: not tested yet.

Input does reach Steam through this path. The inversion is likely a double-negation: Xbox360Parser correctly negates Y on parse, but SDL's ASTRO C40 TR mapping also flips Y, so they cancel each other in the wrong direction. Mapping is Sony-style throughout.

---

**Xbox One HID** — detected as "Xbox One S Controller" (045E:02EA)

Steam Test Device Inputs: no button or stick events.
Games: no response.
Vibration: not tested yet.

The virtual device is visible and registered. Steam sees it as a real Xbox One S and likely uses a direct XInput/GIP path rather than HID, so OJD's HID report format doesn't reach it.

---

**Apple GameController** — also detected as "Xbox One S Controller"

Behavior identical to Xbox One HID: device exists, zero input events in Steam.

---

**One interesting observation across all modes:**

When the physical controller is disconnected, games show a controller-disconnected notification — so connection state does reach them. Only gameplay input doesn't.

---

**Vibration note:**

The output endpoint `0x01` failure was only fixed in the latest patch. Vibration hasn't been tested since then. Happy to test it now if you want that data before moving on.

---

Summary: Generic HID is the only mode delivering actual input to Steam right now (after steam input layout setup). SDL2/3 delivers input but with wrong identity and doubled Y inversion. Xbox One HID and Apple GameController register cleanly but deliver nothing. The gap between "Steam sees it" and "games respond" appears to be the XInput/direct-input layer that Generic HID can't satisfy.

### lunarephemera — 2026-08-29T11:04:56Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5461971769)

Update on virtual output modes:

Apple GameController works in Hotline Miami 2 — both with and without Steam Input forced on. Other modes (Generic HID, SDL2/3, Xbox One HID) are not detected by that game at all.

Cyberpunk 2077 does not detect the controller in any mode. Since CP2077 on Mac uses the Apple GameController framework directly (bypassing Steam Input), and Hotline Miami 2 works fine through that same path, the difference is probably somewhere in how CP2077 filters or enumerates controllers — not in OJD's virtual device itself.

Polling rate measured at 1000 Hz current / 375 Hz effective, jitter 0.19 ms, through Generic HID mode (screenshot attached if useful).

Happy to test specific scenarios in either game.

Tried launching CP2077 with controller already connected, and connecting after launch — neither works. Since Apple GameController mode uses 045E:02EA (Xbox One S VID/PID), the issue might be that OJD registers as GCExtendedGamepad rather than GCXboxGamepad specifically. CP2077 may filter on the subclass.


Comparison: Windows shows 8029 Hz max / 5575 Hz effective on the same controller in the same XInput mode. macOS through OJD shows 1004 Hz max / 375 Hz effective. The gap suggests Windows driver requests a different USB transfer interval — possibly the controller supports multiple polling modes and only switches to the fast one when the driver asks. Worth checking if IOUSBHost allows requesting a shorter bInterval at open time.

### 127841352 — 2026-09-06T08:56:25Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5558170654)

Confirmed on the same controller as this issue reports: **ZD Ultimate Legend compatible pad, VID `413D`, PID `0x2104`** ("XBOX 360 For Windows"), wired USB, macOS 26.6.2 (Apple Silicon), OJD v0.5.0-beta.3.

**Symptom**: Input works perfectly (the standard wired-360 layout matches bit-for-bit, as already noted above), but rumble and player-indicator writes always fail. `app logs show` prints:

```
[DevicePipeline] Rumble send failed for DeviceIdentifier(VID:0x413D PID:0x2104 loc=1048576): notFound
[DevicePipeline] Player indicator send failed for DeviceIdentifier(VID:0x413D PID:0x2104 loc=1048576): notFound
```

**Root cause**: Same class of bug as the Logitech F310 fix in #15 — this pad's rumble OUT endpoint is `0x02`, but the Xbox360 driver default is `0x01`. The default `413d-2104.json` profile declares no endpoints, so writes go to a nonexistent endpoint.

**Fix**: Add an explicit endpoint override to `Resources/Controllers/413d-2104.json`:

```json
"usb": {
  "endpoints": {
    "in": 129,
    "out": 2
  }
}
```

**Verified on hardware**: after this one-line change (re-sign + restart), `controller output rumble 16701 8452 --left 255 --right 255` works — both leftMain and rightMain motors fire reliably. Input path unchanged and still perfect.

### xsyetopz — 2026-09-15T00:32:47Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5672842307)

OpenJoystickDriver 0.5.0-beta.4 is published: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.4

The release implements device-first IOUSBHost discovery for controllers with `bDeviceClass = 0` and resolves the vendor-specific interface afterward. It also sends ZD Ultimate Legend player-indicator and rumble packets to the observed interrupt OUT endpoint `0x02`.

Please verify discovery, input, player indicator, and rumble on `413D:2104` with the published build. The reported implementation gap is now released, so I am closing this issue; please reopen it or file a focused follow-up if the hardware test fails.

### xsyetopz — 2026-09-16T00:21:51Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5690091771)

@codex OP reported on discord that the latest notarized 0.5.0-beta.4 release had "absolutely zero difference" in implementation for this specific controller, therefore it does not work at all.

Look further into this, and report your findings.

### chatgpt-codex-connector[bot] — 2026-09-16T00:21:56Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5690093274)

To use Codex here, [create an environment for this repo](https://chatgpt.com/codex/cloud/settings/environments).

### xsyetopz — 2026-09-16T00:23:40Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5690125313)

> To use Codex here, [create an environment for this repo](https://chatgpt.com/codex/cloud/settings/environments).

@codex I've created the environment as requested. Original message requests for review:

> OP reported on discord that the latest notarized 0.5.0-beta.4 release had "absolutely zero difference" in implementation for this specific controller, therefore it does not work at all.
>
> Look further into this, and report your findings.

### chatgpt-codex-connector[bot] — 2026-09-16T00:27:46Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5690175225)

### Summary

* Investigated the reported beta.4 regression. The current source **does contain** the controller-specific implementation:
  * IOUSBHost discovery begins with `IOUSBHostDevice`, so it does not depend on `bDeviceClass == 0xFF`; the vendor-specific interface is resolved later using interface class `0xFF`.
  * The authored `413D:2104` override explicitly selects input endpoint `0x81` and output endpoint `0x02`.
  * The generated bundled controller record likewise selects XUSB/Xbox 360 with endpoints `0x81` and `0x02`.
* The available source therefore does **not** support the conclusion that beta.4 had “absolutely zero difference” for this controller. However, source inspection cannot prove that the notarized artifact contained the expected commit or identify what happened in the installed runtime.
* Added an exact-identity regression test that pins `413D:2104` to the Xbox 360 parser, raw-USB admission, interface 0, and the hardware-observed endpoint override.
* Added a transport regression test demonstrating that this composite device is enumerated from its device service, without requiring device-level vendor class or a pre-existing interface service.
* Updated the issue audit to keep the report open. The requested next evidence is the installed app’s build identity, `app logs show`, and `diagnose report`; these distinguish an artifact/install mismatch from discovery, interface-open, or pipeline failures.
* Committed the changes as `b9fb4ae` (`test(usb): pin ZD Ultimate Legend release behavior`) and prepared a new pull request titled **“test(usb): verify beta.4 ZD Ultimate Legend path.”**

**Testing**

* ✅ `git diff --check`
* ⚠️ `swift test --filter RawUSBAdmissionPolicyTests --filter TransportFacadeTests` — unavailable because the repository requires Swift 6.3.3, which is not installed in this environment.
* ⚠️ `./Scripts/ojd catalog regenerate --check && ./Scripts/ojd check profiles && ./Scripts/ojd check schemas && git diff --check` — could not complete because the repository-local schema environment attempted to install `jsonschema==4.26.0`, but outbound package access was blocked by the environment proxy.
* ✅ `git status --short --branch` — clean worktree after the commit.

 [View task →](https://chatgpt.com/s/cd_6aa9e191bd3c81918f834fe649b0b570)

### xsyetopz — 2026-09-16T00:31:11Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5690205910)

> ### Summary
> * Investigated the reported beta.4 regression. The current source **does contain** the controller-specific implementation:
>
>   * IOUSBHost discovery begins with `IOUSBHostDevice`, so it does not depend on `bDeviceClass == 0xFF`; the vendor-specific interface is resolved later using interface class `0xFF`.
>   * The authored `413D:2104` override explicitly selects input endpoint `0x81` and output endpoint `0x02`.
>   * The generated bundled controller record likewise selects XUSB/Xbox 360 with endpoints `0x81` and `0x02`.
> * The available source therefore does **not** support the conclusion that beta.4 had “absolutely zero difference” for this controller. However, source inspection cannot prove that the notarized artifact contained the expected commit or identify what happened in the installed runtime.
> * Added an exact-identity regression test that pins `413D:2104` to the Xbox 360 parser, raw-USB admission, interface 0, and the hardware-observed endpoint override.
> * Added a transport regression test demonstrating that this composite device is enumerated from its device service, without requiring device-level vendor class or a pre-existing interface service.
> * Updated the issue audit to keep the report open. The requested next evidence is the installed app’s build identity, `app logs show`, and `diagnose report`; these distinguish an artifact/install mismatch from discovery, interface-open, or pipeline failures.
> * Committed the changes as `b9fb4ae` (`test(usb): pin ZD Ultimate Legend release behavior`) and prepared a new pull request titled **“test(usb): verify beta.4 ZD Ultimate Legend path.”**
>
> **Testing**
>
> * ✅ `git diff --check`
> * ⚠️ `swift test --filter RawUSBAdmissionPolicyTests --filter TransportFacadeTests` — unavailable because the repository requires Swift 6.3.3, which is not installed in this environment.
> * ⚠️ `./Scripts/ojd catalog regenerate --check && ./Scripts/ojd check profiles && ./Scripts/ojd check schemas && git diff --check` — could not complete because the repository-local schema environment attempted to install `jsonschema==4.26.0`, but outbound package access was blocked by the environment proxy.
> * ✅ `git status --short --branch` — clean worktree after the commit.
>
> [View task →](https://chatgpt.com/s/cd_6aa9e191bd3c81918f834fe649b0b570)
@codex See here for the OP's original messages:

```
[23:23]lunarephemera: Is there anything I can do to help support the ZD UL?
[04:25]iborrowcheckbtw: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.4
[04:25]iborrowcheckbtw: notarized ver
[16:34]lunarephemera: Absolutely zero changes
```

### chatgpt-codex-connector[bot] — 2026-09-16T00:34:23Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5690230638)

### Summary

* Added an exact-identity regression test for ZD Ultimate Legend `413D:2104`, pinning the Xbox 360 parser, raw-USB admission, interface `0`, input endpoint `0x81`, and output endpoint `0x02`.
* Added a transport regression test confirming that the composite controller is discovered from its `IOUSBHostDevice` service without requiring an existing interface service.
* Corrected the issue audit to treat “Absolutely zero changes” as a report of unchanged observed behavior—not evidence that the implementation was absent—and kept issue #22 open pending installed-build identity, logs, and diagnostics.
* Committed the changes as `4853700` (`test(usb): pin ZD beta release behavior`) and prepared the pull request **“test(usb): verify beta.4 ZD Ultimate Legend path.”**

**Testing**

* ✅ `git diff --check`
* ✅ `git status --short --branch`
* ⚠️ `swift test --filter RawUSBAdmissionPolicyTests --filter TransportFacadeTests` — Swift 6.3.3 is required but is not installed in the environment.
* ⚠️ `./Scripts/ojd catalog regenerate --check && ./Scripts/ojd check profiles && ./Scripts/ojd check schemas` — the schema environment could not install `jsonschema==4.26.0` because the configured package proxy returned HTTP 403.

 [View task →](https://chatgpt.com/s/cd_6aa9e356be848191a4a77ad2a6b2561e)

### 127841352 — 2026-09-16T00:54:56Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5690385378)

**Follow-up: patching `413d-2104.json` on beta.3 — don't re-sign, edit in place**

A correction to my earlier comment, in case anyone applies the endpoint fix manually on `0.5.0-beta.3` (same pad, 413D:2104, macOS 26.6.2, Apple Silicon):

**TL;DR** — edit the profile file in place and leave the code signature alone. Re-signing the app after the edit is a trap that takes down the virtual-device backend.

**Verified end-to-end on beta.3 + in-place edit (original developer signature intact):**

- discovery and physical input (dpad / face buttons / sticks / analog triggers all parse correctly)
- virtual device output (SDL2/3 compatibility mode, ASTRO C40 identity — confirmed working in-game)
- rumble on OUT endpoint `0x02` (both motors, tested up to 255)

macOS does not enforce sealed-resource validation at launch here, so the modified profile loads fine and the `com.apple.developer.hid.virtual.device` entitlement stays intact.

**Why re-signing breaks things (tested the hard way):**

1. Ad-hoc re-sign after editing the profile drops the app's entitlements → `IOHIDUserDevice` virtual device creation fails (`compatibility activation failed`), so the controller reads input but no game ever sees it.
2. Attempting to re-sign *with* those entitlements fails at launch (LS error 163) — `com.apple.developer.hid.virtual.device` is Apple-restricted and cannot be carried by an ad-hoc signature.
3. Any signature change also revokes the TCC grants (Input Monitoring / Accessibility), so the pad looks completely dead until the app is removed and re-added in both panes.

We're staying on beta.3 for now, so I can't speak to the beta.4 artifact question from the audit above — but the endpoint override itself (`in: 0x81, out: 0x02`) is confirmed working on real hardware via the profile path described here.

### xsyetopz — 2026-09-16T00:58:15Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5690410150)

> **Follow-up: patching `413d-2104.json` on beta.3 — don't re-sign, edit in place**
>
> A correction to my earlier comment, in case anyone applies the endpoint fix manually on `0.5.0-beta.3` (same pad, 413D:2104, macOS 26.6.2, Apple Silicon):
>
> **TL;DR** — edit the profile file in place and leave the code signature alone. Re-signing the app after the edit is a trap that takes down the virtual-device backend.
>
> **Verified end-to-end on beta.3 + in-place edit (original developer signature intact):**
>
> * discovery and physical input (dpad / face buttons / sticks / analog triggers all parse correctly)
> * virtual device output (SDL2/3 compatibility mode, ASTRO C40 identity — confirmed working in-game)
> * rumble on OUT endpoint `0x02` (both motors, tested up to 255)
>
> macOS does not enforce sealed-resource validation at launch here, so the modified profile loads fine and the `com.apple.developer.hid.virtual.device` entitlement stays intact.
>
> **Why re-signing breaks things (tested the hard way):**
>
> 1. Ad-hoc re-sign after editing the profile drops the app's entitlements → `IOHIDUserDevice` virtual device creation fails (`compatibility activation failed`), so the controller reads input but no game ever sees it.
> 2. Attempting to re-sign _with_ those entitlements fails at launch (LS error 163) — `com.apple.developer.hid.virtual.device` is Apple-restricted and cannot be carried by an ad-hoc signature.
> 3. Any signature change also revokes the TCC grants (Input Monitoring / Accessibility), so the pad looks completely dead until the app is removed and re-added in both panes.
>
> We're staying on beta.3 for now, so I can't speak to the beta.4 artifact question from the audit above — but the endpoint override itself (`in: 0x81, out: 0x02`) is confirmed working on real hardware via the profile path described here.

Considering this for `0.5.0-beta.5`. It would be kind of you to join the Discord, so that I could give you tester builds, and get a verification before I may publish another notarized tag release.

### lunarephemera — 2026-09-16T17:40:54Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5701888151)

Noticing input feels less responsive / occasionally stutters in Cyberpunk 2077, compared to what I remember from the same controller on Windows XInput.

Looked at `ReportSender.swift` and found something that might be relevant: the output queue uses `AsyncStream(bufferingPolicy: .bufferingOldest(64))`. Under load that means once the buffer fills, *new* reports get dropped (`.dropped` -> `queueOverflow`) while the *old*, now-stale ones already queued still get processed first. For a real-time gamepad state stream that seems backwards — you'd generally want to keep the newest state and drop stale backlog, not the other way around.

At idle/low load this probably never fills up, which might be why it doesn't show in short synthetic tests, but could plausibly explain intermittent lag/stutter specifically under game load (CPU/GPU busy, more contention on the dispatch queue).

Not 100% sure this is the actual cause of what I'm feeling — could just be normal macOS/Steam Input overhead — but wanted to flag it since `.bufferingNewest` seems like the more correct policy for this kind of live state stream.

Follow-up, found a specific reproduction case: the stutter is most visible during fast stick acceleration (quick flicks), not just randomly.

That actually lines up with the queue theory above — a fast flick generates a burst of many stick-position reports in a very short window, which seems like the most likely way to actually hit that 64-item queue limit. If that's what's happening, `.bufferingOldest` would mean the game briefly plays through a backlog of slightly-stale positions instead of tracking the flick smoothly, which matches what I'm seeing.

### gornobatov — 2026-09-19T23:23:38Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5746085969)

Hi everyone! Joining the discussion regarding the **ZD Ultimate Legend** controller.

My main goal is to get this controller working wirelessly over **2.4 GHz in Xbox mode with smooth analog triggers** on **macOS 26.7 (M5 Pro)**.

Here is what I am experiencing:

### Primary Issue: 2.4 GHz Wireless Mode
* **Direct connection:** Plugging the 2.4 GHz USB dongle directly into macOS yields no input/recognition at all.
* **Via Mayflash Magic NS2 passthrough:** With OJD active, macOS sees the controller as an Xbox Controller (in Cyan/Green modes on NS2). The connection and buttons are stable, **but LT/RT triggers operate strictly as digital (binary 0/1) buttons** instead of smooth analog axes.

### Secondary Test: USB Cable Connection
* I also tested direct USB cable connection as a fallback. While OJD picks it up, the mapping is unstable — after reconnecting or power cycling, **the layout scrambles** (analog sticks get swapped with triggers, and some face buttons stop responding).

Here is my `--headless status` output while connected:

```text
Status:
  identity      : automatic
  backend       : enabled
  status        : automatic, consumer: unknown, targets: canonical 045E:028E,
                  publication: controller=DeviceIdentifier(VID:0x413D PID:0x2104 loc=17825792),
                  session=0, publication=0, target=sdl2-3,
                  last-attempted=48770773198541, last-completed=48770773326291,
                  failure=on (devices=1), recovery=idle

Devices (1):
  XBOX 360 For Windows (VID:16701 PID:8452 XUSB [USB] SN:none)
    protocol=xbox360 endpoints=in:0x81 out:0x2 setConfig=false settleMs=0
    quirks=none backends=userSpaceHID
```

Note the failure=on status during publication for VID:0x413D PID:0x2104.
My priority is getting proper analog LT/RT trigger support over 2.4 GHz (either directly via custom OJD mapping or via NS2). I'm ready to capture any diagnostic dumps, HID reports, or logs you need!

### lunarephemera — 2026-09-20T16:42:41Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5751162499)

Three things, keeping them separate since they're likely unrelated:

**1. Confirmed bug: hardcoded 15% stick deadzone.**

`Events.swift`'s `stickTransfer(for:)` applies a 15% deadzone to every controller by default (`return StickTransfer(deadzone: 0.15, rescalesDeadzone: false)`), with only one hardcoded exception (`0x11C1:0x5600`). This device (413D:2104) doesn't match that exception, so it gets the full 15%.

The actual hardware has effectively zero deadzone — confirmed by raw capture back in July (rests near 0 with no drift, full range on deflection), and the pad is marketed with anti-deadzone TMR sticks. So this 15% is entirely artificial, added by OJD, not something inherited from the controller. It's applied in the shared dispatcher, so it affects every identity equally (not identity-specific).

**2. Sticks feel less responsive than native mode overall**, separate from the deadzone — possibly related, possibly not, hard to separate from #1 without a fix to test against.

**3. Possible regression, direction is confusing so flagging as-is:** almost every identity worked well on macOS 27 (Golden Gate, released Sept 14), but after rolling back to macOS 26 only Apple GameController works reasonably. That's the opposite of what I'd expect (newer OS usually less tested) — wanted to flag in case you're primarily testing against 27 right now and 26 has drifted out of coverage.

### xsyetopz — 2026-09-20T21:01:03Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5752629702)

> **3. Possible regression, direction is confusing so flagging as-is:** almost every identity worked well on macOS 27 (Golden Gate, released Sept 14), but after rolling back to macOS 26 only Apple GameController works reasonably. That's the opposite of what I'd expect (newer OS usually less tested) — wanted to flag in case you're primarily testing against 27 right now and 26 has drifted out of coverage.

Yeah, I'm on macOS 27 now, so testing on 26.x is left for anybody else.

### 127841352 — 2026-09-21T11:52:16Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5760038468)

**macOS 26.x data point (26.6.2) — SDL2/3 identity working well here**

@xsyetopz — since 26.x testing is now community-side, here's a stable reference point from our setup. Also relevant to @lunarephemera's #3, which doesn't match what we see.

**Config:** `0.5.0-beta.3` + the in-place `413d-2104.json` endpoint patch (`in: 0x81, out: 0x02`) described in my earlier comment, original developer signature intact, Apple Silicon, **macOS 26.6.2**.

**Verified end-to-end (repeated, across multiple replugs):**

- discovery + physical input parsing (dpad / face buttons / sticks / analog triggers)
- virtual device publication (SDL2/3 compatibility mode, ASTRO C40 identity)
- in-game input and rumble (rumble arrives at game-sent strength; a direct 255 test is strong)

So at least one 26.x combination — 26.6.2 + beta.3 + SDL2/3 — behaves well here. That suggests the #3 regression, if real, may be tied to a specific 26.x point release, a beta.4 artifact, or a particular failure mode, rather than "26 broadly".

**Questions that would help isolate it:**

- @lunarephemera — which 26.x build showed the regression, and what did "not working reasonably" look like exactly (publication failure, no in-game input, mapping scramble)?
- @gornobatov — the layout-scramble-after-replug on cable: which OJD build was that on? We have not observed it on beta.3 across several replugs on this same pad, so if yours was beta.4 it would line up with the artifact question from the audit above.

To set expectations on scope: our contribution here is the data points and modifications already documented in this thread — the endpoint override applied in-place without re-signing, and the 26.6.2 verification results above. We won't be able to take on regular tester-build verification, but happy to answer any questions about this 26.6.2 setup.

### xsyetopz — 2026-09-21T11:58:24Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5760113478)

> **macOS 26.x data point (26.6.2) — SDL2/3 identity working well here**
>
> [@xsyetopz](https://github.com/xsyetopz) — since 26.x testing is now community-side, here's a stable reference point from our setup. Also relevant to [@lunarephemera](https://github.com/lunarephemera)'s [#3](https://github.com/xsyetopz/OpenJoystickDriver/pull/3), which doesn't match what we see.

Likewise, I will not touch the current OJD beta.5 until my newly ordered Sony DUALSHOCK 3 Wireless and Razer Wolverine Tournament Edition arrive. So I will be in charge of 4 distinct devices physically:

[GameSir-G7 SE (White)](https://gamesir.com/products/gamesir-g7-se)
[Sony DUALSHOCK 3 Wireless (Black)](https://www.amazon.com/clp/B0015AARJI)
[Sony DUALSHOCK 4 Wireless (Berry Blue Edition)](https://www.amazon.ca/DualShock-Wireless-Controller-PlayStation-Berry/dp/B07GQ6R2LR)
[Razer Wolverine (V1) Tournament Edition (Black)](https://www.razer.com/latam-es/console-headsets/razer-wolverine-tournament-edition?srsltid=AU7gw4Xj6I8AjBh_oOJySbsqVQQUKQec5F_aNCgzKP_y83LfHndVs9Dl)

### gornobatov — 2026-09-21T18:11:27Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5765264871)

### Environment & Testing Conditions
- **Test Setup:** Gamepad connected strictly via 2.4GHz Wireless USB Dongle directly into the MacBook Pro USB port (no hubs).
- **macOS Version:** macOS 26.7 (Build 25G229)
- **OpenJoystickDriver Version:** 0.5.0-beta.4 (`com.openjoystickdriver.XboxUSBDevice`, activated & enabled)
- **System State:** Clean system, previous third-party drivers (like USB Overdrive) completely removed.

---

### Hardware Identity (System Report & IOHID)
- **Device Name:** XBOX 360 For Windows Controller
- **Vendor ID (VID):** `0x413d` (16701)
- **Product ID (PID):** `0x2204` (8708)
- **USB Revision:** `0x0100`
- **Speed / Power:** 12 Mbps / 2.5 W (500 mA)

---

### Diagnostic Findings

1. **Missing PID Configuration in OpenJoystickDriver:**
   `grep` search in `/Applications/OpenJoystickDriver.app/` shows that `413d-2104.json` exists in resources, but **`413d-2204.json` is missing**. Because of this, OpenJoystickDriver does not attempt to claim the device upon connection, and macOS routes it to the fallback Apple driver (`com.apple.AppleUserHIDDrivers.dext`).

2. **Continuous Reset / Re-enumeration Loop (`pipe stalled`):**
   `ioreg` loop monitoring shows the dongle repeatedly resetting every ~9–13 seconds (incrementing `IORegistryEntryID` from `0x100001b83` -> `0x100001bab` -> `0x100001bd0` -> `0x100001bf5`).

---

### Kernel Log Trace (`sudo log stream`)

```text
kernel: (IOUSBHostFamily) usb-drd2-port-hs@02100000: AppleUSBHostPort::enumerateDeviceComplete_block_invoke: enumerated 0x413d/2204/0100 (XBOX 360 For Windows Controller / 1) at 12 Mbps
kernel: (IOUSBHostFamily) XBOX 360 For Windows Controller@02100000: IOUSBHostDevice::setConfigurationGated: AppleUSBHostCompositeDevice selected configuration 1
kernel: (IOHIDFamily) VendorID: 0x413d ProductID: 0x2204 VersionNumber: 0x100 ReportDescriptor: Bnr/CQGhAQkCoQAJAxUAJf91CJVAgQIJBZECwMA=
kernel: (IOUSBHostFamily) AppleUSBIORequest: AppleUSBIORequest::complete: device 1 (XBOX 360 For Windows Controller@02100000) endpoint 0x00: status 0xe0005000 (pipe stalled): 0 bytes transferred
kernel: (com.apple.AppleUserHIDDrivers.dext) [AppleUserHIDEventDriver.cpp:116][0x100001bc4] XBOX 360 For Windows Controller usagePage: 1 usage: 6 vid: 16701 pid: 8708
kernel: (IOUSBHostFamily) usb-drd2-port-hs@02100000: AppleUSBHostPort::terminateDevice: destroying 0x413d/2204/0100 (XBOX 360 For Windows Controller): hardware connection lost
kernel: (IOUSBHostFamily) AppleUSBIORequest: AppleUSBIORequest::complete: device 1 (XBOX 360 For Windows Controller@02100000) endpoint 0x82: status 0xe00002ed (transaction error): 0 bytes transferred
kernel: (IOUSBHostFamily) AppleUSBIORequest: AppleUSBIORequest::complete: device 1 (XBOX 360 For Windows Controller@02100000) endpoint 0x83: status 0xe00002ed (transaction error): 0 bytes transferred
```

<details>
<summary>Full Unified Log Output</summary>

```text
2026-09-22 02:11:02.442 Df kernel[0:8c8] (IOUSBHostFamily) usb-drd2-port-hs@02100000: AppleUSBHostPort::createDevice: failed to create device (0xe00002bc)
2026-09-22 02:11:02.442 Df kernel[0:8c8] (IOUSBHostFamily) usb-drd2-port-hs@02100000: AppleUSBHostPort::terminateDevice: destroying 0x413d/2204/0100 (XBOX 360 For Windows Controller): hardware connection lost
2026-09-22 02:11:02.452 E  kernel[0:3e32d] (IOUSBHostFamily) AppleUSBIORequest: AppleUSBIORequest::complete: device 1 (XBOX 360 For Windows Controller@02100000) endpoint 0x82: status 0xe00002ed (transaction error): 0 bytes transferred
2026-09-22 02:11:02.452 E  kernel[0:3e32d] (IOUSBHostFamily) AppleUSBIORequest: AppleUSBIORequest::complete: device 1 (XBOX 360 For Windows Controller@02100000) endpoint 0x83: status 0xe00002ed (transaction error): 0 bytes transferred
2026-09-22 02:11:11.447 Df kernel[0:48758] (IOUSBHostFamily) usb-drd2-port-hs@02100000: AppleUSBHostPort::enumerateDeviceComplete_block_invoke: enumerated 0x413d/2204/0100 (XBOX 360 For Windows Controller / 1) at 12 Mbps
2026-09-22 02:11:11.451 Df kernel[0:48758] (IOUSBHostFamily) XBOX 360 For Windows Controller@02100000: IOUSBHostDevice::setConfigurationGated: AppleUSBHostCompositeDevice selected configuration 1
2026-09-22 02:11:11.465 E  kernel[0:3e32d] (IOUSBHostFamily) AppleUSBIORequest: AppleUSBIORequest::complete: device 1 (XBOX 360 For Windows Controller@02100000) endpoint 0x00: status 0xe0005000 (pipe stalled): 0 bytes transferred
```
</details>

### Hypothesis / Summary:
The driver successfully enumerates the clone receiver (0x413d:0x2204), but right after setting configuration 1, it sends an unsupported setup packet to Endpoint 0x00, triggering a pipe stalled error (0xe0005000). This stalls the clone's microcontroller, causing a hardware watchdog reset ~4 seconds later (hardware connection lost) in an infinite loop.
Everything else is almost working—input endpoints (0x82/0x83) enumerate correctly—so skipping Endpoint 0x00 initialization or gracefully handling the stall for this specific VID:PID quirk should solve the issue.

### Proposed Fixes  @127841352 @xsyetopz
- Add 413d-2204.json mapping (vendorID: 16701, productID: 8708) to OpenJoystickDriverKit.bundle/Contents/Resources/.
- Implement control pipe stall handling / endpoint override on Endpoint 0x00 during initialization for 0x413d devices to prevent the reset loop.

I can provide additional USB dumps, Wireshark captures, or test custom build binaries if needed.

### gornobatov — 2026-09-23T17:37:28Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/22#issuecomment-5799788876)

### Wireshark USB Descriptor Dump & Composite Device Findings

I captured the initial USB Device Descriptor response under Windows 11 using USBPcap/Wireshark.

#### 1. Device Descriptor Trace (EP 0x80 / Control IN)
```json
{
  "usb.idVendor": "0x413d",
  "usb.idProduct": "0x2204",
  "usb.bMaxPacketSize0": "64",
  "usb.bNumConfigurations": "1",
  "usb.endpoint_address": "0x80",
  "usb.usbd_status": "USBD_STATUS_SUCCESS (0x00000000)"
}

```

Windows successfully issues GET DESCRIPTOR Response DEVICE (18 bytes) on Endpoint 0x80 without triggering any pipe stall or watchdog reset.


#### 2. Composite Device Structure (Gamepad + Keyboard + Mouse)
Under Windows, this dongle enumerates as a USB Composite Device:
Interface 0: Gamepad / XInput controller
Interface 1: Standard USB HID Keyboard (used for mapping extra back M-buttons / macros)
Interface 2: Standard USB HID Mouse
Mentioning this in case handling the USB Composite interface descriptors (or isolating the Gamepad interface while letting macOS natively handle the HID Keyboard interface) helps resolve the setup sequence!
