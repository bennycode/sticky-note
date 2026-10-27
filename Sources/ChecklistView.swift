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
      stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 16),
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

    for item in items where !item.isChecked {
      addFullWidth(makeRow(for: item))
    }
    let addButton = makeTextButton(title: "List item", symbolName: "plus", action: #selector(addItem))
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
      makeTextButton(
        title: "\(checkedItems.count) checked \(noun)",
        symbolName: showsCheckedItems ? "chevron.down" : "chevron.right",
        action: #selector(toggleCheckedItems)
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

    let row = NSView()
    for view in [checkbox, field] {
      view.translatesAutoresizingMaskIntoConstraints = false
      row.addSubview(view)
    }
    // Center the circle on the first line of text, so it stays put when the item wraps.
    let firstLineHeight = NSLayoutManager().defaultLineHeight(for: font)
    NSLayoutConstraint.activate([
      checkbox.leadingAnchor.constraint(equalTo: row.leadingAnchor),
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
