import Foundation

struct InkColor: Codable, Equatable {
    var red: Double = 0.12
    var green: Double = 0.14
    var blue: Double = 0.18
    var alpha: Double = 1
}

enum DrawingTool: String, Codable, CaseIterable {
    case pen, pencil, marker, eraser, select
    var title: String {
        switch self {
        case .pen: return "Перо"
        case .pencil: return "Карандаш"
        case .marker: return "Маркер"
        case .eraser: return "Ластик"
        case .select: return "Выделение"
        }
    }
    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        case .select: return "lasso"
        }
    }
}

struct InkPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var pressure: Double = 1
}

struct DrawingElement: Codable, Equatable, Identifiable {
    var id = UUID()
    var tool: DrawingTool = .pen
    var color = InkColor()
    var width: Double = 4
    var points: [InkPoint] = []
    var imageData: Data?
    var imageX: Double = 0
    var imageY: Double = 0
    var imageWidth: Double = 0
    var imageHeight: Double = 0
    var imageRotation: Double = 0

    mutating func transform(dx: Double = 0, dy: Double = 0, scale: Double = 1,
                            rotation: Double = 0, center: InkPoint) {
        func transformed(_ p: InkPoint) -> InkPoint {
            let x = (p.x - center.x) * scale
            let y = (p.y - center.y) * scale
            return InkPoint(x: center.x + x * cos(rotation) - y * sin(rotation) + dx,
                            y: center.y + x * sin(rotation) + y * cos(rotation) + dy,
                            pressure: p.pressure)
        }
        points = points.map(transformed)
        width *= abs(scale)
        let p = transformed(InkPoint(x: imageX, y: imageY))
        imageX = p.x; imageY = p.y
        imageWidth *= abs(scale); imageHeight *= abs(scale)
        imageRotation += rotation
    }
}

struct DrawingLayer: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "Слой 1"
    var isVisible = true
    var opacity: Double = 1
    var elements: [DrawingElement] = []

    func duplicated() -> DrawingLayer {
        var copy = self
        copy.id = UUID()
        copy.name += " — копия"
        copy.elements = elements.map { element in
            var result = element; result.id = UUID(); return result
        }
        return copy
    }
}

struct NotebookPage: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt = Date()
    var modifiedAt = Date()
    var width: Double = 1200
    var height: Double = 1600
    var layers = [DrawingLayer()]

    func duplicated(at date: Date = Date()) -> NotebookPage {
        var copy = self
        copy.id = UUID(); copy.createdAt = date; copy.modifiedAt = date
        copy.layers = layers.map { layer in
            var l = layer.duplicated(); l.name = layer.name; return l
        }
        return copy
    }
}

enum PageOrder: String, Codable, CaseIterable {
    case original, recent
    var title: String { self == .original ? "По умолчанию" : "Более поздние страницы вверху" }
}

struct Notebook: Codable, Equatable, Identifiable {
    var schemaVersion = 1
    var id = UUID()
    var title = "Новый блокнот"
    var folderID: UUID?
    var folderName: String?
    var createdAt = Date()
    var modifiedAt = Date()
    var revision = UUID()
    var ancestors: Set<UUID> = []
    var isDeleted = false
    var pageOrder: PageOrder = .original
    var pages = [NotebookPage()]

    var orderedPages: [NotebookPage] {
        guard pageOrder == .recent else { return pages }
        return pages.sorted {
            if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    mutating func advance(at date: Date = Date()) {
        ancestors.insert(revision)
        revision = UUID()
        modifiedAt = date
    }

    func importedCopy() -> Notebook {
        var copy = self
        copy.id = UUID(); copy.revision = UUID(); copy.ancestors = []
        copy.folderID = nil; copy.folderName = nil; copy.isDeleted = false
        return copy
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw DocumentError.unsupportedVersion }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(pages.map(\.id)).count == pages.count else { throw DocumentError.invalidDocument }
        for page in pages {
            guard page.width.isFinite, page.height.isFinite,
                  (64...8192).contains(page.width), (64...8192).contains(page.height),
                  !page.layers.isEmpty, Set(page.layers.map(\.id)).count == page.layers.count else {
                throw DocumentError.invalidDocument
            }
            for layer in page.layers {
                guard layer.opacity.isFinite, (0...1).contains(layer.opacity),
                      Set(layer.elements.map(\.id)).count == layer.elements.count else {
                    throw DocumentError.invalidDocument
                }
                for element in layer.elements {
                    let values = [element.width, element.imageX, element.imageY, element.imageWidth,
                                  element.imageHeight, element.imageRotation, element.color.red,
                                  element.color.green, element.color.blue, element.color.alpha]
                    guard values.allSatisfy(\.isFinite), (0...2048).contains(element.width),
                          element.imageWidth >= 0, element.imageHeight >= 0,
                          element.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.pressure.isFinite && (0...2).contains($0.pressure) }) else {
                        throw DocumentError.invalidDocument
                    }
                }
            }
        }
    }
}

struct NotebookFolder: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
}

enum DocumentError: LocalizedError {
    case unsupportedVersion, invalidDocument, tooLarge, unsupportedFormat
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Этот файл создан более новой версией приложения."
        case .invalidDocument: return "Файл повреждён или содержит неподдерживаемые данные. Исходный файл не изменён."
        case .tooLarge: return "Файл превышает допустимый размер 100 МБ."
        case .unsupportedFormat: return "Формат пока не поддерживается. Импортируй файл .blockyees, изображение или PDF."
        }
    }
}

enum NotebookCodec {
    static let maximumBytes = 100 * 1024 * 1024
    static func encode(_ notebook: Notebook) throws -> Data {
        try notebook.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(notebook)
        guard data.count <= maximumBytes else { throw DocumentError.tooLarge }
        return data
    }
    static func decode(_ data: Data) throws -> Notebook {
        guard data.count <= maximumBytes else { throw DocumentError.tooLarge }
        let note = try JSONDecoder().decode(Notebook.self, from: data)
        try note.validate()
        return note
    }
}

/// Concurrent revisions remain separate documents, never flattened or silently discarded.
enum RevisionMerge {
    static func merge(_ local: Notebook, _ remote: Notebook) -> [Notebook] {
        guard local.id == remote.id else { return [local, remote] }
        if local.revision == remote.revision { return [local] }
        if local.ancestors.contains(remote.revision) { return [local] }
        if remote.ancestors.contains(local.revision) { return [remote] }
        // A stable winner and copy ID make repeated sync idempotent on all devices.
        var winner = local.revision.uuidString < remote.revision.uuidString ? local : remote
        var other = winner.revision == local.revision ? remote : local
        other.id = other.revision
        other.title += " — конфликт"
        other.isDeleted = false
        winner.ancestors.formUnion(other.ancestors)
        winner.ancestors.insert(other.revision)
        return [winner, other]
    }
}
