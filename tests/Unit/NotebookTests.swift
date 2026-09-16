import XCTest
@testable import BlockyeesCore

final class NotebookTests: XCTestCase {
    func testEditingOldPageMovesItFirstWithoutChangingOriginalOrder() {
        var note = Notebook()
        note.pages = (1...3).map { index in
            var page = NotebookPage(); page.createdAt = Date(timeIntervalSince1970: Double(index))
            page.modifiedAt = page.createdAt; return page
        }
        let original = note.pages.map(\.id)
        note.pageOrder = .recent
        XCTAssertEqual(note.orderedPages.map(\.id), Array(original.reversed()))
        note.pages[0].modifiedAt = Date(timeIntervalSince1970: 10)
        XCTAssertEqual(note.orderedPages.map(\.id), [original[0], original[2], original[1]])
        note.pageOrder = .original
        XCTAssertEqual(note.orderedPages.map(\.id), original)
    }

    func testMoveAndNotebookMetadataDoNotRetimestampPages() {
        var note = Notebook()
        let date = note.pages[0].modifiedAt
        note.folderID = UUID(); note.advance()
        XCTAssertEqual(note.pages[0].modifiedAt, date)
    }

    func testCodecRoundTripPreservesLayersAndInk() throws {
        var note = Notebook()
        note.pages[0].layers.append(DrawingLayer(name: "Ink", opacity: 0.4, elements: [
            DrawingElement(tool: .pencil, width: 12, points: [InkPoint(x: 10, y: 20, pressure: 0.6)])
        ]))
        XCTAssertEqual(try NotebookCodec.decode(NotebookCodec.encode(note)), note)
    }

    func testInvalidGeometryAndVersionAreRejected() {
        var note = Notebook(); note.pages[0].width = -1
        XCTAssertThrowsError(try NotebookCodec.encode(note))
        note.pages[0].width = 1200; note.schemaVersion = 99
        XCTAssertThrowsError(try NotebookCodec.encode(note))
    }

    func testSequentialSyncChoosesDescendant() {
        let old = Notebook()
        var newer = old; newer.title = "Edited"; newer.advance()
        XCTAssertEqual(RevisionMerge.merge(old, newer), [newer])
        XCTAssertEqual(RevisionMerge.merge(newer, old), [newer])
    }

    func testConcurrentEditsPreserveBothAndConverge() {
        let base = Notebook()
        var left = base; left.title = "Left"; left.advance()
        var right = base; right.title = "Right"; right.advance()
        let a = RevisionMerge.merge(left, right)
        let b = RevisionMerge.merge(right, left)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(Set(a.map(\.id)).count, 2)
        XCTAssertTrue(a.contains { $0.title.hasPrefix("Left") })
        XCTAssertTrue(a.contains { $0.title.hasPrefix("Right") })
    }

    func testConcurrentDeleteRetainsEditedCopy() {
        let base = Notebook()
        var deleted = base; deleted.isDeleted = true; deleted.advance()
        var edited = base; edited.pages[0].layers[0].name = "Saved edit"; edited.advance()
        let result = RevisionMerge.merge(deleted, edited)
        XCTAssertTrue(result.contains { !$0.isDeleted && $0.pages[0].layers[0].name == "Saved edit" })
    }

    func testDuplicateHasIndependentPageAndLayerIDs() {
        let page = NotebookPage()
        let duplicate = page.duplicated()
        XCTAssertNotEqual(page.id, duplicate.id)
        XCTAssertNotEqual(page.layers[0].id, duplicate.layers[0].id)
    }

    func testTransformMovesPointsAndPreservesPressure() {
        var element = DrawingElement(width: 4, points: [InkPoint(x: 2, y: 3, pressure: 0.5)])
        element.transform(dx: 10, dy: 20, scale: 2, center: InkPoint(x: 0, y: 0))
        XCTAssertEqual(element.points[0], InkPoint(x: 14, y: 26, pressure: 0.5))
        XCTAssertEqual(element.width, 8)
    }

    func testPersistenceSurvivesReopeningAndIgnoresStaleWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NotebookRepository(root: root)
        let note = Notebook()
        try await repo.save(note)
        var updated = note; updated.title = "Persisted"; updated.advance()
        try await repo.save(updated)
        try await repo.save(note)
        let reopened = NotebookRepository(root: root)
        let (notes, _, warnings) = try await reopened.load()
        XCTAssertEqual(notes, [updated]); XCTAssertTrue(warnings.isEmpty)
    }

    func testCorruptedFileDoesNotHideHealthyNotebook() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = NotebookRepository(root: root)
        let note = Notebook(); try await repo.save(note)
        let corrupt = root.appendingPathComponent("broken.blockyees")
        try Data("bad json".utf8).write(to: corrupt)
        let (notes, _, warnings) = try await repo.load()
        XCTAssertEqual(notes, [note]); XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
    }
}
