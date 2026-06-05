import XCTest
@testable import PinNote

@MainActor
final class NoteStoreTests: XCTestCase {

    private var tempDirectories: [URL] = []

    override func tearDown() {
        for url in tempDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirectories.removeAll()
        super.tearDown()
    }

    func testICloudToggleMergesLocalAndCloudNotesByIDKeepingNewestVersion() throws {
        let dir = try makeTempDirectory()
        let localURL = dir.appendingPathComponent("local.json")
        let cloudURL = dir.appendingPathComponent("cloud.json")
        let defaults = makeDefaults()

        let sharedID = UUID()
        let oldShared = makeNote(id: sharedID, content: "Old", modifiedAt: Date(timeIntervalSince1970: 100))
        let newShared = makeNote(id: sharedID, content: "New", modifiedAt: Date(timeIntervalSince1970: 200))
        let localOnly = makeNote(content: "Local only", modifiedAt: Date(timeIntervalSince1970: 150))
        let cloudOnly = makeNote(content: "Cloud only", modifiedAt: Date(timeIntervalSince1970: 175))

        try write([oldShared, localOnly], to: localURL)
        try write([newShared, cloudOnly], to: cloudURL)

        let store = NoteStore(
            defaults: defaults,
            localURLProvider: { localURL },
            iCloudURLProvider: { cloudURL }
        )

        XCTAssertTrue(store.setICloudEnabled(true))
        XCTAssertEqual(store.notes.count, 3)
        XCTAssertTrue(store.notes.contains { $0.id == sharedID && $0.content == "New" })
        XCTAssertTrue(store.notes.contains { $0.content == "Local only" })
        XCTAssertTrue(store.notes.contains { $0.content == "Cloud only" })

        let savedCloudNotes = try readNotes(from: cloudURL)
        XCTAssertEqual(savedCloudNotes.count, 3)
    }

    func testFailedSaveRollsBackInMemoryInsert() throws {
        let dir = try makeTempDirectory()
        let localURL = dir.appendingPathComponent("notes.json")
        let defaults = makeDefaults()

        let store = NoteStore(defaults: defaults, localURLProvider: { localURL })
        try FileManager.default.removeItem(at: dir)

        store.add(Note(content: "Unsaved"))

        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNotNil(store.storageError)
    }

    func testUnreadableStoreIsBackedUpBeforeReportingError() throws {
        let dir = try makeTempDirectory()
        let localURL = dir.appendingPathComponent("notes.json")
        let defaults = makeDefaults()

        try Data("not json".utf8).write(to: localURL)
        let store = NoteStore(defaults: defaults, localURLProvider: { localURL })

        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNotNil(store.storageError)

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("notes.json.corrupt.") })
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PinNoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirectories.append(url)
        return url
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PinNoteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeNote(
        id: UUID = UUID(),
        content: String,
        modifiedAt: Date
    ) -> Note {
        var note = Note(content: content)
        note.id = id
        note.createdAt = modifiedAt
        note.modifiedAt = modifiedAt
        return note
    }

    private func write(_ notes: [Note], to url: URL) throws {
        let data = try JSONEncoder().encode(notes)
        try data.write(to: url, options: .atomic)
    }

    private func readNotes(from url: URL) throws -> [Note] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Note].self, from: data)
    }
}
