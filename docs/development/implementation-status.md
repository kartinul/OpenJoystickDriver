# Implementation Status

OpenJoystickDriver 0.5 uses a persistent application runtime. The signed app host owns controller
processing, virtual output, login registration, permission state, and the authenticated local RPC
endpoint. No helper daemon or LaunchAgent is packaged.

The beta.4 retirement audit keeps only current consumers: the foreground app owns the runtime and
login item, the authenticated Unix socket remains the typed GUI/CLI service boundary, and the
installed-CLI forwarder prevents an unsigned or stale repository executable from impersonating the
signed client. Historical profile versions and a stored legacy `CompatibilityIdentity` default are
rejected rather than migrated. Current profile formats, RPC payloads, macOS 10.15 platform
fallbacks, hardware/parser fallbacks, and virtual HID profile overrides remain active contracts.
Packaging and source searches confirm that no helper daemon, LaunchAgent plist, daemon launcher,
obsolete GUI registration, or alternate RPC route is shipped, so there is no consumer-free
daemon-era resource to remove.

Controller sessions distinguish physical connection from reversible OJD suspension. Virtual HID
profile transitions use bounded shutdown and retain the actual live profile after a failed
replacement. Complete DualShock 4 Bluetooth reports require a valid CRC. Every driver decodes each report into a
full controller snapshot, stale report progress retires non-neutral OJD output after one second, and recovery
requires a fresh neutral report. Idle input is never consumed as a wake event. Explicit wireless
disconnect neutralizes and suspends one selected session before a bounded Bluetooth close, without
reconnecting or affecting other controllers. GameSir G7 SE startup keeps the mandatory
GIP LED-on command on every USB open and resume, with the latest startup result in diagnostics.

Quit requests share one asynchronous teardown and leave the app stopped. TCC
reopen remains a native system action. Profile-library versions other than the
current schema return a typed unsupported-version error; loading an empty
unsupported library does not rewrite its bytes or discard unknown fields.

The CLI and signed application runtime report authoritative Input Monitoring and Accessibility states for `OpenJoystickDriver.app`. Input Monitoring gates physical controller reads. Accessibility gates virtual-HID publication. OJD never resets TCC.

Controller records remain generated data, while shared protocol behavior remains
in code. Event normalization removes duplicate and contradictory input, and
output dispatch is concurrent across devices and ordered within each virtual device.
Per-device host sessions validate control requests and decode Sony/Nintendo USB
initialization and rumble. Codec tests do not establish signed consumer binding
or hardware delivery; see [wire protocols](wire-protocols.md).
Process and RPC calls have deadlines; buffers and
frames are bounded; current-session logs have typed paths.

`OpenJoystickDriverUSB` exposes one controller-neutral raw USB API. Accessible
vendor-specific interfaces use app-side IOUSBHost. The SwifterKit adapter talks
to the USBDriverKit extension only for an observed DEXT-owned service or a model
covered by OJD's restricted production entitlement. That extension is not a
consumer virtual-controller path. SwifterKit generates its native project at
build time, while this repository authors the USB configuration. Generation and
unsigned native builds are locally validated. Signed activation, macOS approval,
and physical USB delivery require an appropriately provisioned Mac and recorded
evidence.
Issue-by-issue acceptance is recorded in the
[controller issue audit](issue-audit.md).

## Platform Boundaries

On every supported macOS (10.15+), physical HID access uses IOHID and
consumer virtual output uses `IOHIDUserDevice`. Raw USB uses
IOUSBHost/USBDriverKit. `OpenJoystickDriverUSB` hides the
USB host transport from parsers and application callers. OJD does not retain a
libusb fallback.
