import XCTest
@testable import PinNote

final class NoteListItemTests: XCTestCase {

    func testParsesUncheckedChecklistItem() throws {
        let item = try XCTUnwrap(NoteListItem(line: "  ☐    Milk"))

        XCTAssertEqual(item.kind, .checklist)
        XCTAssertFalse(item.isChecked)
        XCTAssertEqual(item.indent, "  ")
        XCTAssertEqual(item.markerOffset, 2)
        XCTAssertEqual(item.prefixLength, 7)
        XCTAssertEqual(item.text, "Milk")
    }

    func testCheckedMarkersAreNormalized() throws {
        let crossed = try XCTUnwrap(NoteListItem(line: "☒ Done"))
        let ticked = try XCTUnwrap(NoteListItem(line: "☑\tDone"))

        XCTAssertTrue(crossed.isChecked)
        XCTAssertTrue(ticked.isChecked)
        XCTAssertEqual(ticked.marker, NoteListItem.checkedMarker)
        XCTAssertEqual(ticked.text, "Done")
    }

    func testBareMarkerIsEmptyChecklistItem() throws {
        let item = try XCTUnwrap(NoteListItem(line: " ☐"))

        XCTAssertEqual(item.kind, .checklist)
        XCTAssertEqual(item.prefixLength, 2)
        XCTAssertEqual(item.text, "")
    }

    func testMarkerGluedToTextIsNotListItem() {
        XCTAssertNil(NoteListItem(line: "☐Milk"))
    }

    func testParsesBullets() throws {
        let bullet = try XCTUnwrap(NoteListItem(line: "  -  Bread"))
        let bare = try XCTUnwrap(NoteListItem(line: "-"))

        XCTAssertEqual(bullet.kind, .bullet)
        XCTAssertEqual(bullet.prefixLength, 4)
        XCTAssertEqual(bullet.text, " Bread")
        XCTAssertEqual(bare.prefixLength, 1)
        XCTAssertEqual(bare.text, "")
    }

    func testPlainTextIsNotListItem() {
        XCTAssertNil(NoteListItem(line: "Shopping"))
        XCTAssertNil(NoteListItem(line: "-5 degrees"))
        XCTAssertNil(NoteListItem(line: ""))
    }

    func testContainsChecklistMarker() {
        XCTAssertTrue(NoteListItem.containsChecklistMarker("a\nb ☑ c"))
        XCTAssertFalse(NoteListItem.containsChecklistMarker("- a\n- b"))
    }
}
