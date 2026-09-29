import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

struct ListCommand {
  let serviceCallTimeoutSeconds: Double

  func run() async {
    CLIOutput.diagnostic(
      CLILocalized.text("cli.controller.scanning", "Scanning for game controllers...")
    )
    CLIOutput.diagnostic("")
    if await checkApplicationServiceAndListDevices() { return }
    await handleDirectScan()
  }

  private func checkApplicationServiceAndListDevices() async -> Bool {
    let client = ApplicationServiceClient()
    await client.connect()
    let serviceDevices = await withTimeout(seconds: serviceCallTimeoutSeconds) {
      try await client.listDevices()
    }

    defer { client.disconnect() }

    guard let devices = serviceDevices else { return false }
    print(
      CLILocalized.text(
        "cli.controller.serviceControllers",
        "Controllers (from running application service):"
      )
    )
    if devices.isEmpty {
      print("  \(CLILocalized.text("cli.controller.noneConnected", "(none connected)"))")
    } else {
      for dev in devices { print("  \(dev)") }
    }
    print("")
    return true
  }

  private func handleDirectScan() async {
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.controller.directScan",
        "(direct scan - application service not running)"
      )
    )
    await listUSBDevices()
    CLIOutput.diagnostic("")
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.controller.hidNote",
        "Note: HID controllers are shown when application service is running."
      )
    )
  }

  private func listUSBDevices() async {
    print(CLILocalized.text("cli.controller.usbControllers", "USB Controllers (class 0xFF / GIP):"))
    let result: Result<[USBControllerDescription], USBScanFailure>
    do {
      result = .success(
        try await USBControllerScanner.scanVendorSpecific(
          using: OpenJoystickDriverUSBTransportProvider()
        )
      )
    } catch { result = .failure(USBScanFailure(message: error.localizedDescription)) }
    guard let devices = try? result.get() else {
      if case .failure(let error) = result {
        CLIOutput.error(
          CLILocalized.format(
            "cli.controller.usbAccessFailed",
            "USB access failed: %@",
            error.message
          )
        )
      }
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.controller.usbAccessTip",
          "Tip: grant the required entitlement and Input Monitoring access."
        )
      )
      return
    }
    if devices.isEmpty {
      print("  \(CLILocalized.text("cli.controller.noneFound", "(none found)"))")
      return
    }
    for device in devices {
      let vid = String(format: "%04X", device.vendorID)
      let pid = String(format: "%04X", device.productID)
      let quirks = device.quirks.isEmpty ? "none" : device.quirks.joined(separator: ",")
      let endpoints =
        if let input = device.inputEndpoint, let output = device.outputEndpoint {
          "in:0x\(input) out:0x\(output)"
        } else { "none" }
      print(
        "  VID=0x\(vid)" + " PID=0x\(pid)" + " bus=\(device.bus)" + " addr=\(device.address)"
          + " protocol=\(device.protocolBinding?.rawValue ?? "none")" + " endpoints=\(endpoints)"
          + " quirks=\(quirks)"
      )
    }
  }
}

private struct USBScanFailure: Error, Sendable { let message: String }
