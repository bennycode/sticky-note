import AppKit

extension NSColor {
  static var noteBackground: NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0.36, green: 0.31, blue: 0.12, alpha: 1)
        : NSColor(srgbRed: 1.0, green: 0.93, blue: 0.56, alpha: 1)
    }
  }

  static var noteText: NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 1.0, green: 0.96, blue: 0.82, alpha: 1)
        : NSColor(srgbRed: 0.2, green: 0.17, blue: 0.05, alpha: 1)
    }
  }

  static var noteSecondaryText: NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 1.0, green: 0.96, blue: 0.82, alpha: 0.5)
        : NSColor(srgbRed: 0.2, green: 0.17, blue: 0.05, alpha: 0.5)
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
    layer.cornerRadius = 20
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
final class FirstClickButton: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The strip along the top edge that moves the window, since the note content takes every click below it.
final class DragHandleView: NSView {
  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}
