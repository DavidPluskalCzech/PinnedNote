// Widget Extension target — add PinNoteActivityAttributes.swift to this target too.

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Lock-screen / notification banner view

struct PinNoteBannerView: View {
    let context: ActivityViewContext<PinNoteActivityAttributes>

    // Theme-derived colors
    private var bgColor: Color {
        if context.state.isDarkTheme {
            return Color(red: 0.058, green: 0.060, blue: 0.066)
        }
        return context.state.usesBlossomTheme
            ? Color(red: 1.0, green: 0.940, blue: 0.958)
            : .white
    }

    private var primaryColor: Color {
        if context.state.isDarkTheme {
            return Color(red: 0.94, green: 0.92, blue: 0.86)
        }
        return context.state.usesBlossomTheme
            ? Color(red: 0.55, green: 0.33, blue: 0.41)
            : Color(white: 0.08)
    }

    private var secondaryColor: Color {
        if context.state.isDarkTheme {
            return Color(red: 0.68, green: 0.65, blue: 0.59)
        }
        return context.state.usesBlossomTheme
            ? Color(red: 0.65, green: 0.48, blue: 0.53)
            : Color(white: 0.40)
    }

    var body: some View {
        ZStack(alignment: usesCenteredSingleLineLayout ? .center : .topTrailing) {
            if context.state.hasExplicitTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.note(context.state.appFont, size: 15))
                        .foregroundColor(primaryColor)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    if !context.state.bannerBodyPreview.isEmpty {
                        bannerText(context.state.bannerBodyPreview, maxLines: 4)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                bannerText(context.state.fullPreview, maxLines: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: usesCenteredSingleLineLayout ? .center : .topLeading
        )
        .clipped()
        .background(bgColor)
        .environment(\.noteFont, context.state.appFont)
    }

    private var usesCenteredSingleLineLayout: Bool {
        guard !context.state.hasExplicitTitle else { return false }
        let lines = context.state.fullPreview
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count == 1, let line = lines.first else { return false }
        return NoteListItem(line: line) == nil
    }

    @ViewBuilder
    private func bannerText(_ text: String, maxLines: Int) -> some View {
        if startsWithListFormatting(text) {
            LiveActivityChecklistText(
                text,
                fontSize: 13,
                color: primaryColor,
                maxLines: maxLines
            )
        } else {
            Text(text)
                .font(.note(context.state.appFont, size: 13))
                .foregroundColor(primaryColor)
                .lineLimit(maxLines)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()
        }
    }

    private func startsWithListFormatting(_ text: String) -> Bool {
        guard let firstLine = text.components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return false
        }
        return NoteListItem(line: firstLine) != nil
    }
}

private struct LiveActivityChecklistText: View {
    private let singleColumnLines: [LiveActivityChecklistLine.Model]
    private let leadingColumnLines: [LiveActivityChecklistLine.Model]
    private let trailingColumnLines: [LiveActivityChecklistLine.Model]
    private let prefersColumns: Bool
    let fontSize: CGFloat
    let color: Color

    init(_ text: String, fontSize: CGFloat, color: Color, maxLines: Int, allowsColumns: Bool = true) {
        let visibleTextLines = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let listItemCount = visibleTextLines.filter { NoteListItem(line: $0) != nil }.count
        let leadingListLines = Array(visibleTextLines.prefix { NoteListItem(line: $0) != nil })
        let shouldUseColumns = allowsColumns
            && leadingListLines.count > maxLines
            && listItemCount >= 3

        self.prefersColumns = shouldUseColumns
        self.singleColumnLines = Self.makeModels(
            from: visibleTextLines,
            capacity: maxLines,
            allowsWrapping: true
        )

        if shouldUseColumns {
            let columnCapacity = maxLines * 2
            let columnLines = Self.makeModels(
                from: leadingListLines,
                capacity: columnCapacity,
                allowsWrapping: false
            )
            self.leadingColumnLines = Array(columnLines.prefix(maxLines))
            self.trailingColumnLines = Array(columnLines.dropFirst(maxLines).prefix(maxLines))
        } else {
            self.leadingColumnLines = []
            self.trailingColumnLines = []
        }

        self.fontSize = fontSize
        self.color = color
    }

    var body: some View {
        Group {
            if prefersColumns {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        column(leadingColumnLines)
                            .frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
                        column(trailingColumnLines)
                            .frame(minWidth: 112, maxWidth: .infinity, alignment: .leading)
                    }

                    column(singleColumnLines)
                }
            } else {
                column(singleColumnLines)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
    }

    private func column(_ lines: [LiveActivityChecklistLine.Model]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                LiveActivityChecklistLine(
                    line: line,
                    fontSize: fontSize,
                    color: color,
                    lineLimit: line.displayLineLimit
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func makeModels(
        from lines: [String],
        capacity: Int,
        allowsWrapping: Bool
    ) -> [LiveActivityChecklistLine.Model] {
        let visibleLines = Array(lines.prefix(capacity))
        let didTruncate = lines.count > visibleLines.count
        var models = visibleLines.enumerated().map { index, line in
            var model = LiveActivityChecklistLine.Model(
                line,
                appendEllipsis: didTruncate && index == visibleLines.count - 1
            )
            model.displayLineLimit = 1
            return model
        }

        guard allowsWrapping else { return models }

        var remainingLines = max(0, capacity - visibleLines.count)
        let leadingListCount = models.prefix { $0.isListItem }.count
        let preferredWrappingIndices: [Int]
        if leadingListCount > 0 && leadingListCount <= 2 {
            preferredWrappingIndices = Array(models.indices.filter { !models[$0].isListItem })
                + Array(models.indices.filter { models[$0].isListItem })
        } else {
            preferredWrappingIndices = Array(models.indices)
        }

        for index in preferredWrappingIndices where remainingLines > 0 {
            let maxLineLimit = models[index].isListItem ? 2 : 3
            let extraLines = min(remainingLines, maxLineLimit - 1)
            models[index].displayLineLimit += extraLines
            remainingLines -= extraLines
        }

        return models
    }
}

private struct LiveActivityChecklistLine: View {
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.noteFont) private var noteFont

    struct Model {
        let text: String
        let checked: Bool?
        let indentLevel: Int
        let isListItem: Bool
        var displayLineLimit: Int

        init(_ rawLine: String, appendEllipsis: Bool = false) {
            let item = NoteListItem(line: rawLine)

            if let item, item.kind == .checklist {
                self.text = Self.ellipsized(item.text, appendEllipsis: appendEllipsis)
                self.checked = item.isChecked
                self.indentLevel = item.indent.count
            } else {
                self.text = Self.ellipsized(rawLine, appendEllipsis: appendEllipsis)
                self.checked = nil
                self.indentLevel = 0
            }
            self.isListItem = item != nil
            self.displayLineLimit = 1
        }

        private static func ellipsized(_ text: String, appendEllipsis: Bool) -> String {
            guard appendEllipsis else { return text }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "..." : "\(trimmed)..."
        }
    }

    let line: Model
    let fontSize: CGFloat
    let color: Color
    let lineLimit: Int

    var body: some View {
        if let checked = line.checked {
            // A little extra spacing: the check flies out past the box's right edge.
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                LiveActivityCheckbox(checked: checked)
                    .fill(color)
                    .frame(width: 11, height: 11)
                    .opacity(redactionReasons.isEmpty ? 1 : 0)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[VerticalAlignment.center] + 4
                    }

                Text(line.text.isEmpty ? " " : line.text)
                    .font(.note(noteFont, size: fontSize))
                    .foregroundColor(color)
                    .lineLimit(lineLimit)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(line.indentLevel) * 3)
        } else {
            Text(line.text)
                .font(.note(noteFont, size: fontSize))
                .foregroundColor(color)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Note font

private struct NoteFontKey: EnvironmentKey {
    static let defaultValue = AppFont.default
}

private extension EnvironmentValues {
    var noteFont: AppFont {
        get { self[NoteFontKey.self] }
        set { self[NoteFontKey.self] = newValue }
    }
}

private extension Font {
    /// The note typeface picked in the app's Settings.
    static func note(_ appFont: AppFont, size: CGFloat, bold: Bool = true) -> Font {
        guard let name = bold ? appFont.boldName : appFont.regularName else {
            return .system(size: size, weight: bold ? .bold : .light)
        }
        return .custom(name, size: size * appFont.sizeScale)
    }
}

private struct LiveActivityCheckbox: Shape {
    let checked: Bool

    func path(in rect: CGRect) -> Path {
        Path(HandDrawnCheckbox.path(in: rect, checked: checked))
    }
}

struct PinNoteAdaptiveActivityView: View {
    let context: ActivityViewContext<PinNoteActivityAttributes>

    var body: some View {
        PinNoteBannerView(context: context)
    }
}

struct PinNoteCompactActivityView: View {
    let context: ActivityViewContext<PinNoteActivityAttributes>
    let isSmall: Bool

    private var primaryColor: Color {
        if context.state.isDarkTheme {
            return Color(red: 0.94, green: 0.92, blue: 0.86)
        }
        return context.state.usesBlossomTheme
            ? Color(red: 0.55, green: 0.33, blue: 0.41)
            : Color(white: 0.08)
    }

    private var secondaryColor: Color {
        if context.state.isDarkTheme {
            return Color(red: 0.68, green: 0.65, blue: 0.59)
        }
        return context.state.usesBlossomTheme
            ? Color(red: 0.65, green: 0.48, blue: 0.53)
            : Color(white: 0.36)
    }

    private var bgColor: Color {
        if context.state.isDarkTheme {
            return Color(red: 0.058, green: 0.060, blue: 0.066)
        }
        return context.state.usesBlossomTheme
            ? Color(red: 1.0, green: 0.940, blue: 0.958)
            : .white
    }

    private var bodyText: String {
        context.state.hasExplicitTitle
            ? context.state.bannerBodyPreview
            : context.state.fullPreview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isSmall ? 2 : 4) {
            Text(context.state.title)
                .font(.note(context.state.appFont, size: isSmall ? 13 : 15))
                .foregroundColor(primaryColor)
                .lineLimit(isSmall ? 1 : 2)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !bodyText.isEmpty {
                Text(bodyText)
                    .font(.note(context.state.appFont, size: isSmall ? 11 : 13))
                    .foregroundColor(primaryColor)
                    .lineLimit(isSmall ? 2 : 3)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, isSmall ? 8 : 10)
        .padding(.vertical, isSmall ? 6 : 8)
        .background(bgColor)
    }
}

// MARK: - New Note Control (iOS 18+ lock screen Controls gallery)

@available(iOS 18.0, *)
struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.pinnote.control.newnote") {
            ControlWidgetButton(action: CreateNoteIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Note")
        .description("Open PinNote and create a new note.")
    }
}

// MARK: - Widget bundle

@main
struct PinNoteLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        PinNoteLiveActivityWidget()
        NotesWidget()
        if #available(iOS 18.0, *) {
            NewNoteControl()
        }
    }
}

struct PinNoteLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        makePinNoteActivityConfiguration(useAdaptiveBanner: true)
    }
}

private func makePinNoteActivityConfiguration(useAdaptiveBanner: Bool) -> some WidgetConfiguration {
    ActivityConfiguration(for: PinNoteActivityAttributes.self) { context in
        // Lock screen / notification banner
        let bgColor = context.state.isDarkTheme
            ? Color(red: 0.058, green: 0.060, blue: 0.066)
            : (context.state.usesBlossomTheme ? Color(red: 1.0, green: 0.940, blue: 0.958) : .white)
        let primaryColor = context.state.isDarkTheme
            ? Color(red: 0.94, green: 0.92, blue: 0.86)
            : (context.state.usesBlossomTheme ? Color(red: 0.55, green: 0.33, blue: 0.41) : Color(white: 0.08))
        if useAdaptiveBanner {
            PinNoteAdaptiveActivityView(context: context)
                .activityBackgroundTint(bgColor)
                .activitySystemActionForegroundColor(primaryColor)
                .widgetURL(URL(string: "pinnote://note/\(context.attributes.noteID)"))
        } else {
            PinNoteBannerView(context: context)
                .activityBackgroundTint(bgColor)
                .activitySystemActionForegroundColor(primaryColor)
                .widgetURL(URL(string: "pinnote://note/\(context.attributes.noteID)"))
        }

    } dynamicIsland: { context in
        let primaryColor = context.state.isDarkTheme
            ? Color(red: 0.94, green: 0.92, blue: 0.86)
            : (context.state.usesBlossomTheme ? Color(red: 0.55, green: 0.33, blue: 0.41) : Color(white: 0.08))
        let secondaryColor = context.state.isDarkTheme
            ? Color(red: 0.68, green: 0.65, blue: 0.59)
            : (context.state.usesBlossomTheme ? Color(red: 0.65, green: 0.48, blue: 0.53) : Color.secondary)
        return DynamicIsland {
            // Expanded regions
            DynamicIslandExpandedRegion(.leading) {
                EmptyView()
            }
            DynamicIslandExpandedRegion(.center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(context.state.title)
                        .font(.note(context.state.appFont, size: context.state.hasExplicitTitle ? 14 : 13))
                        .foregroundColor(primaryColor)
                        .lineLimit(1)
                    if !context.state.bodyPreview.isEmpty {
                        Text(context.state.bodyPreview)
                            .font(.note(context.state.appFont, size: 11, bold: false))
                            .foregroundColor(secondaryColor)
                            .lineLimit(2)
                    }
                }
            }

        } compactLeading: {
            Text(context.state.title.prefix(12))
                .font(.note(context.state.appFont, size: 10))
                .foregroundColor(primaryColor)
                .lineLimit(1)

        } compactTrailing: {
            EmptyView()

        } minimal: {
            Color.clear
        }
        .widgetURL(URL(string: "pinnote://note/\(context.attributes.noteID)"))
    }
}
