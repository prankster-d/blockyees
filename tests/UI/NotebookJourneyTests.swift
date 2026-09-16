import XCTest

final class NotebookJourneyTests: XCTestCase {
    func testCreateDrawLayerAndReopen() {
        let app = XCUIApplication()
        app.launch()
        let newNotebook = app.buttons["newNotebook"]
        XCTAssertTrue(newNotebook.waitForExistence(timeout: 10))
        attach("Library")
        newNotebook.tap()
        let title = app.textFields["notebookTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Sketch test")
        app.buttons["createNotebook"].tap()
        let page = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'page-'")).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 5)); page.tap()
        XCTAssertTrue(app.buttons["closeEditor"].waitForExistence(timeout: 5))
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
        from.press(forDuration: 0.05, thenDragTo: to)
        app.buttons["layersButton"].tap()
        XCTAssertTrue(app.buttons["addLayer"].waitForExistence(timeout: 5))
        app.buttons["addLayer"].tap()
        XCTAssertTrue(app.buttons["Слой 2"].exists)
        app.buttons["Готово"].tap()
        attach("Editor")
        app.buttons["closeEditor"].tap()
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 5))
        app.buttons["addPage"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'page-'")).count, 2)
        attach("Pages")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Открыть Sketch test"].waitForExistence(timeout: 10))
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
