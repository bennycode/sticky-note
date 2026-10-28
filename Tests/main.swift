import AppKit

/// Checks that moving items between quadrants keeps the list intact. Run it with ./test.sh.
MainActor.assumeIsolated {
  let milk = ChecklistItem(text: "Buy milk")
  let anna = ChecklistItem(text: "Reply to Anna")
  let cables = ChecklistItem(text: "Order cables", quadrant: .delegate)
  let invoice = ChecklistItem(text: "Pay invoice", isChecked: true)
  let view = ChecklistView(
    frame: NSRect(x: 0, y: 0, width: 320, height: 400),
    items: [milk, anna, cables, invoice],
    showsCheckedItems: true,
    showsQuadrants: true,
    fontSize: 15
  )

  func texts(in quadrant: Quadrant?) -> [String] {
    view.items.filter { !$0.isChecked && $0.quadrant == quadrant }.map(\.text)
  }

  // Into a quadrant that already has an item, above it.
  assert(view.move(itemWithID: milk.id, toQuadrant: .delegate, position: 0))
  assert(texts(in: .delegate) == ["Buy milk", "Order cables"], "\(texts(in: .delegate))")
  assert(texts(in: nil) == ["Reply to Anna"])

  // Within the same quadrant, and the same spot again is not a move.
  assert(view.move(itemWithID: milk.id, toQuadrant: .delegate, position: 1))
  assert(texts(in: .delegate) == ["Order cables", "Buy milk"], "\(texts(in: .delegate))")
  assert(!view.move(itemWithID: milk.id, toQuadrant: .delegate, position: 1))

  // Into an empty quadrant, and back out of the quadrants entirely.
  assert(view.move(itemWithID: milk.id, toQuadrant: .dontDo, position: 7))
  assert(texts(in: .dontDo) == ["Buy milk"])
  assert(view.move(itemWithID: milk.id, toQuadrant: nil, position: 0))
  assert(texts(in: nil) == ["Buy milk", "Reply to Anna"], "\(texts(in: nil))")

  // Nothing was lost or duplicated, and checked items stayed out of it.
  assert(view.items.count == 4)
  assert(view.items.filter(\.isChecked).map(\.text) == ["Pay invoice"])

  // Where a drop lands: the left column is urgent, the right one isn't, so pointing into the other lane has
  // to pick the other quadrant at the same height.
  view.layoutSubtreeIfNeeded()
  let left = view.bounds.width * 0.25
  let right = view.bounds.width * 0.75
  var lanes: [Quadrant: Quadrant] = [:]
  for step in 0 ... Int(view.bounds.height) where step % 4 == 0 {
    let y = CGFloat(step)
    guard let hit = view.dropQuadrant(forItemWithID: milk.id, at: NSPoint(x: left, y: y)) else { continue }
    if let opposite = view.dropQuadrant(forItemWithID: milk.id, at: NSPoint(x: right, y: y)) {
      lanes[hit] = opposite
    }
  }
  assert(lanes[.doFirst] == .schedule, "\(lanes)")
  assert(lanes[.delegate] == .dontDo, "\(lanes)")

  print("ok")
}
