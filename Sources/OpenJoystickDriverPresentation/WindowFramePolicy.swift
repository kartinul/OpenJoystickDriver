#if canImport(AppKit)

  import AppKit

  enum WindowFramePolicy {
    static func fittingFrame(_ frame: NSRect, minimumSize: NSSize) -> NSRect {
      let width = max(frame.width, minimumSize.width)
      let height = max(frame.height, minimumSize.height)
      return NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
    }

    static func fittingSize(_ size: NSSize, minimumSize: NSSize) -> NSSize {
      NSSize(
        width: max(size.width, minimumSize.width),
        height: max(size.height, minimumSize.height)
      )
    }

    static func clampedFrame(
      _ frame: NSRect,
      to visibleFrame: NSRect,
      minimumSize: NSSize = .zero
    ) -> NSRect {
      let fitted = fittingFrame(frame, minimumSize: minimumSize)
      let width = max(minimumSize.width, min(fitted.width, visibleFrame.width))
      let height = max(minimumSize.height, min(fitted.height, visibleFrame.height))
      let x = min(max(fitted.minX, visibleFrame.minX), visibleFrame.maxX - width)
      let y = min(max(fitted.minY, visibleFrame.minY), visibleFrame.maxY - height)
      return NSRect(x: x, y: y, width: width, height: height)
    }

    @MainActor
    static func clamp(_ window: NSWindow, minimumSize: NSSize = .zero) {
      guard let screen = window.screen ?? NSScreen.main else { return }
      window.setFrame(
        clampedFrame(window.frame, to: screen.visibleFrame, minimumSize: minimumSize),
        display: false
      )
    }
  }

#endif
