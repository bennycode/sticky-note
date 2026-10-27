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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSMenuItemValidation,
  ChecklistViewDelegate
{
  private static let frameAutosaveName = "StickyNoteWindow"
  private static let handleHeight: CGFloat = 24
  private static let footerHeight: CGFloat = 30

  private let store = NoteStore()
  private var note = Note()
  private var window: NoteWindow!
  private var contentArea: NSView!
  private var checkboxesButton: NSButton!
  private var textScrollView: NSScrollView!
  private var textView: NSTextView!

  func applicationDidFinishLaunching(_ notification: Notification) {
    note = store.load()
    NSApp.mainMenu = makeMainMenu()
    window = makeWindow()
    showNoteContent()
    window.orderFrontRegardless()
  }

  func applicationWillTerminate(_ notification: Notification) {
    store.save(note)
  }

  func textDidChange(_ notification: Notification) {
    note.text = textView.string
    store.save(note)
  }

  func checklistViewDidChange(_ checklistView: ChecklistView) {
    note.items = checklistView.items
    note.showsCheckedItems = checklistView.showsCheckedItems
    store.save(note)
  }

  private func showNoteContent() {
    contentArea.subviews.forEach { $0.removeFromSuperview() }
    switch note.mode {
    case .text:
      textView.string = note.text
      textScrollView.frame = contentArea.bounds
      contentArea.addSubview(textScrollView)
    case .checklist:
      let checklistView = ChecklistView(
        frame: contentArea.bounds,
        items: note.items,
        showsCheckedItems: note.showsCheckedItems
      )
      checklistView.autoresizingMask = [.width, .height]
      checklistView.delegate = self
      contentArea.addSubview(checklistView)
    }
    updateCheckboxesButton()
  }

  private func updateCheckboxesButton() {
    let isChecklist = note.mode == .checklist
    checkboxesButton.image = NSImage(
      systemSymbolName: isChecklist ? "checkmark.square.fill" : "checkmark.square",
      accessibilityDescription: isChecklist ? "Hide Checkboxes" : "Show Checkboxes"
    )
    checkboxesButton.contentTintColor = isChecklist ? .noteText : .noteSecondaryText
    checkboxesButton.toolTip = isChecklist ? "Hide Checkboxes (⇧⌘L)" : "Show Checkboxes (⇧⌘L)"
  }

  @objc private func toggleCheckboxes(_ sender: Any?) {
    switch note.mode {
    case .text:
      note.items = note.text
        .components(separatedBy: .newlines)
        .compactMap(ChecklistItem.init(line:))
      note.mode = .checklist
    case .checklist:
      note.text = note.items.map(\.text).joined(separator: "\n")
      note.items = []
      note.mode = .text
    }
    store.save(note)
    showNoteContent()
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

    contentArea = NoteContentView(
      frame: NSRect(
        x: 0,
        y: Self.footerHeight,
        width: size.width,
        height: size.height - Self.handleHeight - Self.footerHeight
      )
    )
    contentArea.autoresizingMask = [.width, .height]
    background.addSubview(contentArea)
    window.initialFirstResponder = contentArea

    checkboxesButton = FirstClickButton(frame: NSRect(x: 10, y: 6, width: 22, height: 22))
    checkboxesButton.isBordered = false
    checkboxesButton.imageScaling = .scaleProportionallyUpOrDown
    checkboxesButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    checkboxesButton.target = self
    checkboxesButton.action = #selector(toggleCheckboxes(_:))
    checkboxesButton.autoresizingMask = [.maxXMargin, .maxYMargin]
    background.addSubview(checkboxesButton)

    textScrollView = NSTextView.scrollableTextView()
    textScrollView.autoresizingMask = [.width, .height]
    textScrollView.drawsBackground = false
    textScrollView.hasVerticalScroller = true
    textScrollView.autohidesScrollers = true
    textScrollView.scrollerStyle = .overlay

    textView = textScrollView.documentView as? NSTextView
    textView.drawsBackground = false
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.font = .systemFont(ofSize: 15)
    textView.textColor = .noteText
    textView.insertionPointColor = .noteText
    textView.textContainerInset = NSSize(width: 12, height: 4)
    textView.delegate = self

    window.setFrameUsingName(Self.frameAutosaveName)
    window.setFrameAutosaveName(Self.frameAutosaveName)
    return window
  }

  private func makeContextMenu() -> NSMenu {
    let menu = NSMenu()
    let checkboxesItem = NSMenuItem(title: "Show Checkboxes", action: #selector(toggleCheckboxes(_:)), keyEquivalent: "")
    checkboxesItem.target = self
    menu.addItem(checkboxesItem)
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

    let noteMenu = NSMenu(title: "Note")
    let checkboxesItem = NSMenuItem(title: "Show Checkboxes", action: #selector(toggleCheckboxes(_:)), keyEquivalent: "l")
    checkboxesItem.keyEquivalentModifierMask = [.command, .shift]
    checkboxesItem.target = self
    noteMenu.addItem(checkboxesItem)
    let noteMenuItem = NSMenuItem()
    noteMenuItem.submenu = noteMenu
    mainMenu.addItem(noteMenuItem)

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
    switch menuItem.action {
    case #selector(toggleCheckboxes(_:)):
      menuItem.title = note.mode == .checklist ? "Hide Checkboxes" : "Show Checkboxes"
    case #selector(toggleOpenAtLogin(_:)):
      menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    default:
      break
    }
    return true
  }
}
