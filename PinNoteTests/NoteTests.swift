import XCTest
@testable import PinNote

final class NoteTests: XCTestCase {

    func testDisplayTitleUsesFirstNonEmptyLine() {
        let note = Note(content: "\n  \nFirst line\nSecond line")

        XCTAssertEqual(note.displayTitle, "First line")
    }

    func testPreviewBodyUsesUpToThreeLinesAfterTitle() {
        let note = Note(content: "Title\nOne\nTwo\nThree\nFour")

        XCTAssertEqual(note.previewBody, "One\nTwo\nThree")
    }

    func testExplicitTitleOverridesFirstContentLine() {
        let note = Note(title: "Shopping", content: "Milk\nBread")

        XCTAssertEqual(note.displayTitle, "Shopping")
        XCTAssertEqual(note.previewBody, "Milk\nBread")
    }

    func testEmptyDisplayTitleUsesDash() {
        let note = Note(content: " \n\t")

        XCTAssertEqual(note.displayTitle, "—")
    }

    func testDecodesOldNotesWithoutTitle() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "content": "Old note",
          "createdAt": 0,
          "modifiedAt": 0,
          "isPinned": false,
          "isBulletList": false
        }
        """
        let decoder = JSONDecoder()

        let note = try decoder.decode(Note.self, from: Data(json.utf8))

        XCTAssertEqual(note.title, "")
        XCTAssertEqual(note.displayTitle, "Old note")
    }
}
