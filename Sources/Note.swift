import Foundation

struct ChecklistItem: Codable, Equatable {
  var id = UUID()
  var text: String
  var isChecked = false
}

extension ChecklistItem {
  private static let checkedMarkers = ["[x] ", "[X] ", "- [x] ", "- [X] "]
  private static let uncheckedMarkers = ["[ ] ", "- [ ] ", "- ", "* ", "• "]

  /// Turns a line of plain text into an item, dropping list markers like "- " and reading "[x] " as checked.
  init?(line: String) {
    var text = line.trimmingCharacters(in: .whitespaces)
    var isChecked = false
    if let marker = Self.checkedMarkers.first(where: text.hasPrefix) {
      text.removeFirst(marker.count)
      isChecked = true
    } else if let marker = Self.uncheckedMarkers.first(where: text.hasPrefix) {
      text.removeFirst(marker.count)
    }
    guard !text.isEmpty else { return nil }
    self.init(text: text, isChecked: isChecked)
  }
}

struct Note: Codable {
  enum Mode: String, Codable {
    case text
    case checklist
  }

  var mode = Mode.text
  var text = ""
  var items: [ChecklistItem] = []
  var showsCheckedItems = true
}

final class NoteStore {
  private let noteURL: URL
  /// Plain text file written by the first version, before checklists existed.
  private let legacyTextURL: URL

  init() {
    let directory = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("StickyNote", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    noteURL = directory.appendingPathComponent("note.json")
    legacyTextURL = directory.appendingPathComponent("note.txt")
  }

  func load() -> Note {
    if let data = try? Data(contentsOf: noteURL), let note = try? JSONDecoder().decode(Note.self, from: data) {
      return note
    }
    if let text = try? String(contentsOf: legacyTextURL, encoding: .utf8) {
      return Note(text: text)
    }
    return Note()
  }

  func save(_ note: Note) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(note) else { return }
    try? data.write(to: noteURL, options: .atomic)
  }
}
