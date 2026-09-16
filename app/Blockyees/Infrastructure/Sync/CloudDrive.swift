import Foundation

actor CloudDrive {
    struct Result {
        var notes: [Notebook]
        var folders: [NotebookFolder]
    }
    enum SyncError: LocalizedError {
        case unavailable, downloading
        var errorDescription: String? {
            switch self {
            case .unavailable: return "iCloud недоступен. Проверь вход в iCloud и разрешение iCloud Drive для Blockyees. Записи сохранены на устройстве."
            case .downloading: return "iCloud загружает документы. Повторим синхронизацию после загрузки."
            }
        }
    }

    func synchronize(notes: [Notebook], folders: [NotebookFolder]) throws -> Result {
        let manager = FileManager.default
        guard let container = manager.url(forUbiquityContainerIdentifier: nil) else { throw SyncError.unavailable }
        let root = container.appendingPathComponent("Documents/Notebooks", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        var all = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var mergedFolders = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        let urls = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])
        for url in urls {
            if url.lastPathComponent.hasSuffix(".icloud") {
                try manager.startDownloadingUbiquitousItem(at: url)
                throw SyncError.downloading
            }
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values.ubiquitousItemDownloadingStatus, status == .notDownloaded {
                try manager.startDownloadingUbiquitousItem(at: url)
                throw SyncError.downloading
            }
            if url.pathExtension == "folder" {
                let folder = try JSONDecoder().decode(NotebookFolder.self, from: coordinatedRead(url))
                mergedFolders[folder.id] = folder
            } else if url.pathExtension == "blockyees" {
                let note = try NotebookCodec.decode(coordinatedRead(url))
                integrate(note, into: &all)
                // Preserve every system conflict before marking it resolved.
                for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
                    let conflict = try NotebookCodec.decode(Data(contentsOf: version.url))
                    integrate(conflict, into: &all)
                }
            }
        }
        for folder in mergedFolders.values {
            let url = root.appendingPathComponent(folder.id.uuidString).appendingPathExtension("folder")
            try coordinatedWrite(JSONEncoder().encode(folder), to: url)
        }
        // Re-read under the writing coordination lock to protect against another device's update.
        for note in Array(all.values) {
            let url = root.appendingPathComponent(note.id.uuidString).appendingPathExtension("blockyees")
            let written = try publish(note, at: url, root: root)
            for value in written { all[value.id] = value }
        }
        return Result(notes: Array(all.values), folders: Array(mergedFolders.values))
    }

    private func integrate(_ note: Notebook, into all: inout [UUID: Notebook]) {
        for merged in all[note.id].map({ RevisionMerge.merge($0, note) }) ?? [note] {
            all[merged.id] = merged
        }
    }

    private func publish(_ note: Notebook, at url: URL, root: URL) throws -> [Notebook] {
        var coordinationError: NSError?
        var operation: Swift.Result<[Notebook], Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinated in
            operation = Swift.Result {
                var values = [note]
                if FileManager.default.fileExists(atPath: coordinated.path) {
                    let other = try NotebookCodec.decode(Data(contentsOf: coordinated))
                    values = RevisionMerge.merge(note, other)
                }
                // The conflict copy must be durable before the primary document changes.
                for copy in values.dropFirst() {
                    let copyURL = root.appendingPathComponent(copy.id.uuidString).appendingPathExtension("blockyees")
                    if FileManager.default.fileExists(atPath: copyURL.path) {
                        let existing = try NotebookCodec.decode(Data(contentsOf: copyURL))
                        // A recovered copy may already have been edited on another device.
                        // Never replace its newer contents with the original conflict snapshot.
                        for preserved in RevisionMerge.merge(existing, copy) {
                            let target = root.appendingPathComponent(preserved.id.uuidString).appendingPathExtension("blockyees")
                            try NotebookCodec.encode(preserved).write(to: target, options: .atomic)
                        }
                    } else {
                        try NotebookCodec.encode(copy).write(to: copyURL, options: .atomic)
                    }
                }
                try NotebookCodec.encode(values[0]).write(to: coordinated, options: .atomic)
                // Do not remove system conflict versions here: they remain a recovery source.
                return values
            }
        }
        if let coordinationError { throw coordinationError }
        guard let operation else { throw SyncError.unavailable }
        return try operation.get()
    }

    private func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var operation: Swift.Result<Data, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            operation = Swift.Result { try Data(contentsOf: coordinated) }
        }
        if let coordinationError { throw coordinationError }
        guard let operation else { throw SyncError.unavailable }
        return try operation.get()
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var operation: Swift.Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &coordinationError) { coordinated in
            operation = Swift.Result { try data.write(to: coordinated, options: .atomic) }
        }
        if let coordinationError { throw coordinationError }
        guard let operation else { throw SyncError.unavailable }
        try operation.get()
    }
}
