import XCTest
@testable import PinNote

@MainActor
final class TrashStoreTests: XCTestCase {

    private var directory: URL!
    private var now = Date(timeIntervalSince1970: 1_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeTrash() -> TrashStore {
        TrashStore(fileURL: directory.appendingPathComponent("trash.json"), now: { [unowned self] in self.now })
    }

    func testDeletedNotesGoToTrashUnpinnedAndEmptyOnesAreDropped() {
        let trash = makeTrash()
        var pinned = Note(title: "Shopping", content: "Milk")
        pinned.isPinned = true
        pinned.scheduledPinDate = now.addingTimeInterval(60)

        trash.add([pinned, Note()])

        XCTAssertEqual(trash.items.map(\.id), [pinned.id])
        XCTAssertFalse(trash.items[0].note.isPinned)
        XCTAssertNil(trash.items[0].note.scheduledPinDate)
        XCTAssertEqual(trash.items[0].expiresAt, now.addingTimeInterval(30 * 24 * 60 * 60))
    }

    func testNotesAreRemovedForGoodAfterThirtyDays() {
        let trash = makeTrash()
        let note = Note(content: "Old idea")
        trash.add([note])

        now = now.addingTimeInterval(30 * 24 * 60 * 60 - 1)
        trash.purgeExpired()
        XCTAssertEqual(trash.items.count, 1)

        now = now.addingTimeInterval(2)
        trash.purgeExpired()
        XCTAssertTrue(trash.items.isEmpty)
    }

    func testTrashIsKeptAcrossLaunchesAndExpiredNotesGoOnLoad() {
        let note = Note(content: "Keep me")
        makeTrash().add([note])
        XCTAssertEqual(makeTrash().items.map(\.id), [note.id])

        now = now.addingTimeInterval(31 * 24 * 60 * 60)
        XCTAssertTrue(makeTrash().items.isEmpty)
    }

    func testDeletingFromTheStoreMovesNotesToTrashAndRestoreBringsThemBack() throws {
        let trash = makeTrash()
        let notesURL = directory.appendingPathComponent("notes.json")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = NoteStore(defaults: defaults, localURLProvider: { notesURL }, trash: trash)
        let note = Note(title: "Plans", content: "Weekend")
        store.add(note)

        store.delete(id: note.id)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertEqual(trash.items.map(\.id), [note.id])

        store.restoreFromTrash(id: note.id)
        XCTAssertEqual(store.notes.map(\.id), [note.id])
        XCTAssertEqual(store.notes.first?.content, "Weekend")
        XCTAssertTrue(trash.items.isEmpty)
    }
}
