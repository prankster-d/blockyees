import Foundation

actor NotebookRepository {
    let root: URL
    init(root: URL) { self.root = root }

    func load() throws -> ([Notebook], [NotebookFolder], [String]) {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var notes: [Notebook] = []
        var warnings: [String] = []
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where url.pathExtension == "blockyees" {
            do { notes.append(try NotebookCodec.decode(Data(contentsOf: url))) }
            catch { warnings.append("Не удалось открыть \(url.lastPathComponent). Файл сохранён без изменений.") }
        }
        let foldersURL = root.appendingPathComponent("folders.json")
        var folders: [NotebookFolder] = []
        if FileManager.default.fileExists(atPath: foldersURL.path) {
            do { folders = try JSONDecoder().decode([NotebookFolder].self, from: Data(contentsOf: foldersURL)) }
            catch { warnings.append("Не удалось прочитать список папок.") }
        }
        return (notes, folders, warnings)
    }

    func save(_ note: Notebook) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(note.id.uuidString).appendingPathExtension("blockyees")
        if let oldData = try? Data(contentsOf: url), let old = try? NotebookCodec.decode(oldData),
           old.ancestors.contains(note.revision) { return }
        try NotebookCodec.encode(note).write(to: url, options: .atomic)
    }

    func saveFolders(_ folders: [NotebookFolder]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(folders).write(to: root.appendingPathComponent("folders.json"), options: .atomic)
    }
}
