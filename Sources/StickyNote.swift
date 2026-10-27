import AppKit
import ServiceManagement

@main
@MainActor
enum StickyNoteApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
      app.run()
    }
  }
}

final class NoteStore {
  private let fileURL: URL

  init() {
    let directory = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("StickyNote", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    fileURL = directory.appendingPathComponent("note.txt")
  }

  func load() -> String {
    (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
  }

  func save(_ text: String) {
    try? text.write(to: fileURL, atomically: true, encoding: .utf8)
  }
}

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

/// The strip along the top edge that moves the window, since the text view takes every click below it.
final class DragHandleView: NSView {
  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSMenuItemValidation {
  private static let frameAutosaveName = "StickyNoteWindow"
  private static let handleHeight: CGFloat = 24

  private let store = NoteStore()
  private var window: NoteWindow!
  private var textView: NSTextView!

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()
    window = makeWindow()
    window.orderFrontRegardless()
  }

  func applicationWillTerminate(_ notification: Notification) {
    store.save(textView.string)
  }

  func textDidChange(_ notification: Notification) {
    store.save(textView.string)
  }

  private func makeWindow() -> NoteWindow {
    let size = NSSize(width: 280, height: 280)
    let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let defaultFrame = NSRect(
      x: visibleFrame.minX + 40,
      y: visibleFrame.maxY - 40 - size.height,
      width: size.width,
      height: size.height
    )

    let window = NoteWindow(
      contentRect: defaultFrame,
      styleMask: [.borderless, .resizable],
      backing: .buffered,
      defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 160, height: 120)
    // Sit just above the desktop icons, below regular windows, like a widget.
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

    let background = NoteBackgroundView(frame: NSRect(origin: .zero, size: size))
    background.autoresizingMask = [.width, .height]
    background.menu = makeContextMenu()
    window.contentView = background

    let handle = DragHandleView(
      frame: NSRect(x: 0, y: size.height - Self.handleHeight, width: size.width, height: Self.handleHeight)
    )
    handle.autoresizingMask = [.width, .minYMargin]
    handle.toolTip = "Drag to move, right-click for options"
    background.addSubview(handle)

    let scrollView = NSTextView.scrollableTextView()
    scrollView.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - Self.handleHeight)
    scrollView.autoresizingMask = [.width, .height]
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay

    let textView = scrollView.documentView as! NSTextView
    textView.drawsBackground = false
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.font = .systemFont(ofSize: 15)
    textView.textColor = .noteText
    textView.insertionPointColor = .noteText
    textView.textContainerInset = NSSize(width: 12, height: 4)
    textView.string = store.load()
    textView.delegate = self
    background.addSubview(scrollView)
    self.textView = textView

    window.setFrameUsingName(Self.frameAutosaveName)
    window.setFrameAutosaveName(Self.frameAutosaveName)
    return window
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu()
    let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleOpenAtLogin(_:)), keyEquivalent: "")
    loginItem.target = self
    menu.addItem(loginItem)
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Sticky Note", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    return menu
  }

  /// Accessory apps have no visible menu bar, but the key equivalents (⌘C, ⌘V, ⌘Z, ⌘Q) still come from this menu.
  private func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    let appMenu = NSMenu()
    appMenu.addItem(NSMenuItem(title: "Quit Sticky Note", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    let appMenuItem = NSMenuItem()
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(redo)
    editMenu.addItem(.separator())
    editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    let editMenuItem = NSMenuItem()
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    return mainMenu
  }

  @objc private func toggleOpenAtLogin(_ sender: NSMenuItem) {
    let service = SMAppService.mainApp
    do {
      if service.status == .enabled {
        try service.unregister()
      } else {
        try service.register()
      }
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(toggleOpenAtLogin(_:)) {
      menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    return true
  }
}
