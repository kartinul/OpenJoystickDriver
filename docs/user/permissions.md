# Permissions

OpenJoystickDriver uses separate macOS permissions for reading controllers, publishing a virtual
controller, and sending keyboard or pointer events.

## Input Monitoring

Input Monitoring lets the app read reports from physical controllers.

```text
System Settings > Privacy & Security > Input Monitoring
```

## Controller Publication

The virtual controller is published through the permission macOS lists under Accessibility.

```text
System Settings > Privacy & Security > Accessibility
```

This permission is separate from the access used for keyboard and pointer output.

## Keyboard & Pointer

Profiles can send keyboard keys, mouse buttons, pointer movement, and scroll events to the frontmost
app. macOS may list this access under Accessibility, but it is separate from controller publication.

Use the **Keyboard & pointer** row in Overview when a profile needs these destinations. If access is
still blocked, open:

```text
System Settings > Privacy & Security > Accessibility
```

## Request Access

Use the matching **Request...** action in Overview for Input Monitoring, controller publication, or
Keyboard & pointer. The menu-bar **Request access...** action opens the same native macOS flow.

If macOS asks for a relaunch, quit and reopen OpenJoystickDriver. The app rechecks permission
after each request; the request result alone is not approval.

Ordinary menu, signal, external, and session-end quits leave the app stopped.
Repeated quit requests wait for runtime teardown. The app does not infer restart
intent from a generic Apple Event or remove Launch Services jobs on exit.
When TCC offers **Quit & Reopen**, macOS owns the reopen.

## Other Approvals

macOS may also ask for:

- **Driver Extension:** required to install or update the optional controller relay.
- **Login Item:** allows macOS 13 or later to start the app at login.

These approvals do not grant Input Monitoring, controller publication, or Keyboard & pointer access.

## Older Alpha Entries

An older alpha may leave an `OpenJoystickDriverDaemon` entry or stale privacy row. Current builds
use neither that helper nor its launchd registration. If System Settings offers a remove control for
the stale entry, remove it manually. OpenJoystickDriver does not reset macOS privacy records.
