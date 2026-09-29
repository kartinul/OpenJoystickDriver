import Foundation
import OpenJoystickDriverKit

struct RuntimeHealthCommand {
  func run(arguments: [String]) async throws {
    guard let options = try parse(arguments: arguments) else { return }
    let health = ApplicationServiceManager.health()
    guard let processID = health.pid else {
      CLIOutput.error(
        CLILocalized.text(
          "cli.runtime.not_running",
          "OpenJoystickDriver application service is not running."
        )
      )
      throw CLIExit.failure
    }

    let policy = RuntimeHealthPolicy(
      maximumResidentBytes: options.residentLimitMiB == 0
        ? nil : UInt64(options.residentLimitMiB) * 1_048_576,
      maximumPhysicalFootprintBytes: options.physicalFootprintLimitMiB == 0
        ? nil : UInt64(options.physicalFootprintLimitMiB) * 1_048_576
    )
    let summary: RuntimeHealthSummary
    do {
      summary = try await ApplicationServiceRuntimeHealthSampler.sample(
        processID: Int32(processID),
        seconds: options.seconds,
        intervalMilliseconds: options.intervalMilliseconds,
        policy: policy
      )
    } catch {
      CLIOutput.error(error.localizedDescription)
      throw CLIExit.failure
    }

    if options.json {
      try encodeJSON(summary)
      return
    }
    printSummary(summary)
  }

  private struct Options {
    var seconds = 60
    var intervalMilliseconds = 1_000
    var residentLimitMiB = 0
    var physicalFootprintLimitMiB = 512
    var json = false
  }

  /// Returns nil when help was requested and printed.
  private func parse(arguments: [String]) throws -> Options? {
    var options = Options()
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--seconds":
        options.seconds = try parseValue(arguments, at: index, allowed: 1...86_400)
        index += 2
      case "--interval-ms":
        options.intervalMilliseconds = try parseValue(arguments, at: index, allowed: 100...60_000)
        index += 2
      case "--rss-limit-mib":
        options.residentLimitMiB = try parseValue(arguments, at: index, allowed: 0...65_536)
        index += 2
      case "--footprint-limit-mib":
        options.physicalFootprintLimitMiB = try parseValue(
          arguments,
          at: index,
          allowed: 0...65_536
        )
        index += 2
      case "--json":
        options.json = true
        index += 1
      case "--help", "-h", "help":
        printHelp()
        return nil
      default: try failUsage()
      }
    }

    let estimatedSamples =
      Int(ceil(Double(options.seconds * 1_000) / Double(options.intervalMilliseconds))) + 1
    guard estimatedSamples <= ApplicationServiceRuntimeHealthSampler.maximumSampleCount else {
      CLIOutput.error(
        CLILocalized.format(
          "cli.runtime.sample_limit",
          "Configuration would collect %d samples; increase --interval-ms.",
          estimatedSamples
        )
      )
      throw CLIExit.failure
    }
    return options
  }

  private func parseValue(
    _ arguments: [String],
    at index: Int,
    allowed: ClosedRange<Int>
  ) throws -> Int {
    guard index + 1 < arguments.count, let value = Int(arguments[index + 1]),
      allowed.contains(value)
    else { try failUsage() }
    return value
  }

  private func encodeJSON(_ summary: RuntimeHealthSummary) throws {
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(summary)
      print(String(data: data, encoding: .utf8) ?? "{}")
    } catch {
      CLIOutput.error(
        CLILocalized.format(
          "cli.runtime.json_error",
          "Could not encode runtime summary: %@",
          error.localizedDescription
        )
      )
      throw CLIExit.failure
    }
  }

  private func printSummary(_ summary: RuntimeHealthSummary) {
    print(
      CLILocalized.text(
        "cli.runtime.heading",
        "OpenJoystickDriver Application Service Runtime Soak"
      )
    )
    print("  Samples    : \(summary.sampleCount) over \(format(summary.durationSeconds))s")
    print(
      "  RSS        : \(mebibytes(summary.firstResidentBytes)) -> "
        + "\(mebibytes(summary.lastResidentBytes)) MiB "
        + "(peak \(mebibytes(summary.peakResidentBytes)))"
    )
    print(
      "  Footprint  : \(mebibytes(summary.firstPhysicalFootprintBytes)) -> "
        + "\(mebibytes(summary.lastPhysicalFootprintBytes)) MiB "
        + "(peak \(mebibytes(summary.peakPhysicalFootprintBytes)))"
    )
    print("  RSS rate   : \(signedMebibytes(summary.residentGrowthBytesPerHour)) MiB/hour")
    print(
      "  Foot rate  : " + "\(signedMebibytes(summary.physicalFootprintGrowthBytesPerHour)) MiB/hour"
    )
    print(
      "  FDs        : \(summary.firstFileDescriptorCount) -> "
        + "\(summary.lastFileDescriptorCount) " + "(peak \(summary.peakFileDescriptorCount))"
    )
    print(
      "  Threads    : \(summary.firstThreadCount) -> "
        + "\(summary.lastThreadCount) (peak \(summary.peakThreadCount))"
    )
    print("  CPU avg    : \(format(summary.averageCPUPercent))%")
    print("  RSS trend  : \(summary.memoryTrend.rawValue)")
    print("  Foot trend : \(summary.physicalMemoryTrend.rawValue)")
    if let limit = summary.residentLimitBytes { print("  RSS limit  : \(mebibytes(limit)) MiB") }
    if let limit = summary.physicalFootprintLimitBytes {
      print("  Foot limit : \(mebibytes(limit)) MiB")
    }
    print("  Verdict    : \(summary.soakVerdict.rawValue)")
    if summary.soakVerdict == .insufficientData {
      print(
        CLILocalized.format(
          "cli.runtime.inconclusive",
          "Observation shorter than %ds is inconclusive; use a longer active-controller soak.",
          summary.minimumSoakSeconds
        )
      )
    } else {
      print(
        CLILocalized.text(
          "cli.runtime.stable_note",
          "A stable bounded soak is evidence for this workload, "
            + "not proof that all leaks are absent."
        )
      )
    }
  }

  private func failUsage() throws -> Never {
    printHelp()
    throw CLIExit.failure
  }

  private func printHelp() {
    print(
      [
        CLILocalized.text(
          "cli.runtime.help",
          """
          Usage: OpenJoystickDriver --headless diagnose runtime \
          [--seconds 1...86400] [--interval-ms 100...60000] \
          [--rss-limit-mib 0...65536] [--footprint-limit-mib 0...65536] [--json]

          Samples application service RSS, physical footprint, CPU, file descriptors, and threads.
          """
        ),
        CLILocalized.text(
          "cli.runtime.help_limits",
          "Zero disables a high-water limit; footprint defaults to 512 MiB. "
            + "Windows under 60 seconds are explicitly inconclusive; "
            + "use a longer soak while reproducing activity."
        ),
        CLILocalized.text(
          "cli.runtime.help_max_samples",
          "At most 100000 samples may be requested."
        ),
      ].joined(separator: "\n")
    )
  }

  private func mebibytes(_ bytes: UInt64) -> String { format(Double(bytes) / 1_048_576) }

  private func signedMebibytes(_ bytesPerHour: Double) -> String {
    let value = bytesPerHour / 1_048_576
    return value >= 0 ? "+\(format(value))" : format(value)
  }

  private func format(_ value: Double) -> String { String(format: "%.2f", value) }
}
