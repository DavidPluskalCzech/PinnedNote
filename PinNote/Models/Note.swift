import Foundation

struct Note: Codable, Identifiable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date
    var isPinned: Bool
    var isBulletList: Bool
    var scheduledPinDate: Date?

    init(title: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.isPinned = false
        self.isBulletList = false
        self.scheduledPinDate = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, createdAt, modifiedAt, isPinned, isBulletList, scheduledPinDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        isBulletList = try container.decodeIfPresent(Bool.self, forKey: .isBulletList) ?? false
        scheduledPinDate = try container.decodeIfPresent(Date.self, forKey: .scheduledPinDate)
    }

    /// First non-empty line — used as visible title in the list
    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { return trimmedTitle }

        let first = content
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        return first.isEmpty ? "—" : first
    }

    /// Up to 3 lines after the title, for the cell preview
    var previewBody: String {
        let lines = content
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let hasExplicitTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasExplicitTitle ? lines.prefix(3) : lines.dropFirst().prefix(3)).joined(separator: "\n")
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
