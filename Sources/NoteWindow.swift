import AppKit

extension NSColor {
  static var noteBackground: NSColor {
    dynamic(light: NSColor(srgbRed: 1.0, green: 0.96, blue: 0.75, alpha: 1), dark: NSColor(srgbRed: 0.24, green: 0.22, blue: 0.14, alpha: 1))
  }

  static var noteText: NSColor {
    dynamic(light: NSColor(srgbRed: 0.13, green: 0.12, blue: 0.08, alpha: 1), dark: NSColor(srgbRed: 0.98, green: 0.95, blue: 0.86, alpha: 1))
  }

  static var noteSecondaryText: NSColor {
    dynamic(light: NSColor(srgbRed: 0.13, green: 0.12, blue: 0.08, alpha: 0.45), dark: NSColor(srgbRed: 0.98, green: 0.95, blue: 0.86, alpha: 0.45))
  }

  static var noteSeparator: NSColor {
    dynamic(light: NSColor(srgbRed: 0.13, green: 0.12, blue: 0.08, alpha: 0.1), dark: NSColor(srgbRed: 0.98, green: 0.95, blue: 0.86, alpha: 0.12))
  }

  static var noteAccent: NSColor {
    dynamic(light: NSColor(srgbRed: 0.85, green: 0.6, blue: 0.05, alpha: 1), dark: NSColor(srgbRed: 1.0, green: 0.78, blue: 0.25, alpha: 1))
  }

  private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    }
  }
}

final class NoteWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class NoteBackgroundView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    guard let layer else { return }
    layer.backgroundColor = NSColor.noteBackground.cgColor
    layer.cornerRadius = 24
    layer.cornerCurve = .continuous
    layer.masksToBounds = true
  }
}

/// Holds the note content. It accepts first responder so the window has something harmless to focus when it
/// becomes key, instead of selecting the first checklist item.
final class NoteContentView: NSView {
  override var acceptsFirstResponder: Bool { true }
}

/// A button that responds to the first click even while another app is active, like controls on a widget.
class FirstClickButton: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless SF Symbol button for the note's footer.
final class FooterIconButton: FirstClickButton {
  init(symbolName: String, label: String) {
    super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
    isBordered = false
    imagePosition = .imageOnly
    symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
    contentTintColor = .noteSecondaryText
    setSymbol(symbolName, label: label)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setSymbol(_ symbolName: String, label: String) {
    image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
    setAccessibilityLabel(label)
  }
}

/// The diagonal lines in the bottom-right corner. Dragging them resizes the note while its top-left corner stays put.
final class ResizeGripView: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    let path = NSBezierPath()
    path.lineWidth = 1.5
    path.lineCapStyle = .round
    for length in [6.0, 11.0] {
      path.move(to: NSPoint(x: bounds.maxX - length, y: bounds.minY + 1))
      path.line(to: NSPoint(x: bounds.maxX - 1, y: bounds.minY + length))
    }
    NSColor.noteSecondaryText.setStroke()
    path.stroke()
  }

  override func resetCursorRects() {
    if #available(macOS 15.0, *) {
      addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
    } else {
      addCursorRect(bounds, cursor: .crosshair)
    }
  }

  override func mouseDown(with event: NSEvent) {
    guard let window else { return }
    let startFrame = window.frame
    let startPoint = NSEvent.mouseLocation
    window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
      guard let event, event.type == .leftMouseDragged else {
        stop.pointee = true
        return
      }
      let point = NSEvent.mouseLocation
      let width = max(window.minSize.width, startFrame.width + point.x - startPoint.x)
      let height = max(window.minSize.height, startFrame.height - (point.y - startPoint.y))
      window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height), display: true)
    }
  }
}

/// The strip along the top edge that moves the window, since the note content takes every click below it.
final class DragHandleView: NSView {
  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}
