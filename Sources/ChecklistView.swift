import AppKit

@MainActor
protocol ChecklistViewDelegate: AnyObject {
  func checklistViewDidChange(_ checklistView: ChecklistView)
}

/// A Google Keep style checklist: Return splits an item, Backspace at its start merges it into the one above,
/// and checked items collect in a collapsible section at the bottom.
final class ChecklistView: NSView, NSTextFieldDelegate {
  weak var delegate: ChecklistViewDelegate?
  private(set) var items: [ChecklistItem]
  private(set) var showsCheckedItems: Bool

  var fontSize: CGFloat {
    didSet { reload() }
  }

  private var font: NSFont { .systemFont(ofSize: fontSize) }
  private let stackView = NSStackView()
  private var fields: [UUID: NSTextField] = [:]
  private var rows: [UUID: ChecklistRowView] = [:]

  init(frame frameRect: NSRect, items: [ChecklistItem], showsCheckedItems: Bool, fontSize: CGFloat) {
    self.items = items.isEmpty ? [ChecklistItem(text: "")] : items
    self.showsCheckedItems = showsCheckedItems
    self.fontSize = fontSize
    super.init(frame: frameRect)

    let scrollView = NSScrollView(frame: bounds)
    scrollView.autoresizingMask = [.width, .height]
    scrollView.drawsBackground = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay
    addSubview(scrollView)

    let documentView = FlippedView()
    documentView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.documentView = documentView

    stackView.orientation = .vertical
    stackView.alignment = .leading
    stackView.spacing = 8
    stackView.translatesAutoresizingMaskIntoConstraints = false
    documentView.addSubview(stackView)

    let clipView = scrollView.contentView
    NSLayoutConstraint.activate([
      documentView.topAnchor.constraint(equalTo: clipView.topAnchor),
      documentView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
      documentView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
      stackView.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 4),
      stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 2),
      stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -16),
      stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -14),
    ])

    reload()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Building rows

  private func reload() {
    // End editing first so the field editor is not torn down mid-keystroke.
    window?.makeFirstResponder(nil)
    stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    fields.removeAll()
    rows.removeAll()

    for item in items where !item.isChecked {
      addFullWidth(makeRow(for: item))
    }
    let addButton = indented(makeTextButton(title: "List item", symbolName: "plus", action: #selector(addItem)))
    stackView.addArrangedSubview(addButton)

    let checkedItems = items.filter(\.isChecked)
    guard !checkedItems.isEmpty else { return }

    let separator = NSBox()
    separator.boxType = .custom
    separator.borderWidth = 0
    separator.fillColor = .noteSeparator
    separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
    stackView.setCustomSpacing(12, after: addButton)
    addFullWidth(separator)
    stackView.setCustomSpacing(10, after: separator)

    let noun = checkedItems.count == 1 ? "item" : "items"
    stackView.addArrangedSubview(
      indented(
        makeTextButton(
          title: "\(checkedItems.count) checked \(noun)",
          symbolName: showsCheckedItems ? "chevron.down" : "chevron.right",
          action: #selector(toggleCheckedItems)
        )
      )
    )
    if showsCheckedItems {
      for item in checkedItems {
        addFullWidth(makeRow(for: item))
      }
    }
  }

  private func addFullWidth(_ view: NSView) {
    stackView.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
  }

  /// Lines a view up with the checkboxes, which sit to the right of the drag handles.
  private func indented(_ view: NSView) -> NSView {
    let container = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ChecklistRowView.handleWidth),
      view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      view.topAnchor.constraint(equalTo: container.topAnchor),
      view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return container
  }

  private func makeRow(for item: ChecklistItem) -> NSView {
    let identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)

    let checkbox = FirstClickButton()
    checkbox.setButtonType(.toggle)
    checkbox.isBordered = false
    checkbox.imagePosition = .imageOnly
    checkbox.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: fontSize + 2, weight: .regular)
    checkbox.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Mark as done")
    checkbox.alternateImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Mark as not done")
    checkbox.contentTintColor = item.isChecked ? .noteAccent : .noteSecondaryText
    checkbox.target = self
    checkbox.action = #selector(toggleItem(_:))
    checkbox.identifier = identifier
    checkbox.state = item.isChecked ? .on : .off

    let field = WrappingTextField(wrappingLabelWithString: "")
    field.identifier = identifier
    field.isEditable = true
    field.focusRingType = .none
    field.placeholderString = "List item"
    field.delegate = self
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    applyStyle(of: item, to: field)
    fields[item.id] = field

    let row = ChecklistRowView()
    let id = item.id
    row.handle.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: max(10, fontSize - 4), weight: .semibold)
    row.handle.onMouseDown = { [weak self] event in self?.dragItem(withID: id, startingWith: event) }
    rows[item.id] = row
    for view in [row.handle, checkbox, field] {
      view.translatesAutoresizingMaskIntoConstraints = false
      row.addSubview(view)
    }
    // Center the circle on the first line of text, so it stays put when the item wraps.
    let firstLineHeight = NSLayoutManager().defaultLineHeight(for: font)
    NSLayoutConstraint.activate([
      row.handle.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      row.handle.widthAnchor.constraint(equalToConstant: ChecklistRowView.handleWidth),
      row.handle.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),
      checkbox.leadingAnchor.constraint(equalTo: row.handle.trailingAnchor),
      checkbox.widthAnchor.constraint(equalToConstant: ceil(fontSize + 6)),
      checkbox.centerYAnchor.constraint(equalTo: field.topAnchor, constant: firstLineHeight / 2),
      field.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 6),
      field.trailingAnchor.constraint(equalTo: row.trailingAnchor),
      field.topAnchor.constraint(equalTo: row.topAnchor),
      field.bottomAnchor.constraint(equalTo: row.bottomAnchor),
    ])
    return row
  }

  private func applyStyle(of item: ChecklistItem, to field: NSTextField) {
    let color: NSColor = item.isChecked ? .noteSecondaryText : .noteText
    var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if item.isChecked {
      attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
    }
    field.font = font
    field.textColor = color
    field.attributedStringValue = NSAttributedString(string: item.text, attributes: attributes)
  }

  private func makeTextButton(title: String, symbolName: String, action: Selector) -> NSButton {
    let button = FirstClickButton(title: title, target: self, action: action)
    button.isBordered = false
    let size = max(12, fontSize - 2)
    button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size - 1, weight: .semibold)
    button.imagePosition = .imageLeading
    button.contentTintColor = .noteSecondaryText
    button.attributedTitle = NSAttributedString(
      string: " \(title)",
      attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.noteSecondaryText]
    )
    return button
  }

  // MARK: - Actions

  @objc private func toggleItem(_ sender: NSButton) {
    guard let index = itemIndex(for: sender) else { return }
    items[index].isChecked = sender.state == .on
    reload()
    delegate?.checklistViewDidChange(self)
  }

  @objc private func addItem() {
    let item = ChecklistItem(text: "")
    items.append(item)
    reload()
    focus(item.id, caret: 0)
    delegate?.checklistViewDidChange(self)
  }

  @objc private func toggleCheckedItems() {
    showsCheckedItems.toggle()
    reload()
    delegate?.checklistViewDidChange(self)
  }

  // MARK: - Reordering

  /// Lifts the row into a floating copy that follows the pointer, while the real row stays behind as an invisible
  /// placeholder that slides into place among the others. On release the copy settles into the placeholder's spot.
  private func dragItem(withID id: UUID, startingWith mouseDown: NSEvent) {
    guard let window, let row = rows[id], let documentView = stackView.superview else { return }
    // End editing first, so the snapshot doesn't capture a caret or selected text.
    window.makeFirstResponder(nil)
    guard let snapshot = row.snapshot() else { return }

    let startFrame = FloatingRowView.frame(around: row.convert(row.bounds, to: documentView))
    let startY = documentView.convert(mouseDown.locationInWindow, from: nil).y
    let floatingRow = FloatingRowView(frame: startFrame, snapshot: snapshot)
    documentView.addSubview(floatingRow)
    row.alphaValue = 0
    NSCursor.closedHand.push()
    var didMove = false

    window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration, mode: .eventTracking) { event, stop in
      guard let event, event.type == .leftMouseDragged else {
        stop.pointee = true
        return
      }
      let y = documentView.convert(event.locationInWindow, from: nil).y
      let maxY = max(0, documentView.bounds.height - startFrame.height)
      floatingRow.setFrameOrigin(NSPoint(x: startFrame.minX, y: min(max(startFrame.minY + y - startY, 0), maxY)))
      if let position = dropPosition(forItemWithID: id, atY: floatingRow.frame.midY, in: documentView),
         moveItem(withID: id, to: position)
      {
        didMove = true
      }
      floatingRow.autoscroll(with: event)
    }

    NSCursor.pop()
    let finalFrame = FloatingRowView.frame(around: row.convert(row.bounds, to: documentView))
    floatingRow.settle(duration: 0.18)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.18
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      floatingRow.animator().frame = finalFrame
    } completionHandler: {
      row.alphaValue = 1
      floatingRow.removeFromSuperview()
    }
    if didMove {
      delegate?.checklistViewDidChange(self)
    }
  }

  /// The item's new position within its section: the number of other items whose middle is above `y`.
  private func dropPosition(forItemWithID id: UUID, atY y: CGFloat, in documentView: NSView) -> Int? {
    guard let item = items.first(where: { $0.id == id }) else { return nil }
    return items
      .filter { $0.isChecked == item.isChecked && $0.id != id }
      .compactMap { rows[$0.id] }
      .filter { $0.convert($0.bounds, to: documentView).midY < y }
      .count
  }

  /// Moves an item to `position` within its section (unchecked or checked) and returns whether anything changed.
  @discardableResult
  func moveItem(withID id: UUID, to position: Int) -> Bool {
    guard let item = items.first(where: { $0.id == id }) else { return false }
    let section = items.filter { $0.isChecked == item.isChecked }.map(\.id)
    let others = section.filter { $0 != id }
    let position = min(max(position, 0), others.count)
    guard position != section.firstIndex(of: id) else { return false }

    let sectionStart = section.compactMap { rows[$0] }.compactMap { stackView.arrangedSubviews.firstIndex(of: $0) }.min()
    items.removeAll { $0.id == id }
    let anchorIndex = position < others.count
      ? items.firstIndex { $0.id == others[position] }
      : items.firstIndex { $0.id == others[others.count - 1] }.map { $0 + 1 }
    items.insert(item, at: anchorIndex ?? items.count)

    if let row = rows[id], let sectionStart {
      stackView.removeArrangedSubview(row)
      stackView.insertArrangedSubview(row, at: sectionStart + position)
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        context.allowsImplicitAnimation = true
        stackView.layoutSubtreeIfNeeded()
      }
    }
    return true
  }

  // MARK: - Editing

  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? NSTextField, let index = itemIndex(for: field) else { return }
    items[index].text = field.stringValue
    field.invalidateIntrinsicContentSize()
    delegate?.checklistViewDidChange(self)
  }

  func controlTextDidEndEditing(_ notification: Notification) {
    guard let field = notification.object as? NSTextField, let index = itemIndex(for: field) else { return }
    applyStyle(of: items[index], to: field)
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    guard let index = itemIndex(for: control) else { return false }
    let selection = textView.selectedRange()

    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      splitItem(at: index, caret: selection.location)
      return true
    case #selector(NSResponder.deleteBackward(_:)):
      guard selection.location == 0, selection.length == 0 else { return false }
      mergeIntoPrevious(at: index)
      return true
    case #selector(NSResponder.moveUp(_:)):
      // Let the caret move between wrapped lines first; jump to the previous item once it can't move any further.
      textView.moveUp(nil)
      if textView.selectedRange() == selection {
        moveFocus(from: items[index].id, by: -1)
      }
      return true
    case #selector(NSResponder.moveDown(_:)):
      textView.moveDown(nil)
      if textView.selectedRange() == selection {
        moveFocus(from: items[index].id, by: 1)
      }
      return true
    default:
      return false
    }
  }

  private func splitItem(at index: Int, caret: Int) {
    let text = items[index].text as NSString
    items[index].text = text.substring(to: caret)
    let newItem = ChecklistItem(text: text.substring(from: caret), isChecked: items[index].isChecked)
    items.insert(newItem, at: index + 1)
    reload()
    focus(newItem.id, caret: 0)
    delegate?.checklistViewDidChange(self)
  }

  private func mergeIntoPrevious(at index: Int) {
    let item = items[index]
    let section = items.filter { $0.isChecked == item.isChecked }.map(\.id)
    guard let position = section.firstIndex(of: item.id), position > 0,
          let previousIndex = items.firstIndex(where: { $0.id == section[position - 1] })
    else { return }

    let caret = (items[previousIndex].text as NSString).length
    items[previousIndex].text += item.text
    let previousID = items[previousIndex].id
    items.remove(at: index)
    reload()
    focus(previousID, caret: caret)
    delegate?.checklistViewDidChange(self)
  }

  private func moveFocus(from id: UUID, by offset: Int) {
    let unchecked = items.filter { !$0.isChecked }.map(\.id)
    let checked = showsCheckedItems ? items.filter(\.isChecked).map(\.id) : []
    let visible = unchecked + checked
    guard let position = visible.firstIndex(of: id), visible.indices.contains(position + offset) else { return }
    focus(visible[position + offset], caret: offset < 0 ? nil : 0)
  }

  /// Focuses an item's field and puts the caret at `caret`, or at the end when `caret` is nil.
  private func focus(_ id: UUID, caret: Int?) {
    guard let field = fields[id] else { return }
    window?.makeFirstResponder(field)
    let length = (field.stringValue as NSString).length
    field.currentEditor()?.selectedRange = NSRange(location: min(caret ?? length, length), length: 0)
  }

  private func itemIndex(for view: NSView) -> Int? {
    guard let rawValue = view.identifier?.rawValue, let id = UUID(uuidString: rawValue) else { return nil }
    return items.firstIndex { $0.id == id }
  }
}

/// A checklist row that shows its drag handle while the pointer is over it, and highlights while being dragged.
private final class ChecklistRowView: NSView {
  static let handleWidth: CGFloat = 16

  let handle = DragHandleImageView()
  private var isHovered = false {
    didSet { updateHandle() }
  }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    handle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag to reorder")
    handle.contentTintColor = .noteSecondaryText
    handle.toolTip = "Drag to reorder"
    updateHandle()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// An image of the row without its drag handle, for the copy that follows the pointer.
  func snapshot() -> NSImage? {
    handle.alphaValue = 0
    defer { updateHandle() }
    guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
    cacheDisplay(in: bounds, to: bitmap)
    let image = NSImage(size: bounds.size)
    image.addRepresentation(bitmap)
    return image
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
  }

  private func updateHandle() {
    handle.alphaValue = isHovered ? 1 : 0
  }
}

/// The copy of a row that follows the pointer while dragging: the note's color, rounded, with a soft shadow.
private final class FloatingRowView: NSView {
  private static let liftedShadowOpacity: Float = 0.2
  private static let padding = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 6)
  private var isLifted = true

  /// The card's frame for a row: a little larger than the row, so the text doesn't touch its edges. The left side
  /// needs no padding because the row starts with its (hidden) drag handle.
  static func frame(around rowFrame: NSRect) -> NSRect {
    NSRect(
      x: rowFrame.minX - padding.left,
      y: rowFrame.minY - padding.top,
      width: rowFrame.width + padding.left + padding.right,
      height: rowFrame.height + padding.top + padding.bottom
    )
  }

  init(frame frameRect: NSRect, snapshot: NSImage) {
    super.init(frame: frameRect)
    wantsLayer = true
    let imageView = NSImageView(image: snapshot)
    imageView.frame = NSRect(
      x: Self.padding.left,
      y: Self.padding.bottom,
      width: snapshot.size.width,
      height: snapshot.size.height
    )
    imageView.imageScaling = .scaleNone
    imageView.imageAlignment = .alignTopLeft
    addSubview(imageView)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    guard let layer else { return }
    layer.cornerRadius = 8
    layer.masksToBounds = false
    layer.backgroundColor = NSColor.noteBackground.cgColor
    layer.shadowColor = NSColor.black.cgColor
    layer.shadowOpacity = isLifted ? Self.liftedShadowOpacity : 0
    layer.shadowRadius = 8
    layer.shadowOffset = CGSize(width: 0, height: -3)
  }

  /// Fades the shadow out, so the row looks like it drops back onto the note.
  func settle(duration: TimeInterval) {
    isLifted = false
    let fade = CABasicAnimation(keyPath: "shadowOpacity")
    fade.fromValue = Self.liftedShadowOpacity
    fade.toValue = 0
    fade.duration = duration
    layer?.add(fade, forKey: "settle")
    layer?.shadowOpacity = 0
  }
}

private final class DragHandleImageView: NSImageView {
  var onMouseDown: ((NSEvent) -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    onMouseDown?(event)
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }
}

private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

/// A text field that wraps to whatever width Auto Layout gives it and grows taller as you type.
private final class WrappingTextField: NSTextField {
  override var intrinsicContentSize: NSSize {
    guard bounds.width > 0, let cell else { return super.intrinsicContentSize }
    var height = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: bounds.width, height: .greatestFiniteMagnitude)).height
    // While editing, the cell still holds the text from before the last keystroke; the field editor has the live text.
    if let editor = currentEditor() as? NSTextView, let layoutManager = editor.layoutManager,
       let textContainer = editor.textContainer
    {
      layoutManager.ensureLayout(for: textContainer)
      let editorHeight = layoutManager.usedRect(for: textContainer).height + editor.textContainerInset.height * 2
      height = max(height, editorHeight)
    }
    return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
  }

  override func setFrameSize(_ newSize: NSSize) {
    let widthChanged = newSize.width != frame.width
    super.setFrameSize(newSize)
    if widthChanged {
      invalidateIntrinsicContentSize()
    }
  }
}
