import XCTest
import UIKit
@testable import Blockyees

final class RenderingTests: XCTestCase {
    @MainActor
    func testStrokeAppearsAndErasingDoesNotEraseLowerLayer() {
        var page = NotebookPage()
        page.width = 200; page.height = 200
        page.layers = [DrawingLayer(elements: [DrawingElement(color: InkColor(red: 1, green: 0, blue: 0), width: 60,
            points: [InkPoint(x: 30, y: 100), InkPoint(x: 170, y: 100)])])]
        let redOnly = PageRenderer.image(page, maxDimension: 200)
        page.layers.append(DrawingLayer(name: "Top", elements: [
            DrawingElement(color: InkColor(red: 0, green: 0, blue: 1), width: 40,
                           points: [InkPoint(x: 100, y: 30), InkPoint(x: 100, y: 170)]),
            DrawingElement(tool: .eraser, width: 60, points: [InkPoint(x: 100, y: 100)])
        ]))
        let erased = PageRenderer.image(page, maxDimension: 200)
        XCTAssertEqual(pixel(redOnly, x: 100, y: 100), pixel(erased, x: 100, y: 100))
        XCTAssertNotEqual(pixel(erased, x: 100, y: 50), pixel(redOnly, x: 100, y: 50))
    }

    @MainActor
    func testUndoRestoresEditedLayerAndRedoReapplies() {
        let page = NotebookPage()
        var saved: NotebookPage?
        let session = EditorSession(page: page) { saved = $0 }
        session.append(DrawingElement(points: [InkPoint(x: 5, y: 8)]))
        XCTAssertEqual(saved?.layers[0].elements.count, 1)
        session.undo()
        XCTAssertEqual(saved?.layers[0].elements.count, 0)
        session.redo()
        XCTAssertEqual(saved?.layers[0].elements.count, 1)
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) -> [UInt8] {
        guard let cgImage = image.cgImage else { XCTFail("Missing image"); return [] }
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: -CGFloat(x), y: -CGFloat(y))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return bytes
    }
}
