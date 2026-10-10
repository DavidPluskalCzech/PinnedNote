import Foundation
import Combine

/// A deleted note waiting in the trash.
struct TrashedNote: Codable, Identifiable {
    var note: Note
    var deletedAt: Date

    var id: UUID { note.id }

    /// When it's removed for good.
    var expiresAt: Date { deletedAt.addingTimeInterval(TrashStore.retention) }
}

/// Deleted notes, kept for 30 days so they can be restored, then removed for good.
/// Stored on this device only, next to the notes file.
@MainActor
final class TrashStore: ObservableObject {
    static let shared = TrashStore()

    /// How long a note stays in the trash.
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// Most recently deleted first.
    @Published private(set) var items: [TrashedNote] = []

    private let fileURL: URL
    private let now: () -> Date

    private convenience init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.init(fileURL: documents.appendingPathComponent("trash.json"))
    }

    init(fileURL: URL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
        load()
        purgeExpired()
    }

    /// Moves deleted notes into the trash. Empty notes aren't kept.
    func add(_ notes: [Note]) {
        let deletedAt = now()
        let kept = notes.filter { !$0.isEmpty }.map { note -> TrashedNote in
            var note = note
            note.isPinned = false
            note.scheduledPinDate = nil
            return TrashedNote(note: note, deletedAt: deletedAt)
        }
        guard !kept.isEmpty else { return }
        let ids = Set(kept.map(\.id))
        items = kept + items.filter { !ids.contains($0.id) }
        save()
    }

    /// Takes a note out of the trash and returns it, ready to go back in the list.
    func restore(id: UUID) -> Note? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let note = items.remove(at: index).note
        save()
        return note
    }

    func deleteForever(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func empty() {
        items.removeAll()
        save()
    }

    /// Removes notes whose 30 days are up.
    func purgeExpired() {
        let current = now()
        let remaining = items.filter { $0.expiresAt > current }
        guard remaining.count != items.count else { return }
        items = remaining
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TrashedNote].self, from: data) else { return }
        items = decoded.sorted { $0.deletedAt > $1.deletedAt }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[TrashStore] Could not save the trash: \(error)")
        }
    }
}
