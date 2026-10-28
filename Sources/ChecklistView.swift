import AppKit

@MainActor
protocol ChecklistViewDelegate: AnyObject {
  func checklistViewDidChange(_ checklistView: ChecklistView)
}

/// A Google Keep style checklist: Return splits an item, Backspace at its start merges it into the one above,
/// and checked items collect in a collapsible section at the bottom. With `showsQuadrants` the open items are
/// split across the four Eisenhower quadrants instead of sitting in one list, and dragging an item into another
/// quadrant re-prioritizes it.
final class ChecklistView: NSView, NSTextFieldDelegate {
  /// Where a row sits. The quadrants only exist while `showsQuadrants` is on; `unsorted` holds the rest.
  private enum Group: Hashable {
    case unsorted
    case quadrant(Quadrant)
    case checked
  }

  /// Below this width the quadrants stack in one column instead of two.
  private static let twoColumnWidth: CGFloat = 260
  private static let columnSpacing: CGFloat = 12

  weak var delegate: ChecklistViewDelegate?
  private(set) var items: [ChecklistItem]
  private(set) var showsCheckedItems: Bool
  let showsQuadrants: Bool

  var fontSize: CGFloat {
    didSet { reload() }
  }

  private var font: NSFont { .systemFont(ofSize: fontSize) }
  /// Space between items, scaled with the text so larger sizes don't feel cramped.
  private var itemSpacing: CGFloat { (fontSize * 0.8).rounded() }
  private var rowHeight: CGFloat { ceil(NSLayoutManager().defaultLineHeight(for: font)) + 4 }
  private var columnCount: Int { showsQuadrants && bounds.width >= Self.twoColumnWidth ? 2 : 1 }
  private var laidOutColumnCount = 0
  private let stackView = NSStackView()
  private var fields: [UUID: NSTextField] = [:]
  private var rows: [UUID: ChecklistRowView] = [:]
  /// Per group: the stack its rows live in, and the larger area a row can be dropped on to land in it.
  private var groupStacks: [Group: NSStackView] = [:]
  private var groupTargets: [Group: NSView] = [:]
  /// Each row's "as wide as its stack" constraint, so a row that moves to another stack can be re-pinned.
  private var rowWidths: [UUID: NSLayoutConstraint] = [:]

  init(frame frameRect: NSRect, items: [ChecklistItem], showsCheckedItems: Bool, showsQuadrants: Bool, fontSize: CGFloat) {
    self.items = items.isEmpty ? [ChecklistItem(text: "")] : items
    self.showsCheckedItems = showsCheckedItems
    self.showsQuadrants = showsQuadrants
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

  /// Reflows the quadrants when the note is resized across the two-column width.
  override func layout() {
    super.layout()
    if columnCount != laidOutColumnCount {
      reload()
    }
  }

  // MARK: - Building rows

  private func group(for item: ChecklistItem) -> Group {
    if item.isChecked { return .checked }
    guard showsQuadrants, let quadrant = item.quadrant else { return .unsorted }
    return .quadrant(quadrant)
  }

  private var openGroups: [Group] {
    showsQuadrants ? [.unsorted] + Quadrant.allCases.map(Group.quadrant) : [.unsorted]
  }

  private func reload() {
    // End editing first so the field editor is not torn down mid-keystroke.
    window?.makeFirstResponder(nil)
    stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    fields.removeAll()
    rows.removeAll()
    rowWidths.removeAll()
    groupStacks.removeAll()
    groupTargets.removeAll()
    stackView.spacing = itemSpacing
    laidOutColumnCount = columnCount

    let addButton = indented(makeTextButton(title: "List item", symbolName: "plus", action: #selector(addItem)))
    let lastOpenView: NSView

    if showsQuadrants {
      addFullWidth(indented(makeCell(for: .unsorted, title: "Unsorted", subtitle: "Drag items into a quadrant below", accessory: addButton), by: 12))
      let cells = Quadrant.allCases.map { makeCell(for: .quadrant($0), title: $0.title, subtitle: $0.subtitle) }
      // The quadrants come in reading order, so the first pair is the important half and the second isn't.
      if columnCount == 2 {
        for pair in stride(from: 0, to: cells.count, by: 2) {
          addFullWidth(indented(makeColumnsRow(cells: Array(cells[pair ..< pair + 2])), by: 12))
        }
      } else {
        cells.forEach { addFullWidth(indented($0, by: 12)) }
      }
      lastOpenView = stackView.arrangedSubviews[stackView.arrangedSubviews.count - 1]
    } else {
      addFullWidth(makeGroupStack(for: .unsorted))
      groupTargets[.unsorted] = groupStacks[.unsorted]
      stackView.addArrangedSubview(addButton)
      lastOpenView = addButton
    }

    let checkedItems = items.filter(\.isChecked)
    guard !checkedItems.isEmpty else { return }

    let separator = NSBox()
    separator.boxType = .custom
    separator.borderWidth = 0
    separator.fillColor = .noteSeparator
    separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
    stackView.setCustomSpacing(itemSpacing + 4, after: lastOpenView)
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
      addFullWidth(makeGroupStack(for: .checked))
      groupTargets[.checked] = groupStacks[.checked]
    }
  }

  /// Two equally sized cells side by side.
  private func makeColumnsRow(cells: [NSView]) -> NSStackView {
    let row = NSStackView(views: cells)
    row.orientation = .horizontal
    row.alignment = .top
    row.distribution = .fillEqually
    row.spacing = Self.columnSpacing
    for cell in cells.dropFirst() {
      cell.heightAnchor.constraint(equalTo: cells[0].heightAnchor).isActive = true
    }
    return row
  }

  /// A group's rows under its title, in a tinted box that is a drop target as a whole, so an empty one can be
  /// hit too.
  private func makeCell(for group: Group, title: String, subtitle: String, accessory: NSView? = nil) -> NSView {
    let cell = NSStackView()
    cell.orientation = .vertical
    cell.alignment = .leading
    cell.spacing = 2

    let header = NSTextField(labelWithString: title.uppercased())
    header.font = .systemFont(ofSize: max(9, fontSize - 4), weight: .semibold)
    header.textColor = .noteSecondaryText
    header.lineBreakMode = .byTruncatingTail
    header.toolTip = subtitle
    add(indented(header), to: cell)
    let caption = NSTextField(labelWithString: subtitle)
    caption.font = .systemFont(ofSize: max(9, fontSize - 4))
    caption.textColor = .noteSecondaryText
    caption.lineBreakMode = .byTruncatingTail
    let captionRow = indented(caption)
    add(captionRow, to: cell)
    let stack = makeGroupStack(for: group, minHeight: rowHeight)
    add(stack, to: cell)
    cell.setCustomSpacing(max(4, itemSpacing - 4), after: captionRow)
    if let accessory {
      // Not pinned to the cell's width: the button should keep its own size, like in the plain list.
      cell.setCustomSpacing(itemSpacing, after: stack)
      cell.addArrangedSubview(accessory)
    }

    let box = QuadrantBoxView()
    cell.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(cell)
    NSLayoutConstraint.activate([
      cell.leadingAnchor.constraint(equalTo: box.leadingAnchor),
      cell.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
      cell.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
      cell.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
    ])
    groupTargets[group] = box
    return box
  }

  private func makeGroupStack(for group: Group, minHeight: CGFloat = 0) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = itemSpacing
    if minHeight > 0 {
      stack.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true
    }
    groupStacks[group] = stack
    for item in items where self.group(for: item) == group {
      pin(makeRow(for: item), withID: item.id, to: stack, at: stack.arrangedSubviews.count)
    }
    return stack
  }

  private func pin(_ row: ChecklistRowView, withID id: UUID, to stack: NSStackView, at index: Int) {
    rowWidths[id]?.isActive = false
    stack.insertArrangedSubview(row, at: index)
    let width = row.widthAnchor.constraint(equalTo: stack.widthAnchor)
    width.isActive = true
    rowWidths[id] = width
  }

  private func add(_ view: NSView, to stack: NSStackView) {
    stack.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
  }

  private func addFullWidth(_ view: NSView) {
    add(view, to: stackView)
  }

  /// Lines a view up with the checkboxes, which sit to the right of the drag handles.
  private func indented(_ view: NSView, by inset: CGFloat = ChecklistRowView.handleWidth) -> NSView {
    let container = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
      view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      view.topAnchor.constraint(equalTo: container.topAnchor),
      view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    return container
  }

  private func makeRow(for item: ChecklistItem) -> ChecklistRowView {
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
    field.onDrag = row.handle.onMouseDown
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
    let start = documentView.convert(mouseDown.locationInWindow, from: nil)
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
      let point = documentView.convert(event.locationInWindow, from: nil)
      // The pointer picks the quadrant, so a card counts as moved as soon as you point into the next lane;
      // the card's own middle still decides where it slots in among the rows there.
      if let target = self.dropTarget(forItemWithID: id, over: point, orderingBy: floatingRow.frame.midY, in: documentView),
         self.moveItem(withID: id, to: target.position, in: target.group)
      {
        didMove = true
      }
      // The card takes the width of the group it's over, so one lifted from the full-width unsorted box narrows
      // to a quadrant and can follow the pointer into the right-hand column.
      let rowFrame = FloatingRowView.frame(around: row.convert(row.bounds, to: documentView))
      let maxY = max(0, documentView.bounds.height - rowFrame.height)
      let maxX = max(0, documentView.bounds.width - rowFrame.width)
      let grabX = min(start.x - startFrame.minX, rowFrame.width - FloatingRowView.minimumGrab)
      // It stays close to the column it would drop into, so it's clear where it lands.
      let slack = FloatingRowView.columnSlack
      let x = min(max(point.x - grabX, rowFrame.minX - slack, 0), rowFrame.minX + slack, maxX)
      let y = min(max(startFrame.minY + point.y - start.y, 0), maxY)
      floatingRow.frame = NSRect(x: x, y: y, width: rowFrame.width, height: floatingRow.frame.height)
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

  /// The group the pointer is over (the nearest one when it is over none), and the row's position within it:
  /// the number of other rows there whose middle is above `y`.
  private func dropTarget(forItemWithID id: UUID, over point: NSPoint, orderingBy y: CGFloat, in documentView: NSView) -> (group: Group, position: Int)? {
    guard let item = items.first(where: { $0.id == id }) else { return nil }
    // Checked items stay among the checked ones; quadrants are for what's still open.
    let candidates: [Group] = item.isChecked ? [.checked] : openGroups
    guard let group = candidates.min(by: { distance(from: point, to: $0, in: documentView) < distance(from: point, to: $1, in: documentView) }),
          let stack = groupStacks[group]
    else { return nil }

    let position = stack.arrangedSubviews
      .filter { $0 !== rows[id] && $0.convert($0.bounds, to: documentView).midY < y }
      .count
    return (group, position)
  }

  /// The quadrant an item would land in when dropped at `point` in this view, or nil for the unsorted strip.
  /// Used by the drag above and by the self-check.
  func dropQuadrant(forItemWithID id: UUID, at point: NSPoint) -> Quadrant? {
    guard let documentView = stackView.superview else { return nil }
    let point = convert(point, to: documentView)
    guard let target = dropTarget(forItemWithID: id, over: point, orderingBy: point.y, in: documentView),
          case .quadrant(let quadrant) = target.group
    else { return nil }
    return quadrant
  }

  /// How far `point` is outside a group's drop area, squared. Zero while it is inside.
  private func distance(from point: NSPoint, to group: Group, in documentView: NSView) -> CGFloat {
    guard let target = groupTargets[group] else { return .greatestFiniteMagnitude }
    let rect = target.convert(target.bounds, to: documentView)
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return dx * dx + dy * dy
  }

  /// Moves an item into a quadrant, or out of all of them when `quadrant` is nil, as dragging it there would.
  @discardableResult
  func move(itemWithID id: UUID, toQuadrant quadrant: Quadrant?, position: Int) -> Bool {
    moveItem(withID: id, to: position, in: quadrant.map(Group.quadrant) ?? .unsorted)
  }

  /// Moves an item to `position` within a group, re-prioritizing it when that's another quadrant, and returns
  /// whether anything changed.
  @discardableResult
  private func moveItem(withID id: UUID, to position: Int, in group: Group) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == id }), let row = rows[id], let stack = groupStacks[group]
    else { return false }
    var item = items[index]
    let currentGroup = self.group(for: item)
    let currentPosition = groupStacks[currentGroup]?.arrangedSubviews.firstIndex(of: row)
    let others = items.filter { $0.id != id && self.group(for: $0) == group }.map(\.id)
    let position = min(max(position, 0), others.count)
    guard group != currentGroup || position != currentPosition else { return false }

    items.remove(at: index)
    switch group {
    case .unsorted: item.quadrant = nil
    case .quadrant(let quadrant): item.quadrant = quadrant
    case .checked: break
    }
    let anchorIndex = position < others.count
      ? items.firstIndex { $0.id == others[position] }
      : others.last.flatMap { last in items.firstIndex { $0.id == last }.map { $0 + 1 } }
    items.insert(item, at: anchorIndex ?? items.count)

    groupStacks[currentGroup]?.removeArrangedSubview(row)
    pin(row, withID: id, to: stack, at: position)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      context.allowsImplicitAnimation = true
      layoutSubtreeIfNeeded()
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
    var newItem = items[index]
    newItem.id = UUID()
    newItem.text = text.substring(from: caret)
    items.insert(newItem, at: index + 1)
    reload()
    focus(newItem.id, caret: 0)
    delegate?.checklistViewDidChange(self)
  }

  private func mergeIntoPrevious(at index: Int) {
    let item = items[index]
    let siblings = items.filter { group(for: $0) == group(for: item) }.map(\.id)
    guard let position = siblings.firstIndex(of: item.id), position > 0,
          let previousIndex = items.firstIndex(where: { $0.id == siblings[position - 1] })
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
    var groups = openGroups
    if showsCheckedItems {
      groups.append(.checked)
    }
    let visible = groups.flatMap { group in items.filter { self.group(for: $0) == group }.map(\.id) }
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
  /// How much of the card stays to the right of the pointer when it narrows under it.
  static let minimumGrab: CGFloat = 24
  /// How far the card can follow the pointer sideways out of the column it would drop into.
  static let columnSlack: CGFloat = 16
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
    // Clips the snapshot when the card narrows to fit a quadrant.
    imageView.autoresizingMask = [.width]
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

/// The tinted, rounded background of the unsorted items and of each quadrant.
private final class QuadrantBoxView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.noteSeparator.cgColor
    layer?.cornerRadius = 12
    layer?.cornerCurve = .continuous
  }
}

private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

/// A text field that wraps to whatever width Auto Layout gives it and grows taller as you type.
/// Dragging the text of an item that isn't being edited moves the item, like dragging its handle. A click without
/// dragging starts editing as usual.
private final class WrappingTextField: NSTextField {
  private static let dragThreshold: CGFloat = 4

  var onDrag: ((NSEvent) -> Void)?

  override func mouseDown(with event: NSEvent) {
    guard let window, let onDrag else { return super.mouseDown(with: event) }
    while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseUp {
        // Hand the click back to the text field, which tracks it until this mouse-up.
        window.postEvent(next, atStart: true)
        return super.mouseDown(with: event)
      }
      if hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y) >= Self.dragThreshold {
        return onDrag(event)
      }
    }
  }

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
