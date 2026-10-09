import Foundation

/// A note line that starts with a list marker: a checklist box (`☐` unchecked,
/// `☒` or `☑` checked) or a `- ` bullet. Notes store lists as plain characters,
/// so the editor, list cells, Live Activity and notifications all parse them here.
struct NoteListItem {
    enum Kind {
        case bullet
        case checklist
    }

    static let uncheckedMarker: Character = "☐"
    static let checkedMarker: Character = "☒"
    private static let checklistMarkers: Set<Character> = ["☐", "☒", "☑"]

    let kind: Kind
    let isChecked: Bool
    /// Spaces and tabs before the marker.
    let indent: Substring
    /// UTF-16 length of the indent, the marker and the whitespace after it.
    let prefixLength: Int
    /// Everything after the prefix.
    let text: String

    /// UTF-16 offset of the marker within the line.
    var markerOffset: Int { indent.utf16.count }

    /// The marker to write back for this item, with `☑` normalized to `☒`.
    var marker: Character {
        guard kind == .checklist else { return "-" }
        return isChecked ? Self.checkedMarker : Self.uncheckedMarker
    }

    init?(line: String) {
        let indent = line.prefix(while: Self.isSpaceOrTab)
        let rest = line[indent.endIndex...]
        guard let first = rest.first else { return nil }

        let textStart: String.Index
        if Self.checklistMarkers.contains(first) {
            let afterMarker = rest.dropFirst()
            let spacing = afterMarker.prefix(while: Self.isSpaceOrTab)
            // A marker glued to text ("☐foo") stays plain text.
            guard !spacing.isEmpty || afterMarker.isEmpty else { return nil }
            kind = .checklist
            isChecked = first != Self.uncheckedMarker
            textStart = spacing.endIndex
        } else if rest == "-" || rest.hasPrefix("- ") {
            kind = .bullet
            isChecked = false
            textStart = rest.index(rest.startIndex, offsetBy: min(rest.count, 2))
        } else {
            return nil
        }

        self.indent = indent
        prefixLength = line.utf16.distance(from: line.startIndex, to: textStart)
        text = String(line[textStart...])
    }

    /// Whether `text` contains any checklist marker, wherever it is.
    static func containsChecklistMarker(_ text: String) -> Bool {
        text.contains { checklistMarkers.contains($0) }
    }

    private static func isSpaceOrTab(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }
}
