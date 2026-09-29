import Darwin
import Dispatch
import Foundation
import OpenJoystickDriverKit

enum CLIOutput {
  static func stdout(_ message: String = "", terminator: String = "\n") {
    write(message, terminator: terminator, to: FileHandle.standardOutput)
  }

  static func stderr(_ message: String = "", terminator: String = "\n") {
    write(message, terminator: terminator, to: FileHandle.standardError)
  }

  static func warning(_ message: String) {
    stderr("\(CLILocalized.text("cli.output.warning_prefix", "WARNING")): \(message)")
  }

  static func error(_ message: String) {
    stderr("\(CLILocalized.text("cli.output.error_prefix", "ERROR")): \(message)")
  }

  static func diagnostic(_ message: String = "", terminator: String = "\n") {
    stderr(message, terminator: terminator)
  }

  private static func write(_ message: String, terminator: String, to handle: FileHandle) {
    handle.write(Data((message + terminator).utf8))
  }
}

private let cliShutdownCleanup = Locked<(@Sendable () async -> Void)?>(nil)
private let cliShutdownSources = Locked<[DispatchSourceSignal]>([])

func installCLIShutdownHandlers() {
  guard cliShutdownSources.withLock({ $0.isEmpty }) else { return }
  for signalNumber in [SIGINT, SIGTERM] {
    let source = DispatchSource.makeSignalSource(
      signal: signalNumber,
      queue: DispatchQueue.global(qos: .userInitiated)
    )
    source.setEventHandler {
      Task {
        let cleanup = cliShutdownCleanup.withLock { $0 }
        await cleanup?()
        fflush(stdout)
        fflush(stderr)
        exit(128 + signalNumber)
      }
    }
    source.resume()
    signal(signalNumber, SIG_IGN)
    cliShutdownSources.withLock { $0.append(source) }
  }
}

func withCLIShutdownCleanup<T>(
  _ cleanup: @escaping @Sendable () async -> Void,
  _ body: () async throws -> T
) async rethrows -> T {
  let previous = cliShutdownCleanup.withLock { current in
    defer { current = cleanup }
    return current
  }
  defer { cliShutdownCleanup.withLock { $0 = previous } }
  return try await body()
}

/// Awaits `operation` until it completes or `seconds` elapse, returning nil on timeout or error.
///
/// The operation runs in its own task so a call that never replies (for example an invalidated
/// application service connection) cannot hold the command past its deadline; it is cancelled
/// once the deadline passes.
func withTimeout<T: Sendable>(
  seconds: Double,
  _ operation: @escaping @Sendable () async throws -> T
) async -> T? {
  let outcomes = AsyncStream<T?>(bufferingPolicy: .bufferingOldest(1)) { continuation in
    let work = Task {
      continuation.yield(try? await operation())
      continuation.finish()
    }
    let deadline = Task {
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      continuation.yield(nil)
      continuation.finish()
    }
    continuation.onTermination = { _ in
      work.cancel()
      deadline.cancel()
    }
  }
  for await outcome in outcomes { return outcome }
  return nil
}

/// Ensures the CLI is executed from an app bundle installed under `/Applications`.
///
/// Login registration requires the signed installed bundle.
func requireApplicationsBundle() throws {
  let path = Bundle.main.bundlePath
  guard path.hasPrefix("/Applications/") else {
    CLIOutput.error(
      CLILocalized.text(
        "cli.error.applications_bundle",
        "This command must be run from the /Applications-installed app bundle."
      )
    )
    CLIOutput.diagnostic(
      CLILocalized.format("cli.error.current_bundle", "Current bundle: %@", path)
    )
    CLIOutput.diagnostic(
      CLILocalized.text(
        "cli.error.applications_bundle_fix",
        "  Fix: run: /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver "
          + "--headless <command>"
      )
    )
    throw CLIExit.failure
  }
}

/// Ensures the app bundle is validly signed.
///
/// This catches the common dev failure mode where a `.dext` is copied into the app bundle
/// after signing, which breaks the signature and causes application service registration to fail.
func requireValidBundleSignature(action: String) throws {
  let appPath = Bundle.main.bundlePath
  let result: BoundedProcessResult
  do {
    result = try BoundedProcessRunner.run(
      executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
      arguments: ["--verify", "--deep", "--strict", "--verbose=2", appPath],
      timeoutSeconds: 15,
      maximumOutputBytes: 262_144
    )
  } catch {
    CLIOutput.error(
      CLILocalized.format(
        "cli.error.codesign_run_failed",
        "%@ failed: could not run codesign verification: %@",
        action,
        error.localizedDescription
      )
    )
    throw CLIExit.failure
  }
  if result.timedOut {
    CLIOutput.error(
      CLILocalized.format(
        "cli.error.codesign_timeout",
        "%@ failed: codesign verification timed out after 15 seconds.",
        action
      )
    )
    throw CLIExit.failure
  }
  let out = result.output
  guard result.terminationStatus == 0 else {
    if out.contains("a sealed resource is missing or invalid") {
      CLIOutput.error(
        CLILocalized.format(
          "cli.error.codesign_invalid_signature",
          "%@ failed: this app bundle's signature is INVALID (modified after signing).",
          action
        )
      )
      CLIOutput.diagnostic("")
      CLIOutput.diagnostic(CLILocalized.text("cli.error.fix_heading", "Fix:"))
      CLIOutput.diagnostic(
        CLILocalized.text(
          "cli.error.rebuild_fast_step",
          "  1) Run: ./Scripts/ojd build install-fast dev"
        )
      )
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.error.rerun_step",
          "  2) Then re-run: "
            + "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver "
            + "--headless %@",
          action.lowercased()
        )
      )
      CLIOutput.diagnostic("")
      CLIOutput.diagnostic(
        CLILocalized.text("cli.error.diagnostic_command_heading", "Diagnostic command:")
      )
      CLIOutput.diagnostic(
        CLILocalized.format(
          "cli.error.codesign_diagnostic",
          "  /usr/bin/codesign --verify --deep --strict --verbose=2 %@",
          appPath
        )
      )
      throw CLIExit.failure
    }
    let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
    CLIOutput.error(
      CLILocalized.format(
        "cli.error.signature_verification_failed",
        "%@ failed: app signature verification failed:",
        action
      )
    )
    if trimmed.isEmpty {
      CLIOutput.diagnostic(CLILocalized.text("cli.error.no_output", "  (no output)"))
    } else {
      CLIOutput.diagnostic(trimmed)
    }
    throw CLIExit.failure
  }
}
