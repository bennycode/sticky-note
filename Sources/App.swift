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
  private static let handleHeight: CGFloat = 28
  private static let footerHeight: CGFloat = 40
  private static let fontSizes: [Double] = [11, 13, 15, 17, 20, 24, 28, 32]

  private let store = NoteStore()
  private var note = Note()
  private var window: NoteWindow!
  private var contentArea: NSView!
  private var checklistView: ChecklistView?
  private var checkboxesButton: FooterIconButton!
  private var matrixButton: FooterIconButton!
  private let fontSizePopover = NSPopover()
  private let fontSizeController = FontSizeViewController()
  private var textScrollView: NSScrollView!
  private var textView: NSTextView!

  func applicationDidFinishLaunching(_ notification: Notification) {
    note = store.load()
    NSApp.mainMenu = makeMainMenu()
    fontSizeController.onSmaller = { [weak self] in self?.stepFontSize(by: -1) }
    fontSizeController.onBigger = { [weak self] in self?.stepFontSize(by: 1) }
    fontSizePopover.contentViewController = fontSizeController
    fontSizePopover.behavior = .transient
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
    checklistView = nil
    switch note.mode {
    case .text:
      textView.string = note.text
      textView.font = .systemFont(ofSize: note.fontSize)
      textScrollView.frame = contentArea.bounds
      contentArea.addSubview(textScrollView)
    case .checklist, .matrix:
      let checklistView = ChecklistView(
        frame: contentArea.bounds,
        items: note.items,
        showsCheckedItems: note.showsCheckedItems,
        showsQuadrants: note.mode == .matrix,
        fontSize: note.fontSize
      )
      checklistView.autoresizingMask = [.width, .height]
      checklistView.delegate = self
      contentArea.addSubview(checklistView)
      self.checklistView = checklistView
    }
    updateFooterButtons()
  }

  @objc private func toggleFontSizePopover(_ sender: NSButton) {
    if fontSizePopover.isShown {
      fontSizePopover.performClose(nil)
      return
    }
    updateFontSizeController()
    fontSizePopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: sender.isFlipped ? .minY : .maxY)
  }

  @objc private func increaseFontSize(_ sender: Any?) {
    stepFontSize(by: 1)
  }

  @objc private func decreaseFontSize(_ sender: Any?) {
    stepFontSize(by: -1)
  }

  @objc private func resetFontSize(_ sender: Any?) {
    setFontSize(Note.defaultFontSize)
  }

  private func stepFontSize(by step: Int) {
    let sizes = Self.fontSizes
    let current = sizes.firstIndex { $0 >= note.fontSize } ?? sizes.count - 1
    setFontSize(sizes[min(max(current + step, 0), sizes.count - 1)])
  }

  private func setFontSize(_ size: Double) {
    guard size != note.fontSize else { return }
    note.fontSize = size
    store.save(note)
    textView.font = .systemFont(ofSize: size)
    checklistView?.fontSize = size
    updateFontSizeController()
  }

  private var canShrinkFont: Bool { note.fontSize > Self.fontSizes[0] }
  private var canGrowFont: Bool { note.fontSize < Self.fontSizes[Self.fontSizes.count - 1] }

  private func updateFontSizeController() {
    fontSizeController.update(fontSize: note.fontSize, canShrink: canShrinkFont, canGrow: canGrowFont)
  }

  private func updateFooterButtons() {
    let isList = note.mode != .text
    checkboxesButton.setSymbol("checklist", label: isList ? "Hide Checkboxes" : "Show Checkboxes")
    checkboxesButton.contentTintColor = isList ? .noteAccent : .noteSecondaryText
    checkboxesButton.toolTip = isList ? "Hide Checkboxes (⇧⌘L)" : "Show Checkboxes (⇧⌘L)"

    let isMatrix = note.mode == .matrix
    matrixButton.contentTintColor = isMatrix ? .noteAccent : .noteSecondaryText
    matrixButton.setAccessibilityLabel(isMatrix ? "Hide Quadrants" : "Show Quadrants")
    matrixButton.toolTip = isMatrix ? "Hide Quadrants (⇧⌘M)" : "Eisenhower Matrix (⇧⌘M)"
  }

  /// Turns the note's lines into checklist items, or its items back into lines.
  @objc private func toggleCheckboxes(_ sender: Any?) {
    switch note.mode {
    case .text:
      note.items = note.text
        .components(separatedBy: .newlines)
        .compactMap(ChecklistItem.init(line:))
      note.mode = .checklist
    case .checklist, .matrix:
      note.text = note.items.map(\.text).joined(separator: "\n")
      note.items = []
      note.mode = .text
    }
    store.save(note)
    showNoteContent()
  }

  /// Switches the checklist between one list and the four quadrants. Each item keeps the quadrant it was dragged
  /// into, so switching back and forth doesn't lose the sorting.
  @objc private func toggleMatrix(_ sender: Any?) {
    if note.mode == .matrix {
      note.mode = .checklist
    } else {
      if note.mode == .text {
        toggleCheckboxes(sender)
      }
      note.mode = .matrix
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

    checkboxesButton = FooterIconButton(symbolName: "checklist", label: "Show Checkboxes")
    checkboxesButton.setFrameOrigin(NSPoint(x: 12, y: 8))
    checkboxesButton.target = self
    checkboxesButton.action = #selector(toggleCheckboxes(_:))
    checkboxesButton.autoresizingMask = [.maxXMargin, .maxYMargin]
    background.addSubview(checkboxesButton)

    matrixButton = FooterIconButton(symbolName: "square.grid.2x2", label: "Show Quadrants")
    matrixButton.setFrameOrigin(NSPoint(x: 12 + checkboxesButton.frame.width, y: 8))
    matrixButton.target = self
    matrixButton.action = #selector(toggleMatrix(_:))
    matrixButton.autoresizingMask = [.maxXMargin, .maxYMargin]
    background.addSubview(matrixButton)

    let fontSizeButton = FooterIconButton(symbolName: "textformat.size", label: "Text Size")
    fontSizeButton.setFrameOrigin(NSPoint(x: size.width - 28 - fontSizeButton.frame.width, y: 8))
    fontSizeButton.toolTip = "Text Size (⌘+ / ⌘−)"
    fontSizeButton.target = self
    fontSizeButton.action = #selector(toggleFontSizePopover(_:))
    fontSizeButton.autoresizingMask = [.minXMargin, .maxYMargin]
    background.addSubview(fontSizeButton)

    // Inset far enough that the lines stay clear of the rounded corner.
    let resizeGrip = ResizeGripView(frame: NSRect(x: size.width - 24, y: 9, width: 14, height: 14))
    resizeGrip.toolTip = "Drag to resize"
    resizeGrip.autoresizingMask = [.minXMargin, .maxYMargin]
    background.addSubview(resizeGrip)

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
    textView.font = .systemFont(ofSize: note.fontSize)
    textView.textColor = .noteText
    textView.insertionPointColor = .noteText
    textView.textContainerInset = NSSize(width: 14, height: 4)
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
    let matrixItem = NSMenuItem(title: "Eisenhower Matrix", action: #selector(toggleMatrix(_:)), keyEquivalent: "")
    matrixItem.target = self
    menu.addItem(matrixItem)
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
    let matrixItem = NSMenuItem(title: "Eisenhower Matrix", action: #selector(toggleMatrix(_:)), keyEquivalent: "m")
    matrixItem.keyEquivalentModifierMask = [.command, .shift]
    matrixItem.target = self
    noteMenu.addItem(matrixItem)
    noteMenu.addItem(.separator())
    // ⌘= is listed too, because ⌘+ needs Shift on most keyboards.
    for (title, action, key) in [
      ("Bigger", #selector(increaseFontSize(_:)), "+"),
      ("Bigger", #selector(increaseFontSize(_:)), "="),
      ("Smaller", #selector(decreaseFontSize(_:)), "-"),
      ("Default Size", #selector(resetFontSize(_:)), "0"),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.target = self
      noteMenu.addItem(item)
    }
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
      menuItem.title = note.mode == .text ? "Show Checkboxes" : "Hide Checkboxes"
    case #selector(toggleMatrix(_:)):
      menuItem.state = note.mode == .matrix ? .on : .off
    case #selector(toggleOpenAtLogin(_:)):
      menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    case #selector(increaseFontSize(_:)):
      return canGrowFont
    case #selector(decreaseFontSize(_:)):
      return canShrinkFont
    default:
      break
    }
    return true
  }
}
