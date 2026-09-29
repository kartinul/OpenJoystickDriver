import Foundation
import OpenJoystickDriverKit

struct MappingCommand {
  func run(arguments: [String]) async throws {
    do {
      let invocation = try MappingInvocation(arguments: arguments)
      if invocation.isHelp {
        print(MappingInvocation.help)
        return
      }
      let client = ApplicationServiceClient()
      await client.connect()
      defer { client.disconnect() }
      guard client.isConnected else {
        throw MappingCommandError.invalidArguments(
          CLILocalized.text(
            "cli.mapping.app_unreachable",
            "Could not connect to the installed main app."
          )
        )
      }
      print(try await invocation.execute(client: ApplicationMappingServiceClient(client: client)))
    } catch {
      CLIOutput.error(error.localizedDescription)
      throw CLIExit.failure
    }
  }
}

struct MappingInvocation {
  internal static let bindingOptions: Set<String> = [
    "--source", "--target", "--deadzone", "--gain", "--invert", "--response-curve",
    "--digital-threshold", "--turbo-rate", "--turbo-duty", "--long-hold", "--double-tap",
    "--behavior", "--pulse-ms", "--actions-json",
  ]
  internal let command: String
  internal let arguments: [String]

  init(arguments: [String]) throws {
    guard let command = arguments.first else {
      throw MappingCommandError.invalidArguments(Self.help)
    }
    self.command = command
    self.arguments = Array(arguments.dropFirst())
  }

  static let help =
    CLILocalized.text(
      "cli.mapping.help",
      """
      Usage: OpenJoystickDriver --headless map <command>

      Commands:
        list [--json]
        show <profile> [--json]
        create <name> --vid <id> --pid <id> (--target-app <bundle-id> | --global)
        restore-default-input <profile>
        clear-inputs <profile> --confirm
        update <profile> [--name <name>] [--vid <id>] [--pid <id>]
          [--target-app <bundle-id> | --global]
        bind <profile> --source <source> --target <target> [binding options]
        unbind <profile> --source <source>
        delete <profile>
        import <file>
        export <profile> [--output <file>]
        enable <profile> [--allow-empty]
        disable --vid <id> --pid <id> | --profile <uuid-or-name>
        permission status | request
        calibration status|start|pause|reset --controller <runtime-identifier>
        joy-con pair <profile> --left <runtime-identifier> --right <runtime-identifier>
        joy-con unpair --session <session-uuid>
        --gyro-output disabled|mouse|left_stick|right_stick
        --gyro-pointer-points-per-degree <0...1000>
        --gyro-full-stick-degrees-per-second <1...10000>
        --gyro-activation always|while_held|while_released|toggle
        --gyro-activation-source <source>
        --gyro-consume-activation true|false
        --gyro-trackball-source <source>|none --gyro-trackball-axes pitch|yaw|both
        --gyro-trackball-decay <halvings/s> --gyro-trackball-consume true|false
        chord add <profile> --sources <s1>,<s2>,... --target <destination>
          [--mode modifier|simultaneous] [--window-ms <1...1000>]
        chord delete <profile> --id <chord-id>
        sequence add <profile> --sources <s1>,<s2>,... --window <ms> --target <destination>
        sequence delete <profile> --id <sequence-id>
        layer create <profile> --name <name> --activator <source> --mode hold|toggle
        layer delete <profile> --id <layer-id>
        layer bind <profile> --layer <layer-id> --source <s> --target <t> [binding options]
        layer unbind <profile> --layer <layer-id> --source <s>
        layer list <profile>

      Source: button:<name> | dpad:<direction> | axis:<name>[:negative|positive] |
        touch:<surface>:contact | touch:<surface>:grid:<columns>:<rows>:<column>:<row> |
        touch:<surface>:swipe:<direction>:<minimum-distance>
      Target: key:<key>[:mods=command,control,option,shift] | mouse:<button> |
        move:x|y | scroll:x|y | gamepad:button:<name> | gamepad:dpad:<direction> |
        gamepad:axis:<name>

      Output options (create and update):
        --virtual-gamepad disabled|mapped|passthrough
        --physical-input shared|exclusive
        Virtual gamepad output requires exclusive physical input ownership.

      --behavior hold|toggle|tap_on_press|tap_on_release|pulse|press|release
      --pulse-ms <1...5000>
      --actions-json <JSON-array>

      Stick options (create and update; select one stick per command):
        --stick-source left|right --stick-mode aim|flick|flick_only|rotate_only|none
        --stick-inner-deadzone <0...0.95> --stick-outer-deadzone <0...0.95>
        --stick-response-exponent <0.1...10> --stick-invert-x true|false
        --stick-invert-y true|false --stick-aim-degrees-per-second <0...10000>
        --stick-pointer-points-per-degree <0...1000> --stick-flick-duration-ms <0...10000>
        --stick-flick-threshold <0.1...1> --stick-flick-hysteresis <0...0.5>
      Touch options (create and update; select one surface per command):
        --touch-surface primary|left|right
        --touch-mode pointer|left_stick|right_stick|none
        --touch-pointer-sensitivity <1...5000> --touch-stick-radius <0.01...1>
        --touch-deadzone <0...0.95>

      Paired Joy-Con profile option (create and update):
        --joy-con-pair-gyro left|right|disabled|none

      Axis options:
        --deadzone <0...0.95> --gain <0.1...10>
        --invert --response-curve <linear|ease_in|ease_out|smooth_step>
        --digital-threshold <0.01...1>

      Turbo options (keyboard and mouse buttons only):
        --turbo-rate <1...60> --turbo-duty <0.05...0.95>

      Activation options (keyboard and mouse buttons only, mutually exclusive with turbo):
        --long-hold <ms>:<target>     e.g. --long-hold 500:key:b
        --double-tap <ms>:<target>    e.g. --double-tap 300:key:c

      <profile> accepts a UUID or an exact, case-insensitive profile name.
      <id> accepts decimal or 0x-prefixed hexadecimal.

      map update <profile> --motion-space local|player|world
      --motion-pitch-sensitivity <0...100> --motion-yaw-sensitivity <0...100>
      --motion-invert-pitch true|false --motion-invert-yaw true|false
      --motion-smoothing-half-time-ms <0...1000>
      --motion-threshold-degrees-per-second <0...1000>
      --motion-automatic-bias true|false --motion-yaw-relaxation <0...10>
      --motion-side-reduction-threshold <0...1> --motion-gravity-correction-rate <0...100>
      """
    ) + "\n\n"
    + CLILocalized.text(
      "cli.mapping.advanced_stick_trigger_help",
      """
      Advanced stick, trigger, and lean options:
        --stick-source left|right
        --stick-mode pointer_area|pointer_ring|scroll_wheel|steering|none
        --stick-pointer-radius-points <1...10000> --stick-scroll-degrees-per-line <1...360>
        --stick-scroll-axis horizontal|vertical
        --stick-rotation-direction clockwise|counterclockwise
        --stick-steering-degrees-at-full-scale <45...1440>
        --stick-steering-return-degrees-per-second <0...10000>
        --stick-steering-output left_stick_x|right_stick_x --stick-passthrough true|false

        --trigger-source left|right
        --trigger-mode simultaneous|exclusive|prefer_full|prefer_full_combined|
          responsive_prefer_full|responsive_prefer_full_combined|none
        --trigger-soft-threshold <0.01...0.95> --trigger-full-threshold <0.05...1>
        --trigger-hysteresis <0...0.25> --trigger-skip-window-ms <1...1000>
        --trigger-passthrough true|false

        --motion-lean true|false --motion-lean-threshold-degrees <1...89>
        --motion-lean-hysteresis-degrees <0...30>
        --motion-steering-output left_stick_x|right_stick_x|none
        --motion-steering-deadzone-degrees <0...89>
        --motion-steering-full-scale-degrees <1...90>
        --motion-steering-response-exponent <0.1...10>
        --motion-steering-inverted true|false

      Sources:
        trigger:<left|right>:<soft|full> | motion:lean:<left|right>
      """
    ) + "\n\n"
    + CLILocalized.text(
      "cli.mapping.physical_output_help",
      """
      Physical controller targets:
        physical:rumble:<motor>:<0...1>
        physical:player:<0...4>
        physical:color:<red>:<green>:<blue>
        physical:brightness:<0...1>
        physical:adaptive:<left|right>:off
        physical:adaptive:<left|right>:resistance:<start-position>:<strength>
      """
    )
}
