import Foundation
import Combine

extension Notification.Name {
    static let pnStorageError = Notification.Name("pnStorageError")
}

@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    @Published private(set) var notes: [Note] = []
    @Published private(set) var storageError: String?

    private let fileName = "notes.json"
    private let iCloudKey = "iCloudEnabled"
    private let defaults: UserDefaults
    private let localURLProvider: () -> URL
    private let iCloudURLProvider: () throws -> URL

    private enum StorageError: LocalizedError {
        case iCloudUnavailable

        var errorDescription: String? {
            switch self {
            case .iCloudUnavailable:
                return NSLocalizedString("storage_error_icloud_unavailable", comment: "")
            }
        }
    }

    // MARK: - iCloud toggle

    var isICloudEnabled: Bool {
        get { defaults.bool(forKey: iCloudKey) }
        set { _ = setICloudEnabled(newValue) }
    }

    @discardableResult
    func setICloudEnabled(_ enabled: Bool) -> Bool {
        let previous = isICloudEnabled
        let old = activeURL
        defaults.set(enabled, forKey: iCloudKey)
        defer { objectWillChange.send() }

        do {
            let destination = try makeActiveURL()
            try migrateData(from: old, to: destination)
            return true
        } catch {
            defaults.set(previous, forKey: iCloudKey)
            load()
            reportStorageError(error)
            return false
        }
    }

    // MARK: - Storage URLs

    private var localURL: URL {
        localURLProvider()
    }

    private func makeICloudURL() throws -> URL {
        try iCloudURLProvider()
    }

    private func makeActiveURL() throws -> URL {
        isICloudEnabled ? try makeICloudURL() : localURL
    }

    private var activeURL: URL {
        (try? makeActiveURL()) ?? localURL
    }

    // MARK: - Init

    private convenience init() {
        self.init(defaults: .standard)
    }

    init(
        defaults: UserDefaults,
        localURLProvider: (() -> URL)? = nil,
        iCloudURLProvider: (() throws -> URL)? = nil
    ) {
        self.defaults = defaults
        self.localURLProvider = localURLProvider ?? {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("notes.json")
        }
        self.iCloudURLProvider = iCloudURLProvider ?? {
            guard let base = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                throw StorageError.iCloudUnavailable
            }
            let dir = base.appendingPathComponent("Documents")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("notes.json")
        }
        load()
    }

    // MARK: - CRUD

    func load() {
        var urlForBackup: URL?
        do {
            let url = try makeActiveURL()
            urlForBackup = url
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Note].self, from: data)
            notes = decoded.sorted { $0.modifiedAt > $1.modifiedAt }
            clearStorageError()
            enforceSinglePin()
        } catch {
            if let urlForBackup {
                backupUnreadableStore(at: urlForBackup)
            }
            reportStorageError(error)
        }
    }

    /// Ensures at most one note is pinned. Keeps the first (most recently modified).
    private func enforceSinglePin() {
        let pinnedIndices = notes.indices.filter { notes[$0].isPinned }
        guard pinnedIndices.count > 1 else { return }
        let previous = notes
        for i in pinnedIndices.dropFirst() {
            notes[i].isPinned = false
        }
        if !save() {
            notes = previous
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: makeActiveURL(), options: .atomic)
            clearStorageError()
            return true
        } catch {
            reportStorageError(error)
            return false
        }
    }

    func add(_ note: Note) {
        guard !notes.contains(where: { $0.id == note.id }) else { return }
        let previous = notes
        notes.insert(note, at: 0)
        if !save() {
            notes = previous
        }
    }

    func update(_ note: Note) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let previous = notes
        notes[i] = note
        notes.sort { $0.modifiedAt > $1.modifiedAt }
        if !save() {
            notes = previous
        }
    }

    func delete(id: UUID) {
        let previous = notes
        notes.removeAll { $0.id == id }
        if !save() {
            notes = previous
        }
    }

    func delete(ids: Set<UUID>) {
        let previous = notes
        notes.removeAll { ids.contains($0.id) }
        if !save() {
            notes = previous
        }
    }

    /// Updates only the isPinned flag — does NOT re-sort the list.
    func updatePinOnly(_ note: Note) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let previous = notes
        objectWillChange.send()
        notes[i].isPinned = note.isPinned
        if !save() {
            notes = previous
        }
    }

    /// Updates only the scheduled pin date — does NOT re-sort the list.
    func updateScheduledPinDate(noteID: UUID, date: Date?) {
        guard let i = notes.firstIndex(where: { $0.id == noteID }) else { return }
        let previous = notes
        objectWillChange.send()
        notes[i].scheduledPinDate = date
        if !save() {
            notes = previous
        }
    }

    func updatePinAndScheduleOnly(_ note: Note) {
        guard let i = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let previous = notes
        objectWillChange.send()
        notes[i].isPinned = note.isPinned
        notes[i].scheduledPinDate = note.scheduledPinDate
        if !save() {
            notes = previous
        }
    }

    /// Unpin every note except the one being pinned now.
    func unpinAll(except id: UUID) {
        let previous = notes
        var changed = false
        for i in notes.indices where notes[i].id != id && notes[i].isPinned {
            if !changed {
                objectWillChange.send()
            }
            notes[i].isPinned = false
            changed = true
        }
        if changed, !save() {
            notes = previous
        }
    }

    // MARK: - Migration

    private func migrateData(from source: URL, to destination: URL) throws {
        guard source != destination else {
            load()
            return
        }

        let merged = try mergedNotes(from: source, and: destination)
        let data = try JSONEncoder().encode(merged)
        try data.write(to: destination, options: .atomic)

        notes = merged
        clearStorageError()
        enforceSinglePin()
    }

    private func mergedNotes(from source: URL, and destination: URL) throws -> [Note] {
        let combined = try readNotes(from: source) + readNotes(from: destination)
        var byID = [UUID: Note]()

        for note in combined {
            guard let existing = byID[note.id] else {
                byID[note.id] = note
                continue
            }
            byID[note.id] = note.modifiedAt >= existing.modifiedAt ? note : existing
        }

        return byID.values.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func readNotes(from url: URL) throws -> [Note] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Note].self, from: data)
    }

    private func backupUnreadableStore(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(fileName).corrupt.\(timestamp)")

        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
        } catch {
            print("[NoteStore] Could not back up unreadable store: \(error)")
        }
    }

    // MARK: - Error reporting

    private func reportStorageError(_ error: Error) {
        storageError = error.localizedDescription
        NotificationCenter.default.post(name: .pnStorageError, object: nil)
        print("[NoteStore] Storage error: \(error)")
    }

    private func clearStorageError() {
        storageError = nil
    }
}
