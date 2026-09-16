import SwiftUI
import UIKit

struct DrawingCanvas: UIViewRepresentable {
    @ObservedObject var session: EditorSession
    var previousPages: [NotebookPage]
    var nextPages: [NotebookPage]

    func makeUIView(context: Context) -> CanvasScrollView {
        let view = CanvasScrollView()
        view.surface.session = session
        return view
    }
    func updateUIView(_ view: CanvasScrollView, context: Context) {
        view.surface.session = session
        view.surface.onions = Array(previousPages.prefix(session.onionBefore)) + Array(nextPages.prefix(session.onionAfter))
        view.surface.refreshLayerCache()
        view.surface.setNeedsDisplay()
        let size = CGSize(width: session.page.width, height: session.page.height)
        if view.surface.bounds.size != size {
            view.setZoomScale(1, animated: false)
            view.surface.frame = CGRect(origin: .zero, size: size)
            view.contentSize = size
            view.needsFit = true
        }
        if view.lastFit != session.fitRequest {
            view.lastFit = session.fitRequest; view.needsFit = true; view.setNeedsLayout()
        }
    }
}

final class CanvasScrollView: UIScrollView, UIScrollViewDelegate {
    let surface = DrawingSurface()
    var needsFit = true
    var lastFit: UUID?
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemBackground
        delegate = self
        minimumZoomScale = 0.05; maximumZoomScale = 5
        panGestureRecognizer.minimumNumberOfTouches = 2
        delaysContentTouches = false
        addSubview(surface)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layoutSubviews() {
        super.layoutSubviews()
        if needsFit, bounds.width > 0, surface.bounds.width > 0 {
            needsFit = false
            let fit = min((bounds.width - 32) / surface.bounds.width, (bounds.height - 32) / surface.bounds.height)
            setZoomScale(max(0.05, fit), animated: false)
        }
        contentInset = UIEdgeInsets(top: max(16, (bounds.height - contentSize.height) / 2), left: max(16, (bounds.width - contentSize.width) / 2), bottom: 16, right: 16)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { surface }
}

final class DrawingSurface: UIView, UIDropInteractionDelegate, UIPencilInteractionDelegate {
    weak var session: EditorSession?
    var onions: [NotebookPage] = []
    private var stroke: DrawingElement?
    private var lasso: [CGPoint] = []
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var trackedTouch: UITouch?
    private var layerCache: [UUID: (DrawingLayer, UIImage)] = [:]
    private var cacheSize = CGSize.zero

    func refreshLayerCache() {
        guard let session else { return }
        let size = CGSize(width: session.page.width, height: session.page.height)
        if cacheSize != size { layerCache.removeAll(); cacheSize = size }
        let ids = Set(session.page.layers.map(\.id))
        layerCache = layerCache.filter { ids.contains($0.key) }
        for layer in session.page.layers {
            if layerCache[layer.id]?.0 == layer { continue }
            let scale = min(1, 1600 / max(size.width, size.height))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale), format: format).image {
                $0.cgContext.scaleBy(x: scale, y: scale)
                for element in layer.elements { PageRenderer.draw(element, in: $0.cgContext) }
            }
            layerCache[layer.id] = (layer, image)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = .white
        contentMode = .redraw
        accessibilityLabel = "Холст страницы"
        accessibilityHint = "Рисуй одним пальцем или стилусом. Два пальца перемещают и масштабируют холст."
        addInteraction(UIDropInteraction(delegate: self))
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func draw(_ rect: CGRect) {
        guard let session, let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.white.cgColor); context.fill(bounds)
        if session.mirror { context.translateBy(x: bounds.width, y: 0); context.scaleBy(x: -1, y: 1) }
        for onion in onions {
            context.saveGState(); context.setAlpha(0.12)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            PageRenderer.draw(onion, in: context, background: false)
            context.endTransparencyLayer()
            context.restoreGState()
        }
        var preview = session.page
        if let start = dragStart, let current = dragCurrent, let index = session.activeIndex {
            for i in preview.layers[index].elements.indices where session.selection.contains(preview.layers[index].elements[i].id) {
                preview.layers[index].elements[i].transform(dx: current.x - start.x, dy: current.y - start.y, center: InkPoint(x: 0, y: 0))
            }
        }
        if dragStart != nil {
            PageRenderer.draw(preview, in: context, background: false)
        } else {
            for layer in preview.layers where layer.isVisible && layer.opacity > 0 {
                context.saveGState(); context.setAlpha(layer.opacity)
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                if let image = layerCache[layer.id]?.1 { image.draw(in: bounds) }
                else { for element in layer.elements { PageRenderer.draw(element, in: context) } }
                if layer.id == session.activeLayerID, let stroke { PageRenderer.draw(stroke, in: context) }
                context.endTransparencyLayer(); context.restoreGState()
            }
        }
        context.setStrokeColor(UIColor.systemTeal.cgColor)
        context.setLineWidth(2)
        context.setLineDash(phase: 0, lengths: [8, 5])
        if let first = lasso.first {
            context.move(to: first); for point in lasso.dropFirst() { context.addLine(to: point) }; context.strokePath()
        }
        if var box = session.selectedBounds {
            if let start = dragStart, let current = dragCurrent { box = box.offsetBy(dx: current.x - start.x, dy: current.y - start.y) }
            context.stroke(box.insetBy(dx: -5, dy: -5))
        }
    }

    private func position(_ touch: UITouch) -> CGPoint {
        let p = touch.location(in: self)
        return CGPoint(x: session?.mirror == true ? bounds.width - p.x : p.x, y: p.y)
    }
    private func sample(_ touch: UITouch) -> InkPoint {
        let p = position(touch)
        let pressure: Double
        if session?.fixedWidth == true || touch.type != .pencil || touch.maximumPossibleForce <= 0 { pressure = 1 }
        else { pressure = max(0.15, min(2, Double(touch.force / touch.maximumPossibleForce) * 2)) }
        return InkPoint(x: p.x, y: p.y, pressure: pressure)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let session, let touch = touches.first, trackedTouch == nil else { cancelGesture(); return }
        if event?.allTouches?.count ?? 0 > 1 { cancelGesture(); return }
        if session.pencilOnly && touch.type != .pencil { return }
        guard session.canDraw else { return }
        trackedTouch = touch
        let point = position(touch)
        if session.tool == .select {
            if session.selectedBounds?.insetBy(dx: -20, dy: -20).contains(point) == true {
                dragStart = point; dragCurrent = point
            } else { session.selection = []; lasso = [point] }
        } else {
            let tool = session.fingerEraser && touch.type != .pencil ? DrawingTool.eraser : session.tool
            stroke = DrawingElement(tool: tool, color: InkColor(UIColor(session.color)), width: session.width, points: [sample(touch)])
        }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch), let session else { return }
        if dragStart != nil { dragCurrent = position(touch) }
        else if session.tool == .select { lasso.append(position(touch)) }
        else if session.straightLine, let first = stroke?.points.first {
            stroke?.points = [first, sample(touch)]
        } else {
            stroke?.points.append(contentsOf: (event?.coalescedTouches(for: touch) ?? [touch]).map(sample))
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch), let session else { return }
        if let start = dragStart {
            let end = position(touch)
            session.transformSelection(dx: end.x - start.x, dy: end.y - start.y)
        } else if session.tool == .select, let index = session.activeIndex {
            let path = UIBezierPath()
            if let first = lasso.first { path.move(to: first) }
            for point in lasso.dropFirst() { path.addLine(to: point) }; path.close()
            session.selection = Set(session.page.layers[index].elements.filter { element in
                element.imageData != nil ? path.contains(CGPoint(x: element.imageX, y: element.imageY)) :
                    element.points.contains { path.contains(CGPoint(x: $0.x, y: $0.y)) }
            }.map(\.id))
        } else if var completed = stroke {
            if session.straightLine { completed.points = [completed.points[0], sample(touch)] }
            else { completed.points.append(sample(touch)) }
            session.append(completed)
        }
        cancelGesture()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancelGesture() }
    private func cancelGesture() {
        trackedTouch = nil; stroke = nil; lasso = []; dragStart = nil; dragCurrent = nil; setNeedsDisplay()
    }

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        session?.tool = session?.tool == .eraser ? .pen : .eraser
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool { session.canLoadObjects(ofClass: UIImage.self) }
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal { UIDropProposal(operation: .copy) }
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        session.loadObjects(ofClass: UIImage.self) { [weak self] objects in
            DispatchQueue.main.async {
                for case let image as UIImage in objects { try? self?.session?.insertImage(image) }
            }
        }
    }
}
