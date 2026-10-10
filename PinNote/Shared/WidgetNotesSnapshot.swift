import Foundation

/// A note as the home-screen widget shows it: already reduced to its title and a
/// few preview lines.
struct WidgetNote: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    /// Whether `title` is the note's own title (else it's the first line of text).
    let hasTitle: Bool
    let body: String
    let isPinned: Bool
}

/// What the app hands the widget: the latest notes and the look to draw them in.
/// Written by the app into the shared App Group container, read by the widget.
struct WidgetNotesSnapshot: Codable {
    static let appGroup = "group.com.davethepcguy.PinNote"
    /// The most notes any widget size shows.
    static let maxNotes = 8

    var notes: [WidgetNote]
    var themeRawValue: String
    var fontRawValue: String

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("widget-notes.json")
    }

    static func load() -> WidgetNotesSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetNotesSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL else {
            print("[Widget] App Group container unavailable")
            return
        }
        do {
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        } catch {
            print("[Widget] Could not save the widget notes: \(error)")
        }
    }
}
