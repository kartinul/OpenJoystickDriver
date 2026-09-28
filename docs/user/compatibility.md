# Compatibility Modes

Choose the actual consumer's route. Enumeration alone does not prove input works; every route names its protocol family and evidence
status. Automatic leaves HID controllers to macOS. For every other controller it
publishes one virtual profile chosen only from the controller's declared controls: Xbox
One S Bluetooth (`hid-xbox-one-s-bt`, `045E:02FD`) when its primary controls fit, else
`hid-generic`. Protocol family, the frontmost app, and browser engines do not affect the
choice. Both profiles carry every primary control today, so Automatic always picks Xbox
One S. XID (original Xbox USB) is parsed in userspace and is not HID. DualShock 1/2 used
the PlayStation controller port, not USB HID. A per-controller-model override can pin
either profile regardless of the automatic rule; see below.

Status marks appear only in the support lists below:

- ✅ hardware-verified for the named physical mode and consumer
- ⚠️ source-backed candidate; live consumer evidence still required
- 🧪 reported failure or experimental result; never auto-selected
- 🔬 research-only; no production spoof
- ❌ unavailable

## The Two Profiles And Per-Model Overrides

OJD recognizes exactly two virtual HID profiles. Automatic selection (above) picks
between them from a controller's declared controls; a per-controller-model override
can pin either one instead.

### `hid-xbox-one-s-bt`

Publishes Microsoft's Xbox One S Bluetooth identity `045E:02FD` over a hand-authored
approximation of its report format (Xbox Series Bluetooth-shaped, including the
Consumer Record field and report 2). It is not yet verified byte-exact against genuine
hardware, and whether ordinary HID clients see Guide through it is unconfirmed.

### `hid-generic`

Publishes the OJD generic gamepad `4F4A:4449` "OpenJoystickDriver Generic HID Gamepad":
16 buttons, four stick axes, and two trigger axes, plus a vendor rumble output report.
It is a device-neutral, lossless raw layout; it does not guarantee browser
`mapping: "standard"`.

### Per-model overrides

Pin one of the two profiles for every controller of a given vendor/product ID, or for
one connected device, from the installed CLI:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller virtual set hid-xbox-one-s-bt --vid 0x054C --pid 0x09CC
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller virtual set hid-generic --device <id>
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller virtual reset --vid 0x054C --pid 0x09CC
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller virtual reset --all
```

`reset --all` cannot be combined with a `--vid`/`--pid`/`--device` selector; it clears
every stored override at once. An override is stored per vendor/product ID, not per
connected device, and is rebuilt on service startup; `reset` (without `--all`) returns
that model to automatic selection.

`status` reports each controller's live profile, how it was chosen (`automatic`,
`override`, or `automatic-after-rejecting`), and any stored override, for example:

```
virtual: hid-xbox-one-s-bt (automatic)
override: hid-generic
```

## Controller Support

### ✅ Hardware-Backed Paths

- GameSir G7 SE through GIP, including four-motor output
- SCUF Envision Pro wired `2E95:434D` report-6 controls recorded in issue 33:
  sticks, independent triggers, buttons 1–10, and hat
- Flydigi Vader 5S through GIP; the record sets USB configuration 1 before claim
- DualShock 4 USB and Bluetooth input, rumble, and RGB lightbar
- Xbox 360 USB parsing; individual model coverage still varies

### 🚧 Source-Backed Paths Needing Hardware Checks

- GameSir G7 Pro USB `3537:1003`, `105D`, `105E`, `109B`, `109C`, and `10BA`
  with standard XInput gameplay plus the vendor telemetry stream; documented
  dock brightness becomes available only after the configuration-ready stream
- GameSir Cyclone 2 enhanced HID `3537:0575`, `100B`, and `1053`, including
  heartbeat, extras, battery, motion, two-motor rumble, and solid RGB/brightness
- GameSir G7 Pro 8K PC enhanced HID `3537:10C5`–`10C8`, including heartbeat,
  extras, battery, motion, two-motor rumble, and home-ring color/brightness
- DualShock 3 USB and Bluetooth input, operational-mode setup, two motors, and player LEDs
- DualSense USB and Bluetooth input, compatible rumble, player LEDs, and RGB lightbar
- Steam Controller wired and wireless input, lifecycle, trackpad haptics, and LED brightness
- Switch Pro USB and Bluetooth input, startup reports, HD rumble, and player LEDs
- Linux xpad-derived Xbox records that have not been tested on their matching hardware

### ⚠️ Fallback And Consumer Limits

- Generic HID maps descriptor-defined controls but cannot infer vendor protocols.
- Restricted raw-USB models require the signed DriverKit extension; accessible vendor-specific devices use direct IOUSBHost.
- Automatic ignores protocol family; `hid-generic` is used only when Xbox One S cannot carry a controller's primary controls.
- Browser engines may map the same identity differently. Enumeration, input, reconnect, and output are separate claims.
- Exact consumer-bind observations, failures, and hardware limits are in [consumer-binding evidence](../testing/consumer-binding.md).

## Browser Gamepad API Testing

**ControllerTest.io is the canonical manual browser test site**:

**<https://controllertest.io/>**

Run each matrix row from a clean browser document and record the exact browser
version, Gamepad `id`, mapping, slot/count, every button and axis, timestamps,
disconnect/reconnect behavior, and exposed actuator fields. One browser's result does not establish another's support;
neither enumeration nor rumble alone proves support.
Generic HID is expected to use `mapping: n/a`, with sticks on axes 0–3,
analog LT/RT pressure on axes 4–5, and digital controls on B0–B5 and B8–B17.
Digital-only trigger sources use full-scale values on axes 4–5. It intentionally
does not expose B6/B7 or a D-pad axis.
See the [browser test protocol and reported observations](../testing/browser-gamepad-api.md).

### ❌ Not Implemented

Bluetooth support does not extend to arbitrary controllers. The ASTRO C40 PS4
mode `9886:0025` is experimental research only: the repository lacks a
complete descriptor, feature/calibration, input, and output contract, so it is
not a supported spoof route.

OJD no longer publishes a per-family spoofed identity (a distinct Xbox 360, Switch
Pro, or DualShock/DualSense virtual device chosen for a target consumer): only the
two profiles above exist, picked by declared controls or a per-model override. The
table below is kept as a historical record of consumer-bind results gathered while
those per-family identities existed; it does not describe a selectable route today.
Browser reports remain per-engine because Blink, WebKit, and Gecko can map the same
family differently.

| Physical family/mode | SDL/HIDAPI | Apple GameController |
| --- | --- | --- |
| Xbox GIP, exact GameSir G7 SE mode | ⚠️ Series `045E:0B13`; custom HIDAPI xboxone BLE idle rest `0x8000`→0; no physical button; not Steam | ✅ Xbox Series `045E:0B13` |
| Xbox GIP, other modes | ⚠️ first-party Series unless a reported failure tuple exists | ⚠️ Xbox Series profile |
| Xbox 360 physical family | ⚠️ `sdl2-3` (Microsoft `045E:028E`) | 🔬 Series BT not used for 360 |
| XInputHID/XUSB wire protocol | ❌ no macOS emulation claim | ❌ no macOS emulation claim |
| Xbox One Bluetooth `045E:02FD` | 🧪 BT1/BT2 experiments reported no SDL input; Automatic now publishes this ID, consumer binding not yet hardware-verified | 🔬 not yet verified |
| Nintendo Switch Pro | ⚠️ `switchpro` USB packer; explicit G7 SE publish: custom HIDAPI switchpro `SDL_OpenGamepad` ok, not Steam | ⚠️ `switchpro`; explicit G7 SE `supportsHIDDevice` yes |
| PlayStation DS4/DS5 | ⚠️ `dualshock4` / `dualsense`; explicit G7 SE publish: custom HIDAPI ps4/ps5 `SDL_OpenGamepad` ok, not Steam | ⚠️ first-party packers; explicit G7 SE `supportsHIDDevice` yes |
| Other | 🔬 no cross-family spoof | 🔬 no cross-family spoof |

Automatic does not use this table; see the declared-controls rule at the top. The Xbox One S
row records earlier spoof experiments, not the current `hid-xbox-one-s-bt` profile.

## Apple GameController Support

Use live detection by `GCController.supportsHIDDevice` and a hardware test to
determine whether the active virtual controller works with
GameController.framework. There is no separate identity to select for this test:
the OJD probe checks whichever of the two profiles is currently published, and
confirms whether macOS created `GCXboxGamepad`, `buttonShare`, and any paddle
inputs. Whether `hid-xbox-one-s-bt`'s `045E:02FD` is itself recognized as an Xbox
family device by GameController.framework is not yet hardware-verified. Browser Gamepad API results are separate:
a browser may omit Share even when native GameController.framework exposes it.
The private current-system mapping catalog is optional. A missing pair does not
prove incompatibility. See
[Xbox fallback identity evidence](../development/xbox-identities.md).

## USB DriverKit Extension

`OpenJoystickDriverUSB` selects between direct app-side IOUSBHost and
`com.openjoystickdriver.XboxUSBDevice`. The DEXT is used only for an observed
DEXT-owned service or an Apple-entitled Microsoft Xbox GIP model; it is not
the generic path for every controller. OJD does not use libusb or publish a
second controller. Development and production DEXT matching are both limited
to the VID/PID pairs in OJD's Apple-issued entitlement. Accessible third-party
controllers, including the GameSir G7 SE, use direct app-side IOUSBHost instead.

Run the shared CLI self-test even while a virtual controller is published:

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless test 5
```

The self-test checks the current virtual-HID backend for the selected controller.
For a controller with a stored override, that backend is rebuilt from the override
after service startup. For a controller selected automatically, the backend follows
declared controls at publication and is not persisted; the self-test therefore does
not prove a universally persistent backend. The active backend uses
`IOHIDUserDevice` on every supported macOS.
A self-test does not prove USB
system-extension approval, signing validity, or behavior on a different macOS
version or hardware.

## App Rumble

OJD forwards app rumble only when the virtual report and physical parser agree on an output format. `hid-xbox-one-s-bt` accepts Xbox One report ID `3`. `hid-generic` accepts OJD compact report `0x4F` and the short Xbox 360 `08` rumble packet.

Xbox 360 and DualShock 4 controllers use their two main motors. GIP controllers may also use trigger motors. DualShock 4 ignores trigger values.

## Input Integrity

Before a parsed packet reaches an output backend, OJD reduces its events to the packet's final net controller state. It drops duplicate transitions and contradictory press/release pulses that end unchanged. It also emits one canonical D-pad direction, rejects non-finite analog values by retaining the prior component, and clamps sticks to `-1...1` and triggers to `0...1`. This integrity gate does not add a timing delay or a new global deadzone. Protocol-specific deadzones remain in their parsers.

The normalized batch is delivered to one persistent virtual-HID device per
physical controller. Focusing or opening a consumer does not replace that
device, so SDL hot-plug state remains stable. Automatic selection is not
persisted; only a per-model override is.

## Manual Checks

Before marking a mapping verified, check the exact app and mode:

1. SDL2/3: `A2` and `A5` idle at zero, D-pad releases cleanly.
1. Parsec macOS to Windows: D-pad and A/B/X/Y stay stable on the Windows host.
1. Rumble: app output report reaches the physical controller if the controller supports rumble.
