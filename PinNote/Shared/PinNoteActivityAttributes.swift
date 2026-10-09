// Shared between the main app target AND the PinNoteLiveActivity widget extension.
// In Xcode: select this file → File Inspector → Target Membership → tick both targets.

import ActivityKit
import Foundation

struct PinNoteActivityAttributes: ActivityAttributes {

    // Static metadata (doesn't change while the activity lives)
    var noteID: String

    // Dynamic state (updated when the note is edited)
    public struct ContentState: Codable, Hashable {
        var noteTitle: String?
        var content: String
        var modifiedAt: Date
        var isBlossomTheme: Bool
        var themeRawValue: String?
        /// `AppFont` raw value; nil for activities started before fonts were selectable.
        var fontRawValue: String? = nil

        var appFont: AppFont {
            AppFont(rawValue: fontRawValue ?? "") ?? .default
        }

        var isDarkTheme: Bool {
            themeRawValue == "dark"
        }

        var usesBlossomTheme: Bool {
            themeRawValue == "blossom" || (themeRawValue == nil && isBlossomTheme)
        }

        /// First non-empty line — used in compact/minimal Dynamic Island
        var title: String {
            if let noteTitle,
               !noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return noteTitle
            }
            return displayContent
                .components(separatedBy: "\n")
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                ?? "PinnedNote"
        }

        /// Full content preview for the lock screen banner (up to 9 lines)
        var fullPreview: String {
            let lines = displayContent
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if let noteTitle,
               !noteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ([noteTitle] + Array(lines.prefix(8))).joined(separator: "\n")
            }
            return lines.prefix(9).joined(separator: "\n")
        }

        var hasExplicitTitle: Bool {
            !(noteTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }

        /// Body lines for the lock screen banner when a separate note title exists.
        var bannerBodyPreview: String {
            displayContent
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .prefix(8)
                .joined(separator: "\n")
        }

        /// Up to 4 lines of body text (Dynamic Island expanded)
        var bodyPreview: String {
            let lines = displayContent
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return (hasExplicitTitle ? lines.prefix(4) : lines.dropFirst().prefix(4)).joined(separator: "\n")
        }

        var displayContent: String {
            content
                .components(separatedBy: "\n")
                .map(Self.normalizedChecklistLine)
                .joined(separator: "\n")
        }

        private static func normalizedChecklistLine(_ line: String) -> String {
            guard let item = NoteListItem(line: line), item.kind == .checklist else { return line }
            return "\(item.indent)\(item.marker)  \(item.text)"
        }
    }
}
