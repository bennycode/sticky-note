import Foundation

/// The four Eisenhower quadrants, in reading order: urgent and important first, neither last.
enum Quadrant: Int, Codable, CaseIterable {
  case doFirst
  case schedule
  case delegate
  case dontDo

  var title: String {
    switch self {
    case .doFirst: return "Do first"
    case .schedule: return "Schedule"
    case .delegate: return "Delegate"
    case .dontDo: return "Don't do"
    }
  }

  var subtitle: String {
    switch self {
    case .doFirst: return "Urgent and important"
    case .schedule: return "Important, not urgent"
    case .delegate: return "Urgent, not important"
    case .dontDo: return "Neither urgent nor important"
    }
  }
}

struct ChecklistItem: Codable, Equatable {
  var id = UUID()
  var text: String
  var isChecked = false
  /// nil until the item is dragged into a quadrant. Kept while the note shows a plain list.
  var quadrant: Quadrant?
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
    /// A checklist whose open items are split across the Eisenhower quadrants.
    case matrix
  }

  static let defaultFontSize: Double = 15

  var mode = Mode.text
  var text = ""
  var items: [ChecklistItem] = []
  var showsCheckedItems = true
  var fontSize = Note.defaultFontSize

  init(text: String = "") {
    self.text = text
  }

  /// Fills in defaults for fields that notes saved by older versions don't have yet.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .text
    text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
    items = try container.decodeIfPresent([ChecklistItem].self, forKey: .items) ?? []
    showsCheckedItems = try container.decodeIfPresent(Bool.self, forKey: .showsCheckedItems) ?? true
    fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? Note.defaultFontSize
  }
}

final class NoteStore {
  private let noteURL: URL
  /// Plain text file written by the first version, before checklists existed.
  private let legacyTextURL: URL

  init() {
    // STICKY_NOTE_DIR lets a development build run against test data instead of your real note.
    let directory = ProcessInfo.processInfo.environment["STICKY_NOTE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default
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
