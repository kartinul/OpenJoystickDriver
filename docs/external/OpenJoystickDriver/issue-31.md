# #31: WR-007 (11c1:5600): HID mapping and Apple GameController tester build

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/31
- **State:** OPEN
- **Author:** arthurknowles34-a11y
- **Created:** 2026-09-05T16:59:02Z
- **Updated:** 2026-09-15T00:32:50Z
- **Closed:** —
- **Labels:** —

## Report

## Hardware

- Controller: WR-007 / FCC ID 2AZFAWR-007
- Receiver USB identity: `11c1:5600` (decimal `4545:22016`)
- USB strings: `HORI CO.,LTD.` / `Controller`
- Transport: wireless controller through its USB HID receiver
- Host used for the report: Apple silicon (M4), macOS 26.6.2
- OJD installed build: 0.5.0-beta.3

The receiver has one HID interface with 9-byte input reports and a 4-byte output report. The input descriptor exposes ordinary HID controls; no raw-USB/GIP interface is present.

## Observed input layout

Neutral report: `00 00 0f 80 80 80 80 00 00`

- Sparse button usages: A=1, B=2, X=4, Y=5, LB=7, RB=8, View=11, Menu=12, L3=14, R3=15
- D-pad: hat switch, neutral `0x0f`
- Left stick: X/Y
- Right stick: Z/Rz
- LT/RT analog: Simulation Controls Accelerator/Brake
- Wireless Guide button does not produce an input report
- The receiver accepts its advertised four-byte output report, but individual and maximum-value channel probes produced no motor or LED response. Physical rumble must remain unavailable pending an evidenced vendor initialization protocol.

## Installed-beta behavior

With `generic-hid`, OJD detects the receiver and its virtual self-test passes:

- backend: on, devices=1
- self-test: report count > 0, passed

However, 0.5.0-beta.3's generic parser interprets the sparse button usages incorrectly. More importantly, the App Store build of Resident Evil 4 1.0.7 declares `GCSupportedGameControllers = ExtendedGamepad` and links GameController.framework; it receives no input from the generic HID identity.

Selecting `apple-gamecontroller` is persisted, but the beta's compatibility policy disables the virtual backend for this GenericHID-family device:

- identity: apple-gamecontroller
- backend enabled
- runtime status: off
- virtual self-test: failed, zero reports

Switching back to `generic-hid` restores the backend and passing self-test.

## Source change prepared locally

A local branch based on commit `f42ee34` contains:

- canonical catalog override for `11c1:5600`
- device-specific GenericHID mapping for its sparse buttons, Z/Rz right stick, and Accelerator/Brake triggers
- a 2% rescaled stick deadzone for fine analog motion
- explicit and automatic availability of the Apple GameController/Xbox Series-compatible identity for this tuple
- focused parser, analog-transfer, catalog-discovery, and compatibility-policy tests

Validation result: **873 tests in 112 suites passed**, plus catalog/profile/script/Swift-structure checks. Local execution of the changed virtual-gamepad path is blocked because ad-hoc builds do not receive Apple's restricted `com.apple.developer.hid.virtual.device` entitlement.

## Request

Please advise on contributing the prepared patch and, if acceptable, provide an entitlement-signed tester build so the `apple-gamecontroller` path can be hardware-tested in Resident Evil 4. Input support should remain distinct from rumble: input is packet-backed; physical rumble is currently unavailable.

## Comments

### arthurknowles34-a11y — 2026-09-05T17:18:43Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/31#issuecomment-5553476073)

Follow-up after a runtime-path audit: the first implementation correctly added the tuple-specific policy, but the two concrete dispatch adapters were still calling the older subfamily-only overload. That has now been corrected in a separate local commit, with explicit and automatic WR-007 runtime exposure tests. Focused runtime tests pass, and the updated full suite passes: **875 tests in 112 suites**. The three clean format-patches are ready locally.

### arthurknowles34-a11y — 2026-09-05T17:19:35Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/31#issuecomment-5553481203)

Additional live evidence: `OpenJoystickDriverGameControllerProbe` reports both `11C1:5600 "Controller" transport=USB gamecontroller=no` and the beta's `4F4A:4449 "OpenJoystickDriver Generic HID Gamepad" transport=Virtual gamecontroller=no`; `Initial controllers: 0`. The installed Developer ID build has hardened runtime and the virtual-HID entitlement, while local builds cannot obtain that restricted entitlement. Attaching to the signed process is also denied by macOS, so an updated maintainer-signed build is required for the corrected runtime path.

### arthurknowles34-a11y — 2026-09-05T17:20:15Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/31#issuecomment-5553485412)

The complete controller + runtime diff is below, with author metadata removed. It excludes the independent permission-state commit. Apply from the repository root with `git apply`.

<details>
<summary>WR-007 implementation diff</summary>

```diff
diff --git a/Resources/ControllerOverrides/11c1/11c1-5600.json b/Resources/ControllerOverrides/11c1/11c1-5600.json
new file mode 100644
index 0000000..74ec163
--- /dev/null
+++ b/Resources/ControllerOverrides/11c1/11c1-5600.json
@@ -0,0 +1,14 @@
+{
+  "$schema": "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/controller-override.schema.json",
+  "operation": "add",
+  "record": {
+    "$schema": "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/controller.schema.json",
+    "vendor_id": 4545,
+    "product_id": 22016,
+    "transport": "hid",
+    "protocol": {
+      "driver": "GenericHID",
+      "variant": "genericHID"
+    }
+  }
+}
diff --git a/Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/Dispatcher.swift b/Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/Dispatcher.swift
index a5b5cb4..902db25 100644
--- a/Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/Dispatcher.swift
+++ b/Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/Dispatcher.swift
@@ -360,8 +360,9 @@ public final class UserSpaceOutputDispatcher: CompatibilityUserSpaceOutputDispat

     guard lifecycle.isOpen else { return }

+    let stickTransfer = Self.stickTransfer(for: identifier)
     let primaryReport = activeEntry.inputReportState.update { state in
-      for event in events { applyEvent(event, deadzone: 0.15, state: &state) }
+      for event in events { applyEvent(event, stickTransfer: stickTransfer, state: &state) }
     }
     let secondaryReports =
       emitsXboxGuideReport ? events.compactMap { xboxGuideReport(for: $0) } : []
diff --git a/Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/Events.swift b/Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/Events.swift
index f302638..e41ec01 100644
--- a/Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/Events.swift
+++ b/Sources/OpenJoystickDriverKit/Output/Backends/UserSpaceOutputDispatcher/Events.swift
@@ -1,18 +1,34 @@
 import Foundation

 extension UserSpaceOutputDispatcher {
+  struct StickTransfer: Equatable, Sendable {
+    let deadzone: Float
+    let rescalesDeadzone: Bool
+  }
+
+  static func stickTransfer(for identifier: DeviceIdentifier) -> StickTransfer {
+    if identifier.vendorID == 0x11C1 && identifier.productID == 0x5600 {
+      return StickTransfer(deadzone: 0.02, rescalesDeadzone: true)
+    }
+    return StickTransfer(deadzone: 0.15, rescalesDeadzone: false)
+  }
+
   // MARK: - Event application (called inside reportLock.withLock)

-  func applyEvent(_ event: ControllerEvent, deadzone: Float, state: inout VirtualGamepadState) {
+  func applyEvent(
+    _ event: ControllerEvent,
+    stickTransfer: StickTransfer,
+    state: inout VirtualGamepadState
+  ) {
     switch event {
     case .buttonPressed(let btn): if let bit = buttonBit(for: btn) { state.buttons |= (1 << bit) }
     case .buttonReleased(let btn): if let bit = buttonBit(for: btn) { state.buttons &= ~(1 << bit) }
     case .leftStickChanged(let x, let y):
-      state.leftStickX = axisValue(x, deadzone: deadzone)
-      state.leftStickY = axisValue(y, deadzone: deadzone)
+      state.leftStickX = Self.axisValue(x, transfer: stickTransfer)
+      state.leftStickY = Self.axisValue(y, transfer: stickTransfer)
     case .rightStickChanged(let x, let y):
-      state.rightStickX = axisValue(x, deadzone: deadzone)
-      state.rightStickY = axisValue(y, deadzone: deadzone)
+      state.rightStickX = Self.axisValue(x, transfer: stickTransfer)
+      state.rightStickY = Self.axisValue(y, transfer: stickTransfer)
     case .leftTriggerChanged(let v): state.leftTrigger = Int16(v.clamped(to: 0...1) * 32_767)
     case .rightTriggerChanged(let v): state.rightTrigger = Int16(v.clamped(to: 0...1) * 32_767)
     case .dpadChanged(let dir):
@@ -59,10 +75,13 @@ extension UserSpaceOutputDispatcher {

   // MARK: - Axis + hat helpers

-  func axisValue(_ v: Float, deadzone: Float) -> Int16 {
+  static func axisValue(_ v: Float, transfer: StickTransfer) -> Int16 {
     let clamped = v.clamped(to: -1...1)
-    guard abs(clamped) > deadzone else { return 0 }
-    return Int16(clamped * 32_767)
+    let magnitude = abs(clamped)
+    guard magnitude > transfer.deadzone else { return 0 }
+    guard transfer.rescalesDeadzone else { return Int16(clamped * 32_767) }
+    let rescaled = (magnitude - transfer.deadzone) / (1 - transfer.deadzone)
+    return Int16(copysignf(rescaled, clamped) * 32_767)
   }

   func hatValue(for direction: DpadDirection) -> GamepadHIDDescriptor.Hat {
diff --git a/Sources/OpenJoystickDriverKit/Output/Profiles/Compatibility.swift b/Sources/OpenJoystickDriverKit/Output/Profiles/Compatibility.swift
index 2e9bc81..6defe84 100644
--- a/Sources/OpenJoystickDriverKit/Output/Profiles/Compatibility.swift
+++ b/Sources/OpenJoystickDriverKit/Output/Profiles/Compatibility.swift
@@ -98,12 +98,20 @@ public enum CompatibilityProfileAvailabilityDecision: Equatable, Sendable {

 /// Pure Kit-owned policy for physical-family to explicit virtual-identity compatibility.
 public enum CompatibilityProfileAvailabilityPolicy {
+  private static let wr007VendorID: UInt16 = 0x11C1
+  private static let wr007ProductID: UInt16 = 0x5600
+
   /// Evaluates one explicit identity for a connected physical device.
   public static func decision(
     for device: ApplicationServiceDeviceDescription,
     identity: CompatibilityIdentity
   ) -> CompatibilityProfileAvailabilityDecision {
-    decision(for: AutomaticCompatibilityResolver.subfamily(for: device), identity: identity)
+    if device.vendorID == wr007VendorID, device.productID == wr007ProductID,
+      identity == .appleGameController
+    {
+      return .available
+    }
+    return decision(for: AutomaticCompatibilityResolver.subfamily(for: device), identity: identity)
   }

   /// Evaluates one explicit identity against one physical protocol subfamily.
@@ -160,6 +168,18 @@ public struct CompatibilityEvidenceRecord: Equatable, Sendable {

 public enum CompatibilityEvidenceCatalog {
   public static let records: [CompatibilityEvidenceRecord] = [
+    CompatibilityEvidenceRecord(
+      vendorID: 0x11C1,
+      productID: 0x5600,
+      subfamily: .other,
+      physicalTransport: "wired",
+      physicalMode: "generichid",
+      connection: "usb",
+      consumer: .unknown,
+      identity: .appleGameController,
+      evidence: .sourceBacked,
+      reason: .selectedCatalogTuple
+    ),
     CompatibilityEvidenceRecord(
       vendorID: 0x045E,
       productID: 0x02FD,
diff --git a/Sources/OpenJoystickDriverKit/Protocol/Parsers/GenericHIDParser.swift b/Sources/OpenJoystickDriverKit/Protocol/Parsers/GenericHIDParser.swift
index 8c9a2fb..f4a8a71 100644
--- a/Sources/OpenJoystickDriverKit/Protocol/Parsers/GenericHIDParser.swift
+++ b/Sources/OpenJoystickDriverKit/Protocol/Parsers/GenericHIDParser.swift
@@ -7,6 +7,7 @@ import Foundation
 public final class GenericHIDParser: InputParser, HIDElementValueParser, @unchecked Sendable {
   private static let buttonUsagePage: UInt32 = 0x09
   private static let genericDesktopUsagePage: UInt32 = 0x01
+  private static let simulationControlsUsagePage: UInt32 = 0x02
   private static let usageX: UInt32 = 0x30
   private static let usageY: UInt32 = 0x31
   private static let usageZ: UInt32 = 0x32
@@ -14,6 +15,13 @@ public final class GenericHIDParser: InputParser, HIDElementValueParser, @unchec
   private static let usageRy: UInt32 = 0x34
   private static let usageRz: UInt32 = 0x35
   private static let usageHatSwitch: UInt32 = 0x39
+  private static let usageAccelerator: UInt32 = 0xC4
+  private static let usageBrake: UInt32 = 0xC5
+
+  private enum AxisLayout {
+    case standard
+    case wr007
+  }

   private let identifier: DeviceIdentifier
   private let stateLock = NSLock()
@@ -22,10 +30,13 @@ public final class GenericHIDParser: InputParser, HIDElementValueParser, @unchec
   private var leftY: Float = 0
   private var rightX: Float = 0
   private var rightY: Float = 0
+  private let axisLayout: AxisLayout

   /// Creates a new GenericHIDParser for the given device identifier.
   public init(identifier: DeviceIdentifier) {
     self.identifier = identifier
+    axisLayout =
+      identifier.vendorID == 0x11C1 && identifier.productID == 0x5600 ? .wr007 : .standard
     print("[GenericHIDParser] Unrecognized controller \(identifier), using HID descriptors")
   }

@@ -41,13 +52,14 @@ public final class GenericHIDParser: InputParser, HIDElementValueParser, @unchec
       switch value.usagePage {
       case Self.buttonUsagePage: return parseButton(value)
       case Self.genericDesktopUsagePage: return parseGenericDesktop(value)
+      case Self.simulationControlsUsagePage: return parseSimulationControl(value)
       default: return []
       }
     }
   }

   private func parseButton(_ value: HIDElementValue) -> [ControllerEvent] {
-    guard let button = Self.button(for: value.usage) else { return [] }
+    guard let button = button(for: value.usage) else { return [] }
     let isPressed = value.integerValue != 0
     let wasPressed = pressedButtons.contains(button)
     guard isPressed != wasPressed else { return [] }
@@ -67,19 +79,41 @@ public final class GenericHIDParser: InputParser, HIDElementValueParser, @unchec
     case Self.usageY:
       leftY = -Self.normalizedAxis(value)
       return [.leftStickChanged(x: leftX, y: leftY)]
-    case Self.usageZ: return [.leftTriggerChanged(Self.normalizedTrigger(value))]
+    case Self.usageZ:
+      if axisLayout == .wr007 {
+        rightX = Self.normalizedAxis(value)
+        return [.rightStickChanged(x: rightX, y: rightY)]
+      }
+      return [.leftTriggerChanged(Self.normalizedTrigger(value))]
     case Self.usageRx:
       rightX = Self.normalizedAxis(value)
       return [.rightStickChanged(x: rightX, y: rightY)]
     case Self.usageRy:
       rightY = -Self.normalizedAxis(value)
       return [.rightStickChanged(x: rightX, y: rightY)]
-    case Self.usageRz: return [.rightTriggerChanged(Self.normalizedTrigger(value))]
+    case Self.usageRz:
+      if axisLayout == .wr007 {
+        rightY = -Self.normalizedAxis(value)
+        return [.rightStickChanged(x: rightX, y: rightY)]
+      }
+      return [.rightTriggerChanged(Self.normalizedTrigger(value))]
     case Self.usageHatSwitch: return [.dpadChanged(Self.hatDirection(value))]
     default: return []
     }
   }

+  private func parseSimulationControl(_ value: HIDElementValue) -> [ControllerEvent] {
+    guard axisLayout == .wr007 else { return [] }
+    switch value.usage {
+    case Self.usageAccelerator:
+      return [.leftTriggerChanged(Self.normalizedTrigger(value))]
+    case Self.usageBrake:
+      return [.rightTriggerChanged(Self.normalizedTrigger(value))]
+    default:
+      return []
+    }
+  }
+
   private static func normalizedAxis(_ value: HIDElementValue) -> Float {
     let span = value.logicalMaximum - value.logicalMinimum
     guard span > 0 else { return 0 }
@@ -100,7 +134,24 @@ public final class GenericHIDParser: InputParser, HIDElementValueParser, @unchec
     return [.north, .northEast, .east, .southEast, .south, .southWest, .west, .northWest][position]
   }

-  private static func button(for usage: UInt32) -> Button? {
+  private func button(for usage: UInt32) -> Button? {
+    if axisLayout == .wr007 {
+      // The WR-007 advertises 15 sequential button usages, but its physical
+      // Xbox-style controls occupy a sparse subset of those usages.
+      return [
+        1: .a,
+        2: .b,
+        4: .x,
+        5: .y,
+        7: .leftBumper,
+        8: .rightBumper,
+        11: .back,
+        12: .start,
+        14: .leftStick,
+        15: .rightStick,
+      ][usage]
+    }
+
     let standard: [Button] = [
       .a, .b, .x, .y, .leftBumper, .rightBumper, .back, .start, .leftStick, .rightStick, .guide
     ]
diff --git a/Sources/OpenJoystickDriverKit/Resources/Controllers/11c1/11c1-5600.json b/Sources/OpenJoystickDriverKit/Resources/Controllers/11c1/11c1-5600.json
new file mode 100644
index 0000000..bce26cb
--- /dev/null
+++ b/Sources/OpenJoystickDriverKit/Resources/Controllers/11c1/11c1-5600.json
@@ -0,0 +1,10 @@
+{
+  "$schema": "https://raw.githubusercontent.com/xsyetopz/OpenJoystickDriver/main/Resources/Schemas/controller.schema.json",
+  "vendor_id": 4545,
+  "product_id": 22016,
+  "transport": "hid",
+  "protocol": {
+    "driver": "GenericHID",
+    "variant": "genericHID"
+  }
+}
diff --git a/Tests/OpenJoystickDriverKitTests/Integration/HIDProfileDiscoveryTests.swift b/Tests/OpenJoystickDriverKitTests/Integration/HIDProfileDiscoveryTests.swift
index fc460ea..66bcb71 100644
--- a/Tests/OpenJoystickDriverKitTests/Integration/HIDProfileDiscoveryTests.swift
+++ b/Tests/OpenJoystickDriverKitTests/Integration/HIDProfileDiscoveryTests.swift
@@ -13,6 +13,7 @@ struct HIDProfileDiscoveryTests {
     #expect(identifiers.contains("10462:4418"))
     #expect(identifiers.contains("1356:1476"))
     #expect(identifiers.contains("1406:8201"))
+    #expect(identifiers.contains("4545:22016"))
     #expect(!identifiers.contains("1133:49693"))
     #expect(!identifiers.contains("5426:2627"))
   }
diff --git a/Tests/OpenJoystickDriverKitTests/Output/Backends/CompatibilityProfileAvailabilityTests.swift b/Tests/OpenJoystickDriverKitTests/Output/Backends/CompatibilityProfileAvailabilityTests.swift
index 85ddfd5..8599cf6 100644
--- a/Tests/OpenJoystickDriverKitTests/Output/Backends/CompatibilityProfileAvailabilityTests.swift
+++ b/Tests/OpenJoystickDriverKitTests/Output/Backends/CompatibilityProfileAvailabilityTests.swift
@@ -90,6 +90,30 @@ struct CompatibilityProfileAvailabilityTests {
     )
   }

+  @Test func wr007CanUseXboxSeriesCompatibleIdentity() {
+    let device = ApplicationServiceDeviceDescription(
+      name: "WR-007",
+      vendorID: 0x11C1,
+      productID: 0x5600,
+      parser: "GenericHID",
+      connection: "USB",
+      serialNumber: nil,
+      protocolVariant: .genericHID
+    )
+
+    #expect(
+      CompatibilityProfileAvailabilityPolicy.decision(
+        for: device,
+        identity: .appleGameController
+      ) == .available
+    )
+    #expect(
+      CompatibilityProfileAvailabilityPolicy.decision(for: device, identity: .sdl2_3)
+        == .unavailable(reason: .xbox360IdentityRequiresXbox360Family)
+    )
+    #expect(AutomaticCompatibilityResolver.resolve(for: device).identity == .appleGameController)
+  }
+
   @Test func automaticMustBeResolvedBeforePolicyEvaluation() {
     let decision = CompatibilityProfileAvailabilityPolicy.decision(
       for: .xbox360,
diff --git a/Tests/OpenJoystickDriverKitTests/Output/Backends/UserSpaceOutputDispatcher/WR007AnalogOutputTests.swift b/Tests/OpenJoystickDriverKitTests/Output/Backends/UserSpaceOutputDispatcher/WR007AnalogOutputTests.swift
new file mode 100644
index 0000000..ff6885b
--- /dev/null
+++ b/Tests/OpenJoystickDriverKitTests/Output/Backends/UserSpaceOutputDispatcher/WR007AnalogOutputTests.swift
@@ -0,0 +1,27 @@
+import Testing
+
+@testable import OpenJoystickDriverKit
+
+struct WR007AnalogOutputTests {
+  @Test func usesSmallRescaledDeadzoneForFineStickMovement() {
+    let identifier = DeviceIdentifier(vendorID: 0x11C1, productID: 0x5600)
+    let transfer = UserSpaceOutputDispatcher.stickTransfer(for: identifier)
+
+    #expect(transfer.deadzone == 0.02)
+    #expect(transfer.rescalesDeadzone)
+    #expect(UserSpaceOutputDispatcher.axisValue(0.01, transfer: transfer) == 0)
+    #expect(UserSpaceOutputDispatcher.axisValue(0.03, transfer: transfer) == 334)
+    #expect(UserSpaceOutputDispatcher.axisValue(0.5, transfer: transfer) == 16_049)
+    #expect(UserSpaceOutputDispatcher.axisValue(1, transfer: transfer) == 32_767)
+    #expect(UserSpaceOutputDispatcher.axisValue(-1, transfer: transfer) == -32_767)
+  }
+
+  @Test func leavesExistingControllerTransferUnchanged() {
+    let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x0B13)
+
+    #expect(
+      UserSpaceOutputDispatcher.stickTransfer(for: identifier)
+        == UserSpaceOutputDispatcher.StickTransfer(deadzone: 0.15, rescalesDeadzone: false)
+    )
+  }
+}
diff --git a/Tests/OpenJoystickDriverKitTests/Protocol/Parsers/GenericHIDParserTests.swift b/Tests/OpenJoystickDriverKitTests/Protocol/Parsers/GenericHIDParserTests.swift
index 74fa293..e50c6b0 100644
--- a/Tests/OpenJoystickDriverKitTests/Protocol/Parsers/GenericHIDParserTests.swift
+++ b/Tests/OpenJoystickDriverKitTests/Protocol/Parsers/GenericHIDParserTests.swift
@@ -66,6 +66,73 @@ struct GenericHIDParserTests {
     #expect(try parser.parse(data: Data([1, 2, 3])).isEmpty)
   }

+  @Test func mapsWR007RightStickAndAnalogTriggersFromItsDescriptorUsages() {
+    let parser = GenericHIDParser(
+      identifier: DeviceIdentifier(vendorID: 0x11C1, productID: 0x5600)
+    )
+
+    #expect(
+      parser.parse(elementValue: axis(usage: 0x32, integer: 255)) == [
+        .rightStickChanged(x: 1, y: 0)
+      ]
+    )
+    #expect(
+      parser.parse(elementValue: axis(usage: 0x35, integer: 0)) == [
+        .rightStickChanged(x: 1, y: 1)
+      ]
+    )
+    #expect(
+      parser.parse(
+        elementValue: value(page: 0x02, usage: 0xC4, minimum: 0, maximum: 255, integer: 64)
+      ) == [.leftTriggerChanged(Float(64) / 255)]
+    )
+    #expect(
+      parser.parse(
+        elementValue: value(page: 0x02, usage: 0xC5, minimum: 0, maximum: 255, integer: 192)
+      ) == [.rightTriggerChanged(Float(192) / 255)]
+    )
+  }
+
+  @Test func mapsWR007SparsePhysicalButtonUsages() {
+    let parser = GenericHIDParser(
+      identifier: DeviceIdentifier(vendorID: 0x11C1, productID: 0x5600)
+    )
+    let expected: [(UInt32, Button)] = [
+      (1, .a),
+      (2, .b),
+      (4, .x),
+      (5, .y),
+      (7, .leftBumper),
+      (8, .rightBumper),
+      (11, .back),
+      (12, .start),
+      (14, .leftStick),
+      (15, .rightStick),
+    ]
+
+    for (usage, button) in expected {
+      #expect(
+        parser.parse(
+          elementValue: value(page: 0x09, usage: usage, minimum: 0, maximum: 1, integer: 1)
+        ) == [.buttonPressed(button)]
+      )
+    }
+
+    for unusedUsage: UInt32 in [3, 6, 9, 10, 13] {
+      #expect(
+        parser.parse(
+          elementValue: value(
+            page: 0x09,
+            usage: unusedUsage,
+            minimum: 0,
+            maximum: 1,
+            integer: 1
+          )
+        ).isEmpty
+      )
+    }
+  }
+
   private func axis(usage: UInt32, integer: Int) -> HIDElementValue {
     value(page: 0x01, usage: usage, minimum: 0, maximum: 255, integer: integer)
   }
diff --git a/Sources/OpenJoystickDriver/Runtime/RPC/AutomaticUserSpaceOutputDispatcher.swift b/Sources/OpenJoystickDriver/Runtime/RPC/AutomaticUserSpaceOutputDispatcher.swift
index 66dbffd..df57373 100644
--- a/Sources/OpenJoystickDriver/Runtime/RPC/AutomaticUserSpaceOutputDispatcher.swift
+++ b/Sources/OpenJoystickDriver/Runtime/RPC/AutomaticUserSpaceOutputDispatcher.swift
@@ -526,10 +526,10 @@ final class AutomaticUserSpaceOutputDispatcher: CompatibilityUserSpaceOutputDisp
       })
     else { return false }
     let ownership = await ownershipProvider(identifier)
-    let profileAvailable = CompatibilityProfileAvailabilityPolicy.isAvailable(
-      identity,
-      for: AutomaticCompatibilityResolver.resolve(for: description).subfamily
-    )
+    let profileAvailable = CompatibilityProfileAvailabilityPolicy.decision(
+      for: description,
+      identity: identity
+    ).isAvailable
     return ControllerExposureDecision.decide(
       ownership: ownership,
       intent: .automatic(resolvedIdentity: identity),
diff --git a/Sources/OpenJoystickDriver/Runtime/RPC/CompatibilityUserSpaceOutputDispatchingAdapter.swift b/Sources/OpenJoystickDriver/Runtime/RPC/CompatibilityUserSpaceOutputDispatchingAdapter.swift
index 14bb121..68c7f06 100644
--- a/Sources/OpenJoystickDriver/Runtime/RPC/CompatibilityUserSpaceOutputDispatchingAdapter.swift
+++ b/Sources/OpenJoystickDriver/Runtime/RPC/CompatibilityUserSpaceOutputDispatchingAdapter.swift
@@ -90,10 +90,10 @@ final class CompatibilityUserSpaceOutputDispatchingAdapter: CompatibilityUserSpa
       })
     else { return false }
     let ownership = await ownershipProvider(identifier)
-    let available = CompatibilityProfileAvailabilityPolicy.isAvailable(
-      identity,
-      for: AutomaticCompatibilityResolver.resolve(for: description).subfamily
-    )
+    let available = CompatibilityProfileAvailabilityPolicy.decision(
+      for: description,
+      identity: identity
+    ).isAvailable
     return ControllerExposureDecision.decide(
       ownership: ownership,
       intent: .explicit(identity),
diff --git a/Tests/OpenJoystickDriverTests/App/Presentation/Runtime/CompatibilityExposureRuntimeTests.swift b/Tests/OpenJoystickDriverTests/App/Presentation/Runtime/CompatibilityExposureRuntimeTests.swift
index fdfac6b..8972820 100644
--- a/Tests/OpenJoystickDriverTests/App/Presentation/Runtime/CompatibilityExposureRuntimeTests.swift
+++ b/Tests/OpenJoystickDriverTests/App/Presentation/Runtime/CompatibilityExposureRuntimeTests.swift
@@ -42,6 +42,19 @@ private final class ExposureState: @unchecked Sendable {
     )
   }

+  private func wr007Description(_ identifier: DeviceIdentifier) -> ApplicationServiceDeviceDescription {
+    ApplicationServiceDeviceDescription(
+      name: "WR-007",
+      vendorID: identifier.vendorID,
+      productID: identifier.productID,
+      parser: "GenericHID",
+      connection: "USB",
+      serialNumber: nil,
+      protocolVariant: .genericHID,
+      runtimeIdentifier: identifier.runtimeIdentifier
+    )
+  }
+
   private func makeAdapter(
     identity: CompatibilityIdentity,
     state: ExposureState,
@@ -70,6 +83,19 @@ private final class ExposureState: @unchecked Sendable {
     #expect(backend.dispatches == 1)
   }

+  @Test func explicitAppleIdentityPublishesForWR007Tuple() async throws {
+    let identifier = DeviceIdentifier(vendorID: 0x11C1, productID: 0x5600)
+    let state = ExposureState()
+    state.descriptions = [wr007Description(identifier)]
+    let (adapter, backend) = makeAdapter(identity: .appleGameController, state: state)
+
+    try await adapter.activate(controller: identifier)
+    await adapter.dispatch(events: [], from: identifier)
+
+    #expect(backend.activations == [[identifier]])
+    #expect(backend.dispatches == 1)
+  }
+
   @Test func explicitActivationAndLazyDispatchFailClosedWhenProfileOrDeviceIsUnavailable()
     async throws
   {
@@ -137,4 +163,25 @@ private final class ExposureState: @unchecked Sendable {
     #expect(backend.dispatches == 2)
     await dispatcher.close()
   }
+
+  @Test func automaticAppleIdentityPublishesForWR007Tuple() async {
+    let identifier = DeviceIdentifier(vendorID: 0x11C1, productID: 0x5600)
+    let state = ExposureState()
+    state.descriptions = [wr007Description(identifier)]
+    let backend = ExposureBackendProbe()
+    let dispatcher = AutomaticUserSpaceOutputDispatcher(
+      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
+      ownershipProvider: { _ in state.ownership },
+      consumerProvider: { .unknown },
+      builder: { _ in backend },
+      observeConsumerChanges: false,
+      descriptionsProvider: { state.descriptions },
+      identityProvider: { _, _ in .appleGameController }
+    )
+
+    await dispatcher.dispatch(events: [], from: identifier)
+
+    #expect(backend.dispatches == 1)
+    await dispatcher.close()
+  }
 }

```
</details>

### xsyetopz — 2026-09-15T00:32:50Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/31#issuecomment-5672842787)

OpenJoystickDriver 0.5.0-beta.4 is published: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.4

Thank you for the WR-007 hardware evidence; the release notes credit `@arthurknowles34-a11y`. The `11C1:5600` record maps the captured sparse buttons, sticks, and analog triggers and permits Apple GameController publication. Please use the signed release to verify every mapped control and consumer-visible virtual input: https://github.com/xsyetopz/OpenJoystickDriver/blob/0.5.0-beta.4/docs/testing/wr-007.md

Keeping this issue open for those hardware results.
