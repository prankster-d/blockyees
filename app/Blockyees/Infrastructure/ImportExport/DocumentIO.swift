import SwiftUI
import UniformTypeIdentifiers
import PDFKit

extension UTType {
    static let blockyees = UTType(exportedAs: "app.blockyees.notebook", conformingTo: .data)
}

struct NotebookDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.blockyees] }
    var notebook: Notebook
    init(notebook: Notebook) { self.notebook = notebook }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw DocumentError.invalidDocument }
        notebook = try NotebookCodec.decode(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try NotebookCodec.encode(notebook))
    }
}

enum DocumentIO {
    static func importNotebook(at url: URL) throws -> Notebook {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= NotebookCodec.maximumBytes else { throw DocumentError.tooLarge }
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "blockyees" { return try NotebookCodec.decode(data) }
        var note = Notebook()
        note.title = url.deletingPathExtension().lastPathComponent
        if let image = UIImage(data: data) {
            note.pages = [try page(from: image)]; return note
        }
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(data: data) {
            guard pdf.pageCount > 0, pdf.pageCount <= 200 else { throw DocumentError.invalidDocument }
            note.pages = try (0..<pdf.pageCount).map { index in
                guard let pdfPage = pdf.page(at: index) else { throw DocumentError.invalidDocument }
                let bounds = pdfPage.bounds(for: .mediaBox)
                let factor = min(1, 2000 / max(bounds.width, bounds.height))
                return try page(from: pdfPage.thumbnail(of: CGSize(width: bounds.width * factor, height: bounds.height * factor), for: .mediaBox))
            }
            return note
        }
        throw DocumentError.unsupportedFormat
    }

    static func page(from image: UIImage) throws -> NotebookPage {
        let ratio = min(1, 2400 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(64, image.size.width * ratio), height: max(64, image.size.height * ratio))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = normalized.pngData() else { throw DocumentError.invalidDocument }
        var page = NotebookPage()
        page.width = Double(size.width); page.height = Double(size.height)
        page.layers[0].elements = [DrawingElement(imageData: data, imageX: Double(size.width / 2),
            imageY: Double(size.height / 2), imageWidth: Double(size.width), imageHeight: Double(size.height))]
        return page
    }

    static func pdf(_ notebook: Notebook) -> Data {
        let pages = notebook.orderedPages
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        return renderer.pdfData { context in
            for page in pages {
                let rect = CGRect(x: 0, y: 0, width: page.width, height: page.height)
                context.beginPage(withBounds: rect, pageInfo: [:])
                PageRenderer.draw(page, in: context.cgContext, background: true)
            }
        }
    }
}
