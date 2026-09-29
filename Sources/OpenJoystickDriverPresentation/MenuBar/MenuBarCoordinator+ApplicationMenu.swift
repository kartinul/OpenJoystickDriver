#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import Combine
  import Darwin
  import OpenJoystickDriverKit
  import SwiftUI
  import UserNotifications

  extension MenuBarCoordinator {
    func makeApplicationMenu() -> NSMenu {
      let menu = NSMenu(title: OJDLocalized.string("app.name", fallback: "OpenJoystickDriver"))

      let applicationMenu = NSMenu(
        title: OJDLocalized.string("app.name", fallback: "OpenJoystickDriver")
      )
      let about = NSMenuItem(
        title: OJDLocalized.string("menu.about", fallback: "About OpenJoystickDriver"),
        action: #selector(showAbout(_:)),
        keyEquivalent: ""
      )
      about.target = self
      about.image = menuImage(symbol: "info.circle")
      applicationMenu.addItem(about)
      applicationMenu.addItem(.separator())
      let settings = NSMenuItem(
        title: OJDLocalized.string("menu.settings", fallback: "Settings..."),
        action: #selector(openSettings(_:)),
        keyEquivalent: ","
      )
      settings.target = self
      settings.keyEquivalentModifierMask = [.command]
      settings.image = menuImage(symbol: "gearshape")
      applicationMenu.addItem(settings)
      applicationMenu.addItem(.separator())
      let quit = NSMenuItem(
        title: OJDLocalized.string("menu.quit", fallback: "Quit OpenJoystickDriver"),
        action: #selector(quit(_:)),
        keyEquivalent: "q"
      )
      quit.target = self
      quit.keyEquivalentModifierMask = [.command]
      quit.image = menuImage(symbol: "power")
      applicationMenu.addItem(quit)
      let applicationItem = NSMenuItem()
      applicationItem.submenu = applicationMenu
      menu.addItem(applicationItem)

      // Install real responder-chain menus rather than empty placeholders.  Text fields and the
      // profile editor therefore retain the familiar macOS editing commands even though the app
      // itself is primarily a menu-bar facade.
      let editMenu = NSMenu(title: OJDLocalized.string("menu.edit", fallback: "Edit"))
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.undo", fallback: "Undo"),
        action: #selector(UndoManager.undo),
        keyEquivalent: "z"
      )
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.redo", fallback: "Redo"),
        action: #selector(UndoManager.redo),
        keyEquivalent: "Z"
      )
      editMenu.addItem(.separator())
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.cut", fallback: "Cut"),
        action: #selector(NSText.cut(_:)),
        keyEquivalent: "x"
      )
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.copy", fallback: "Copy"),
        action: #selector(NSText.copy(_:)),
        keyEquivalent: "c"
      )
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.paste", fallback: "Paste"),
        action: #selector(NSText.paste(_:)),
        keyEquivalent: "v"
      )
      editMenu.addItem(
        withTitle: OJDLocalized.string("menu.selectAll", fallback: "Select All"),
        action: #selector(NSText.selectAll(_:)),
        keyEquivalent: "a"
      )
      let editItem = NSMenuItem(
        title: OJDLocalized.string("menu.edit", fallback: "Edit"),
        action: nil,
        keyEquivalent: ""
      )
      editItem.submenu = editMenu
      menu.addItem(editItem)

      let windowMenu = NSMenu(title: OJDLocalized.string("menu.window", fallback: "Window"))
      windowMenu.addItem(
        withTitle: OJDLocalized.string("menu.minimize", fallback: "Minimize"),
        action: #selector(NSWindow.performMiniaturize(_:)),
        keyEquivalent: "m"
      )
      windowMenu.addItem(
        withTitle: OJDLocalized.string("menu.zoom", fallback: "Zoom"),
        action: #selector(NSWindow.performZoom(_:)),
        keyEquivalent: ""
      )
      windowMenu.addItem(.separator())
      windowMenu.addItem(
        withTitle: OJDLocalized.string("menu.bringAllToFront", fallback: "Bring All to Front"),
        action: #selector(NSApplication.arrangeInFront(_:)),
        keyEquivalent: ""
      )
      let windowItem = NSMenuItem(
        title: OJDLocalized.string("menu.window", fallback: "Window"),
        action: nil,
        keyEquivalent: ""
      )
      windowItem.submenu = windowMenu
      menu.addItem(windowItem)
      NSApplication.shared.windowsMenu = windowMenu
      return menu
    }

    @objc
    func saveSupportReport(_ sender: Any?) {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("debug.saveReportPanel", fallback: "Save Debug Report")
      panel.nameFieldStringValue = supportReport.defaultSupportReportFilename
      panel.canCreateDirectories = true
      panel.begin { [supportReport] response in
        guard response == .OK, let outputURL = panel.url else { return }
        Task { @MainActor in await supportReport.saveSupportReport(to: outputURL) }
      }
    }

    @objc
    func saveSupportLogs(_ sender: Any?) {
      let panel = NSSavePanel()
      panel.title = OJDLocalized.string("debug.saveLogsPanel", fallback: "Save Debug Logs")
      panel.nameFieldStringValue = supportReport.defaultSupportLogsFilename
      panel.canCreateDirectories = true
      panel.begin { [supportReport] response in
        guard response == .OK, let outputURL = panel.url else { return }
        Task { @MainActor in await supportReport.saveSupportLogs(to: outputURL) }
      }
    }

    @objc
    func openProjectPage(_ sender: Any?) {
      guard let url = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver") else { return }
      NSWorkspace.shared.open(url)
    }

    @objc
    func showAbout(_ sender: Any?) {
      let repositoryTitle = OJDLocalized.string("menu.projectPage", fallback: "GitHub")
      let credits = NSMutableAttributedString(string: repositoryTitle)
      if let url = URL(string: "https://github.com/xsyetopz/OpenJoystickDriver") {
        credits.addAttribute(.link, value: url, range: NSRange(location: 0, length: credits.length))
      }
      var options: [NSApplication.AboutPanelOptionKey: Any] = [
        .applicationName: OJDLocalized.string("app.name", fallback: "OpenJoystickDriver"),
        .applicationVersion: ApplicationVersion.display, .credits: credits,
      ]
      if let icon = NSImage(named: NSImage.applicationIconName) { options[.applicationIcon] = icon }
      NSApplication.shared.orderFrontStandardAboutPanel(options: options)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }

#else

  final class MenuBarCoordinator {}

#endif
