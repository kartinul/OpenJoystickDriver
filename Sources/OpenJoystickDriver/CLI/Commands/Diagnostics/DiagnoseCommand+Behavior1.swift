import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverUSB

extension DiagnoseCommand {
  func run(arguments: [String] = []) {
    if let subcommand = arguments.first {
      switch subcommand {
      case "runtime": RuntimeHealthCommand().run(arguments: Array(arguments.dropFirst()))
      case "catalog": GameControllerCatalogCommand().run(arguments: Array(arguments.dropFirst()))
      case "--help", "-h", "help":
        CLIOutput.stdout(
          CLILocalized.text(
            "cli.diagnose.usage",
            "Usage: OpenJoystickDriver --headless diagnose [runtime|catalog|report]"
          )
        )
      default:
        CLIOutput.error(
          CLILocalized.format(
            "cli.diagnose.unknown_command",
            "Unknown diagnose command: %@",
            subcommand
          )
        )
        exit(1)
      }
      return
    }

    CLIOutput.diagnostic(
      CLILocalized.text("cli.diagnose.heading", "OpenJoystickDriver Diagnostics")
    )
    let divider = String(repeating: "\u{2550}", count: 30)
    CLIOutput.diagnostic(divider)
    CLIOutput.diagnostic("")

    printSystemInfo()
    CLIOutput.diagnostic("")
    printSystemExtensionBundle()
    CLIOutput.diagnostic("")
    printPermissionsSection()
    CLIOutput.diagnostic("")
    printUSBDevices()
    CLIOutput.diagnostic("")
    printTroubleshooting()
  }

  private func printSystemInfo() {
    let ver = ProcessInfo.processInfo.operatingSystemVersion
    CLIOutput.diagnostic(
      CLILocalized.format(
        "cli.diagnose.macos_version",
        "macOS: %d.%d.%d",
        ver.majorVersion,
        ver.minorVersion,
        ver.patchVersion
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.format("cli.diagnose.binary_path", "Binary: %@", CommandLine.arguments[0])
    )
  }

  private func printSystemExtensionBundle() {
    let appPath = "/Applications/OpenJoystickDriver.app"
    let sysextDir = appPath + "/Contents/Library/SystemExtensions"
    let expectedID = USBDriverKitExtensionConfiguration.bundleIdentifier
    let expectedDextPath = sysextDir + "/com.openjoystickdriver.XboxUSBDevice.dext"

    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.diagnose.extension_heading",
        "DriverKit System Extension (in /Applications):"
      )
    )

    let fm = FileManager.default
    guard fm.fileExists(atPath: appPath) else {
      CLIOutput.diagnostic(
        CLILocalized.format("cli.diagnose.app_missing", "  App: missing at %@", appPath)
      )
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.diagnose.app_missing_fix",
          "  Fix: build + install the app to /Applications"
        )
      )
      return
    }

    CLIOutput.diagnostic(CLILocalized.text("cli.diagnose.app_present", "  App: present"))
    CLIOutput.diagnostic(
      CLILocalized.format("cli.diagnose.expected_dext", "  Expected .dext: %@", expectedDextPath)
    )

    guard fm.fileExists(atPath: sysextDir) else {
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.diagnose.extensions_folder_missing",
          "  Result: FAIL (missing SystemExtensions folder)"
        )
      )
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.diagnose.fix_rebuild_dev",
          "  Fix: run: ./Scripts/ojd build install dev"
        )
      )
      return
    }

    let items = (try? fm.contentsOfDirectory(atPath: sysextDir)) ?? []
    let dexts = items.filter { $0.hasSuffix(".dext") }.sorted()
    if dexts.isEmpty {
      CLIOutput.diagnostic(
        CLILocalized.text("cli.diagnose.no_dext", "  Result: FAIL (no .dext bundles found)")
      )
      CLIOutput.diagnostic(
        CLILocalized.text("cli.diagnose.fix_build_dext", "  Fix: run: ./Scripts/ojd build dext")
      )
      return
    }

    CLIOutput.diagnostic(CLILocalized.text("cli.diagnose.dext_found", "  Found .dext bundles:"))
    var foundExpected = false
    for d in dexts {
      let path = sysextDir + "/" + d
      let bid = Bundle(path: path)?.bundleIdentifier ?? "UNKNOWN"
      CLIOutput.diagnostic(
        CLILocalized.format("cli.diagnose.dext_list_item", "    - %@ (id: %@)", d, bid)
      )
      if bid == expectedID { foundExpected = true }
    }

    if foundExpected {
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.diagnose.expected_id_present",
          "  Result: PASS (expected id present: %@)",
          expectedID
        )
      )
    } else {
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.diagnose.expected_id_missing",
          "  Result: FAIL (expected id missing: %@)",
          expectedID
        )
      )
      CLIOutput.diagnostic(
        CLILocalized.text("cli.diagnose.fix_build_dext", "  Fix: run: ./Scripts/ojd build dext")
      )
    }
  }

  private func printPermissionsSection() {
    let client = ApplicationServiceClient()
    client.connect()
    defer { client.disconnect() }
    let payload: ApplicationServiceStatusPayload? = runSyncOptionalResult(
      timeout: applicationServiceCallTimeoutSeconds
    ) { try? await client.getStatus() }
    guard let payload else {
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.diagnose.permissions_unavailable",
          "Permissions: unavailable without the running main app"
        )
      )
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.diagnose.permissions_recovery",
          "  Recovery: launch the installed OpenJoystickDriver app"
        )
      )
      return
    }

    permissionSnapshotLines(
      StatusPermissions(
        inputMonitoring: payload.inputMonitoring,
        accessibility: payload.accessibility
      )
    ).forEach { CLIOutput.diagnostic($0) }
    CLIOutput.diagnostic(
      CLILocalized.text("cli.diagnose.state_source", "  State source     : running main app")
    )
  }

  private func printUSBDevices() {
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.diagnose.usb_controllers_heading",
        "USB Game Controllers (class 0xFF):"
      )
    )
    let result: Result<[USBControllerDescription], DiagnoseUSBScanFailure> = runSyncResult {
      do {
        return .success(
          try await USBControllerScanner.scanVendorSpecific(
            using: OpenJoystickDriverUSBTransportProvider()
          )
        )
      } catch { return .failure(DiagnoseUSBScanFailure(message: error.localizedDescription)) }
    }
    guard let devices = try? result.get() else {
      if case .failure(let error) = result {
        CLIOutput.error(
          CLILocalized.format("cli.diagnose.usb_failed", "USB access failed: %@", error.message)
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
      CLIOutput.diagnostic(CLILocalized.text("cli.diagnose.none_detected", "  (none detected)"))
      return
    }
    for device in devices {
      let vid = String(format: "%04X", device.vendorID)
      let pid = String(format: "%04X", device.productID)
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.diagnose.usb_device_line",
          "  VID=0x%@ PID=0x%@ bus=%@ addr=%@",
          vid,
          pid,
          device.bus,
          device.address
        )
      )
      printProtocolObservation(device)
    }
  }

  private func printProtocolObservation(_ device: USBControllerDescription) {
    guard let observation = device.physicalDevice, let interfaces = observation.interfaces else {
      printProtocolObservationUnavailable()
      return
    }
    for interface in interfaces {
      guard let number = interface.interfaceNumber,
        let alternateSetting = interface.alternateSetting,
        let interfaceClass = interface.interfaceClass, let endpoints = interface.endpoints
      else {
        printProtocolObservationUnavailable()
        return
      }
      let subclass = interface.interfaceSubclass.map { String(format: "%02X", $0) } ?? "--"
      let protocolValue = interface.interfaceProtocol.map { String(format: "%02X", $0) } ?? "--"
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.diagnose.interface_line",
          "    Interface %d/%d: %02X/%@/%@",
          number,
          alternateSetting,
          interfaceClass,
          subclass,
          protocolValue
        )
      )
      for endpoint in endpoints {
        guard let address = endpoint.address, let transferType = endpoint.transferType,
          let direction = endpoint.direction
        else {
          printProtocolObservationUnavailable()
          return
        }
        let packet = endpoint.maxPacketSize.map(String.init) ?? "unknown"
        let interval = endpoint.interval.map(String.init) ?? "unknown"
        CLIOutput.diagnostic(
          CLILocalized.format(
            "cli.diagnose.endpoint_line",
            "      endpoint 0x%02X %@ %@ maxPacket=%@ interval=%@",
            address,
            transferType.rawValue,
            direction.rawValue,
            packet,
            interval
          )
        )
      }
    }
    guard let classification = device.classification else { return }
    switch classification {
    case .bound(let binding):
      let protocolName = [binding.protocolID.rawValue, binding.variant?.rawValue].compactMap { $0 }
        .joined(separator: ":")
      let predicates = binding.matchedPredicates.map(\.rawValue).joined(separator: ", ")
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.diagnose.matched_predicates",
          "      Matched: %@",
          "\(protocolName) (\(binding.rule.rawValue): \(predicates))"
        )
      )
    case .unsupported(let reason):
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.diagnose.rejected_predicates",
          "      Rejected: %@",
          reason.rawValue
        )
      )
    case .conflict(let reason, let candidates):
      let candidateNames = candidates.map(\.rawValue).joined(separator: ", ")
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.diagnose.rejected_predicates",
          "      Rejected: %@",
          "\(reason.rawValue) [\(candidateNames)]"
        )
      )
    }
  }

  private func printProtocolObservationUnavailable() {
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.diagnose.protocol_unavailable",
        "    Protocol observation: unavailable (catalog admission unchanged)"
      )
    )
  }
}
