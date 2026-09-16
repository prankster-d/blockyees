import UIKit

extension InkColor {
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        red = Double(r); green = Double(g); blue = Double(b); alpha = Double(a)
    }
}

enum PageRenderer {
    static func image(_ page: NotebookPage, maxDimension: CGFloat = 600) -> UIImage {
        let scale = min(1, maxDimension / max(page.width, page.height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: page.width * scale, height: page.height * scale), format: format).image {
            $0.cgContext.scaleBy(x: scale, y: scale)
            draw(page, in: $0.cgContext, background: true)
        }
    }

    static func draw(_ page: NotebookPage, in context: CGContext, background: Bool,
                     extra: DrawingElement? = nil, activeLayer: UUID? = nil) {
        if background {
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: page.width, height: page.height))
        }
        for layer in page.layers where layer.isVisible && layer.opacity > 0 {
            context.saveGState()
            context.setAlpha(layer.opacity)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            for element in layer.elements { draw(element, in: context) }
            if layer.id == activeLayer, let extra { draw(extra, in: context) }
            context.endTransparencyLayer()
            context.restoreGState()
        }
    }

    static func draw(_ element: DrawingElement, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        if let data = element.imageData, let image = UIImage(data: data) {
            context.translateBy(x: element.imageX, y: element.imageY)
            context.rotate(by: element.imageRotation)
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(x: -element.imageWidth / 2, y: -element.imageHeight / 2,
                                  width: element.imageWidth, height: element.imageHeight))
            UIGraphicsPopContext()
            return
        }
        guard let first = element.points.first else { return }
        let alpha = element.tool == .marker ? 0.28 : element.tool == .pencil ? 0.65 : 1
        context.setAlpha(alpha)
        context.setBlendMode(element.tool == .eraser ? .clear : .normal)
        context.setStrokeColor(element.color.uiColor.cgColor)
        context.setFillColor(element.color.uiColor.cgColor)
        context.setLineCap(.round); context.setLineJoin(.round)
        if element.points.count == 1 {
            let width = max(0.5, element.width * first.pressure)
            context.fillEllipse(in: CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width))
        }
        for pair in zip(element.points, element.points.dropFirst()) {
            context.setLineWidth(max(0.5, element.width * (pair.0.pressure + pair.1.pressure) / 2))
            context.move(to: CGPoint(x: pair.0.x, y: pair.0.y))
            context.addLine(to: CGPoint(x: pair.1.x, y: pair.1.y))
            context.strokePath()
        }
    }
}
