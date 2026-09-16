import SwiftUI

@MainActor
final class EditorSession: ObservableObject {
    @Published var page: NotebookPage
    @Published var activeLayerID: UUID
    @Published var tool: DrawingTool = .pen
    @Published var color = Color(red: 0.12, green: 0.14, blue: 0.18)
    @Published var width: Double = 4
    @Published var fixedWidth = false
    @Published var pencilOnly = false
    @Published var fingerEraser = false
    @Published var straightLine = false
    @Published var mirror = false
    @Published var onionBefore = 0
    @Published var onionAfter = 0
    @Published var selection: Set<UUID> = []
    @Published var fitRequest = UUID()
    @Published private(set) var undoStack: [NotebookPage] = []
    @Published private(set) var redoStack: [NotebookPage] = []
    var layerClipboard: DrawingLayer?
    var selectionClipboard: [DrawingElement] = []
    var onSave: (NotebookPage) -> Void

    init(page: NotebookPage, onSave: @escaping (NotebookPage) -> Void) {
        self.page = page; activeLayerID = page.layers[0].id; self.onSave = onSave
    }

    var activeIndex: Int? { page.layers.firstIndex { $0.id == activeLayerID } }
    var canDraw: Bool {
        guard let index = activeIndex else { return false }
        return page.layers[index].isVisible && page.layers[index].opacity > 0
    }

    func edit(_ mutation: (inout NotebookPage) -> Void) {
        let before = page
        mutation(&page)
        guard page != before else { return }
        undoStack.append(before)
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
        page.modifiedAt = Date()
        onSave(page)
    }

    func append(_ element: DrawingElement) {
        guard let index = activeIndex, canDraw else { return }
        edit { $0.layers[index].elements.append(element) }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(page); page = previous; reconcileSelection(); onSave(page)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(page); page = next; reconcileSelection(); onSave(page)
    }

    private func reconcileSelection() {
        if !page.layers.contains(where: { $0.id == activeLayerID }) { activeLayerID = page.layers[0].id }
        selection.removeAll()
    }

    func addLayer() {
        let layer = DrawingLayer(name: "Слой \(page.layers.count + 1)")
        edit { $0.layers.append(layer) }; activeLayerID = layer.id; selection = []
    }

    func copyLayer() { layerClipboard = page.layers.first { $0.id == activeLayerID } }
    func pasteLayer() {
        guard let copy = layerClipboard?.duplicated() else { return }
        edit { $0.layers.append(copy) }; activeLayerID = copy.id; selection = []
    }

    var selectedBounds: CGRect? {
        guard let index = activeIndex else { return nil }
        var rect = CGRect.null
        for element in page.layers[index].elements where selection.contains(element.id) {
            if element.imageData != nil {
                let radius = hypot(element.imageWidth, element.imageHeight) / 2
                rect = rect.union(CGRect(x: element.imageX - radius, y: element.imageY - radius, width: radius * 2, height: radius * 2))
            } else {
                for point in element.points {
                    rect = rect.union(CGRect(x: point.x - element.width / 2, y: point.y - element.width / 2,
                                             width: max(1, element.width), height: max(1, element.width)))
                }
            }
        }
        return rect.isNull ? nil : rect
    }

    func transformSelection(dx: Double = 0, dy: Double = 0, scale: Double = 1, rotation: Double = 0) {
        guard let index = activeIndex, let bounds = selectedBounds else { return }
        let ids = selection
        edit { page in
            for i in page.layers[index].elements.indices where ids.contains(page.layers[index].elements[i].id) {
                page.layers[index].elements[i].transform(dx: dx, dy: dy, scale: scale, rotation: rotation,
                    center: InkPoint(x: bounds.midX, y: bounds.midY))
            }
        }
    }

    func copySelection() {
        guard let index = activeIndex else { return }
        selectionClipboard = page.layers[index].elements.filter { selection.contains($0.id) }
    }

    func pasteSelection() {
        guard let index = activeIndex else { return }
        let copies = selectionClipboard.map { element -> DrawingElement in
            var copy = element; copy.id = UUID()
            copy.transform(dx: 20, dy: 20, center: InkPoint(x: 0, y: 0))
            return copy
        }
        edit { $0.layers[index].elements.append(contentsOf: copies) }
        selection = Set(copies.map(\.id))
    }

    func deleteSelection() {
        guard let index = activeIndex else { return }
        let ids = selection
        edit { $0.layers[index].elements.removeAll { ids.contains($0.id) } }
        selection.removeAll()
    }

    func insertImage(_ image: UIImage) throws {
        guard let index = activeIndex else { return }
        let imagePage = try DocumentIO.page(from: image)
        var element = imagePage.layers[0].elements[0]
        let factor = min(1, min(page.width / element.imageWidth, page.height / element.imageHeight) * 0.85)
        element.imageWidth *= factor; element.imageHeight *= factor
        element.imageX = page.width / 2; element.imageY = page.height / 2
        edit { $0.layers[index].elements.append(element) }
        selection = [element.id]; tool = .select
    }
}
