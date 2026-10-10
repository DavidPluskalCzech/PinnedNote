import SwiftUI
import WidgetKit

/// Home-screen widget with the latest notes: one, three, five or eight of them
/// depending on its size. The app keeps the notes up to date and reloads it.
struct NotesWidget: Widget {
    static let kind = "PinNoteNotesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NotesWidgetProvider()) { entry in
            NotesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_name", comment: ""))
        .description(NSLocalizedString("widget_description", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct NotesWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetNotesSnapshot
}

struct NotesWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotesWidgetEntry {
        NotesWidgetEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NotesWidgetEntry) -> Void) {
        // In the widget gallery, show something even before the app has written notes.
        let saved = WidgetNotesSnapshot.load()
        let snapshot = context.isPreview && (saved?.notes.isEmpty ?? true) ? .sample : (saved ?? .sample)
        completion(NotesWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotesWidgetEntry>) -> Void) {
        let snapshot = WidgetNotesSnapshot.load()
            ?? WidgetNotesSnapshot(notes: [], themeRawValue: "monochrome", fontRawValue: AppFont.default.rawValue)
        // No schedule: the app reloads the widget whenever notes or the look change.
        completion(Timeline(entries: [NotesWidgetEntry(date: Date(), snapshot: snapshot)], policy: .never))
    }
}

struct NotesWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NotesWidgetEntry

    private var layout: NotesWidgetLayout {
        switch family {
        case .systemMedium: return .medium
        case .systemLarge: return .large
        case .systemExtraLarge: return .extraLarge
        default: return .small
        }
    }

    var body: some View {
        let palette = NotesWidgetPalette(themeRawValue: entry.snapshot.themeRawValue)
        NotesWidgetView(snapshot: entry.snapshot, layout: layout)
            .containerBackground(palette.background, for: .widget)
            .widgetURL(entry.snapshot.notes.first.map { URL(string: "pinnote://note/\($0.id.uuidString)")! })
    }
}

private extension WidgetNotesSnapshot {
    /// Shown in the widget gallery before there are any notes.
    static let sample = WidgetNotesSnapshot(
        notes: [
            WidgetNote(id: UUID(), title: "PinnedNote", hasTitle: true,
                       body: "  ☐    Pin a note\n  ☒    Write it down", isPinned: true),
            WidgetNote(id: UUID(), title: "Ideas", hasTitle: true, body: "- Small\n- Simple", isPinned: false),
            WidgetNote(id: UUID(), title: "Shopping", hasTitle: true, body: "Milk\nBread", isPinned: false),
        ],
        themeRawValue: "monochrome",
        fontRawValue: AppFont.default.rawValue
    )
}
