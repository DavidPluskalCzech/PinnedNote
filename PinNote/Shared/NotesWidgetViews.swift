import SwiftUI

/// The widget's arrangements, one per size.
enum NotesWidgetLayout {
    case small, medium, large, extraLarge

    /// How many notes it shows.
    var noteCount: Int {
        switch self {
        case .small: return 1
        case .medium: return 3
        case .large: return 5
        case .extraLarge: return 8
        }
    }
}

/// Colours of the app's three themes, for the widget.
struct NotesWidgetPalette {
    let background: Color
    let surface: Color
    let primary: Color
    let secondary: Color
    let shadowOpacity: Double

    init(themeRawValue: String) {
        switch themeRawValue {
        case "dark":
            background = Color(red: 0.010, green: 0.011, blue: 0.013)
            surface = Color(red: 0.058, green: 0.060, blue: 0.066)
            primary = Color(red: 0.94, green: 0.92, blue: 0.86)
            secondary = Color(red: 0.68, green: 0.65, blue: 0.59)
            shadowOpacity = 0.6
        case "blossom":
            background = Color(red: 0.998, green: 0.905, blue: 0.930)
            surface = Color(red: 1.0, green: 0.940, blue: 0.958)
            primary = Color(red: 0.55, green: 0.33, blue: 0.41)
            secondary = Color(red: 0.65, green: 0.48, blue: 0.53)
            shadowOpacity = 0.16
        default:
            background = Color(red: 0.975, green: 0.972, blue: 0.965)
            surface = .white
            primary = Color(white: 0.08)
            secondary = Color(white: 0.4)
            shadowOpacity = 0.16
        }
    }
}

/// The widget's content: the latest notes as paper tiles, laid out for its size.
/// Each tile opens its note.
struct NotesWidgetView: View {
    let snapshot: WidgetNotesSnapshot
    let layout: NotesWidgetLayout

    private var palette: NotesWidgetPalette { NotesWidgetPalette(themeRawValue: snapshot.themeRawValue) }
    private var font: AppFont { AppFont(rawValue: snapshot.fontRawValue) ?? .default }
    private var notes: [WidgetNote] { Array(snapshot.notes.prefix(layout.noteCount)) }

    var body: some View {
        if notes.isEmpty {
            Text(NSLocalizedString("widget_empty", comment: ""))
                .font(NotesWidgetFont.note(font, size: 15))
                .foregroundColor(palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    @ViewBuilder
    private var grid: some View {
        let spacing: CGFloat = 8
        switch layout {
        case .small:
            tile(notes[0], titleSize: 16, bodyLines: 5)
        case .medium:
            HStack(spacing: spacing) {
                ForEach(notes) { tile($0, titleSize: 13, bodyLines: 4) }
                fillers(3)
            }
        case .large:
            // One wide note on top, four below.
            VStack(spacing: spacing) {
                tile(notes[0], titleSize: 15, bodyLines: 3)
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = 1 + row * 2 + column
                            if index < notes.count {
                                tile(notes[index], titleSize: 13, bodyLines: 3)
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
        case .extraLarge:
            VStack(spacing: spacing) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<4, id: \.self) { column in
                            let index = row * 4 + column
                            if index < notes.count {
                                tile(notes[index], titleSize: 14, bodyLines: 5)
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fillers(_ total: Int) -> some View {
        ForEach(notes.count..<max(notes.count, total), id: \.self) { _ in Color.clear }
    }

    private func tile(_ note: WidgetNote, titleSize: CGFloat, bodyLines: Int) -> some View {
        Link(destination: URL(string: "pinnote://note/\(note.id.uuidString)")!) {
            NotesWidgetTile(note: note, font: font, palette: palette,
                            titleSize: titleSize, bodyLines: bodyLines)
        }
    }
}

/// One note as a paper tile: title, then a few lines of text with checkboxes and
/// bullets drawn as in the app.
private struct NotesWidgetTile: View {
    let note: WidgetNote
    let font: AppFont
    let palette: NotesWidgetPalette
    let titleSize: CGFloat
    let bodyLines: Int

    private var lines: [String] {
        note.body.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(bodyLines)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 4) {
                Text(note.title)
                    .font(NotesWidgetFont.note(font, size: note.hasTitle ? titleSize : titleSize - 2))
                    .foregroundColor(palette.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(palette.primary)
                }
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                NotesWidgetLine(line: line, font: font, color: palette.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.surface)
                .shadow(color: .black.opacity(palette.shadowOpacity), radius: 3, y: 1.5)
        )
    }
}

/// A preview line: a checklist item with its hand-drawn box, a bullet, or text.
private struct NotesWidgetLine: View {
    let line: String
    let font: AppFont
    let color: Color

    var body: some View {
        if let item = NoteListItem(line: line) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                switch item.kind {
                case .checklist:
                    NotesWidgetCheckbox(checked: item.isChecked)
                        .fill(color)
                        .frame(width: 9, height: 9)
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3.5 }
                case .bullet:
                    Text("•").font(NotesWidgetFont.note(font, size: 11)).foregroundColor(color)
                }
                text(item.text)
            }
        } else {
            text(line)
        }
    }

    private func text(_ string: String) -> some View {
        Text(string)
            .font(NotesWidgetFont.note(font, size: 11))
            .foregroundColor(color)
            .lineLimit(1)
    }
}

private struct NotesWidgetCheckbox: Shape {
    let checked: Bool
    func path(in rect: CGRect) -> Path {
        Path(HandDrawnCheckbox.path(in: rect, checked: checked))
    }
}

/// The note typeface picked in the app.
enum NotesWidgetFont {
    static func note(_ appFont: AppFont, size: CGFloat, bold: Bool = true) -> Font {
        guard let name = bold ? appFont.boldName : appFont.regularName else {
            return .system(size: size, weight: bold ? .bold : .regular)
        }
        return .custom(name, size: size * appFont.sizeScale)
    }
}
