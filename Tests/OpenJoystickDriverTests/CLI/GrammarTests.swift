import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct CLIGrammarTests {
  @Test(arguments: [
    ("status", CLIInvocation.status([])), ("status --json", CLIInvocation.status(["--json"])),
    ("controller list", CLIInvocation.controllerList),
    ("controller state --json", CLIInvocation.controllerInput(["state", "--json"])),
    ("controller packets --limit 10", CLIInvocation.controllerInput(["packets", "--limit", "10"])),
    (
      "controller trace --seconds 30 --json-lines",
      CLIInvocation.controllerInput(["trace", "--seconds", "30", "--json-lines"])
    ),
    (
      "controller watch --device device-1",
      CLIInvocation.controllerInput(["watch", "--device", "device-1"])
    ), ("controller output plan 1 2", CLIInvocation.controllerOutput(["plan", "1", "2"])),
    (
      "controller disconnect --device device-1",
      CLIInvocation.controllerDisconnect(["--device", "device-1"])
    ),
    (
      "controller resume --device device-1",
      CLIInvocation.controllerResume(["--device", "device-1"])
    ),
    (
      "controller disconnect-wireless --device device-1",
      CLIInvocation.controllerDisconnectWireless(["--device", "device-1"])
    ), ("map list --json", CLIInvocation.mapping(["list", "--json"])),
    ("app status", CLIInvocation.appStatus([])), ("app ready", CLIInvocation.appReady),
    ("app login enable", CLIInvocation.appLogin(enable: true)),
    ("extension enable", CLIInvocation.extension(.enable)),
    ("permissions open input", CLIInvocation.permissions(["open", "input"])),
    ("test 10", CLIInvocation.selfTest(["10"])), ("diagnose", CLIInvocation.diagnose(.summary)),
    ("diagnose catalog --json", CLIInvocation.diagnose(.gameControllerCatalog(["--json"]))),
    (
      "diagnose report --output report.json",
      CLIInvocation.diagnose(.report(["--output", "report.json"]))
    ), ("update check --json", CLIInvocation.updateCheck(["--json"])),
  ])
  func parsesApprovedGrammar(raw: String, expected: CLIInvocation) throws {
    let arguments = raw.split(separator: " ").map(String.init)
    #expect(try CLIGrammar(arguments: arguments).invocation == expected)
  }

  @Test(arguments: [
    ("controller virtual set hid-generic", CLIVirtualProfileAction.change(.set(.generic), .init())),
    (
      "controller virtual set hid-xbox-one-s-bt --vid 0x045E --pid 736",
      .change(.set(.xboxOneSBluetooth), .init(vendorID: 0x045E, productID: 736))
    ),
    (
      "controller virtual set hid-generic --device device-1",
      .change(.set(.generic), .init(runtimeIdentifier: "device-1"))
    ),
    (
      "controller virtual set hid-generic --vid 1 --pid 2 --device device-1",
      .change(.set(.generic), .init(vendorID: 1, productID: 2, runtimeIdentifier: "device-1"))
    ), ("controller virtual reset", .change(.reset, .init())),
    (
      "controller virtual reset --vid 0x054C --pid 0x09CC",
      .change(.reset, .init(vendorID: 1356, productID: 2508))
    ),
    (
      "controller virtual reset --device device-1",
      .change(.reset, .init(runtimeIdentifier: "device-1"))
    ), ("controller virtual reset --all", .resetAll),
  ])
  func parsesVirtualProfileCommandsWithEachSelectorForm(
    raw: String,
    expected: CLIVirtualProfileAction
  ) throws {
    let arguments = raw.split(separator: " ").map(String.init)
    #expect(try CLIGrammar(arguments: arguments).invocation == .controllerVirtual(expected))
  }

  @Test
  func rejectsAnUnknownVirtualProfileAndListsBothProfiles() {
    let error = #expect(throws: VirtualProfileCommand.UnknownProfile.self) {
      try CLIGrammar(arguments: ["controller", "virtual", "set", "sdl2-3", "--device", "device-1"])
    }
    #expect(error == VirtualProfileCommand.UnknownProfile(value: "sdl2-3"))
    let message = error?.errorDescription ?? ""
    #expect(message.contains("sdl2-3"))
    #expect(message.contains("hid-xbox-one-s-bt"))
    #expect(message.contains("hid-generic"))
  }

  @Test
  func rejectsAMissingVirtualProfileAndListsBothProfiles() {
    let error = #expect(throws: VirtualProfileCommand.MissingProfile.self) {
      try CLIGrammar(arguments: ["controller", "virtual", "set"])
    }
    let message = error?.errorDescription ?? ""
    #expect(message.contains("controller virtual set"))
    #expect(message.contains("hid-xbox-one-s-bt"))
    #expect(message.contains("hid-generic"))
  }

  @Test
  func rejectsMalformedVirtualProfileCommands() {
    for arguments in [["controller", "virtual"], ["controller", "virtual", "show"]] {
      #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: arguments) }
    }
    for arguments in [
      ["controller", "virtual", "reset", "--vid"],
      ["controller", "virtual", "reset", "--vid", "zz", "--pid", "1"],
      ["controller", "virtual", "set", "hid-generic", "--serial", "1"],
    ] {
      #expect(throws: ControllerSelector.InvalidArguments.self) {
        try CLIGrammar(arguments: arguments)
      }
    }
  }

  @Test
  func rejectsVirtualProfileResetAllCombinedWithASelector() {
    for arguments in [
      ["controller", "virtual", "reset", "--all", "--vid", "1", "--pid", "2"],
      ["controller", "virtual", "reset", "--vid", "1", "--pid", "2", "--all"],
      ["controller", "virtual", "reset", "--all", "--device", "device-1"],
    ] {
      let error = #expect(throws: VirtualProfileCommand.ResetAllWithSelector.self) {
        try CLIGrammar(arguments: arguments)
      }
      #expect(
        error?.errorDescription == "'--all' cannot be combined with --vid, --pid, or --device."
      )
    }
  }

  #if DEBUG
    @Test
    func debugGrammarRecognizesPassiveCommand() throws {
      let invocation = try CLIGrammar(arguments: [
        "diagnose", "usb-passive", "--vid", "3537", "--pid", "1010",
      ]).invocation
      #expect(invocation == .diagnose(.usbPassive(["--vid", "3537", "--pid", "1010"])))
    }
  #endif

  @Test(arguments: [
    [], ["run"], ["list"], ["input"], ["logs"], ["updates"], ["report"], ["physical-output"],
    ["compatibility"], ["selftest"], ["sysext"], ["install"], ["uninstall"], ["start"], ["restart"],
    ["reset-settings"], ["compat"], ["compat", "show"], ["compat", "set", "hid-generic"],
    ["compat", "reset"],
  ])
  func rejectsRemovedTopLevelSpellings(arguments: [String]) {
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: arguments) }
  }

  @Test
  func rejectsMissingAndUnexpectedNestedCommands() {
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["controller"]) }
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["app", "login"]) }
    #expect(throws: CLIParseError.self) {
      try CLIGrammar(arguments: ["extension", "status", "now"])
    }
  }

  @Test
  func rejectsObsoletePublicSpellingsAtGrammarLevel() {
    for arguments in [
      ["controller", "input"], ["mapping", "list"], ["compatibility", "get"],
      ["extension", "activate"], ["extension", "deactivate"], ["permissions", "open-settings"],
      ["diagnose", "self-test"], ["diagnose", "gamecontroller-catalog"], ["diagnose", "summary"],
      ["app", "start"], ["app", "restart"],
    ] { #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: arguments) } }
  }

  @Test
  func standardHelpAndVersionFlagsRemainExplicit() throws {
    #expect(try CLIGrammar(arguments: ["--help"]).invocation == .help)
    #expect(try CLIGrammar(arguments: ["-v"]).invocation == .version)
  }

  @Test
  func extractsTheGlobalServiceTimeoutBeforeTheCommand() throws {
    let grammar = try CLIGrammar(arguments: ["--timeout", "2.5", "status"])
    #expect(grammar.invocation == .status([]))
    #expect(grammar.serviceTimeoutSeconds == 2.5)
    #expect(throws: CLIParseError.self) { try CLIGrammar(arguments: ["--timeout", "0", "status"]) }
  }
}
