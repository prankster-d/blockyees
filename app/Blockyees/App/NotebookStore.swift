import SwiftUI

@MainActor
final class NotebookStore: ObservableObject {
    @Published private(set) var notebooks: [Notebook] = []
    @Published private(set) var folders: [NotebookFolder] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var syncMessage = "На устройстве"
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingWrites = 0
    @Published var cloudEnabled: Bool {
        didSet { UserDefaults.standard.set(cloudEnabled, forKey: "cloudEnabled") }
    }
    let repository: NotebookRepository
    private let cloud = CloudDrive()
    private var loaded = false
    private var saveTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    var isEditorOpen = false

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blockyees", isDirectory: true)
        repository = NotebookRepository(root: root)
        cloudEnabled = UserDefaults.standard.bool(forKey: "cloudEnabled")
    }

    var visibleNotebooks: [Notebook] {
        notebooks.filter { !$0.isDeleted }.sorted { $0.modifiedAt > $1.modifiedAt }
    }
    func notebook(_ id: UUID) -> Notebook? { notebooks.first { $0.id == id && !$0.isDeleted } }

    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            let (notes, savedFolders, warnings) = try await repository.load()
            notebooks = notes; folders = savedFolders
            for note in notes { recoverFolder(from: note) }
            if !warnings.isEmpty { errorMessage = warnings.joined(separator: "\n") }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
        if cloudEnabled { await synchronize() }
    }

    @discardableResult
    func createNotebook(title: String, folder: NotebookFolder?, width: Double, height: Double) -> UUID {
        var note = Notebook()
        note.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if note.title.isEmpty { note.title = "Новый блокнот" }
        note.folderID = folder?.id; note.folderName = folder?.name
        note.pages[0].width = width; note.pages[0].height = height
        notebooks.append(note); persist(note)
        return note.id
    }

    func createFolder(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !folders.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "Папка с таким названием уже существует."; return
        }
        folders.append(NotebookFolder(name: trimmed))
        persistFolders()
    }

    func mutate(_ id: UUID, _ mutation: (inout Notebook) -> Void) {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
        var note = notebooks[index]
        mutation(&note)
        guard note != notebooks[index] else { return }
        note.advance()
        notebooks[index] = note
        persist(note)
    }

    func updatePage(_ noteID: UUID, page: NotebookPage) {
        mutate(noteID) { note in
            guard let index = note.pages.firstIndex(where: { $0.id == page.id }) else { return }
            var updated = page; updated.modifiedAt = Date(); note.pages[index] = updated
        }
    }

    func move(_ id: UUID, to folder: NotebookFolder?) {
        mutate(id) { $0.folderID = folder?.id; $0.folderName = folder?.name }
    }

    func delete(_ id: UUID) { mutate(id) { $0.isDeleted = true } }

    func addImported(_ note: Notebook, folder: NotebookFolder?) {
        var copy = note.importedCopy()
        copy.folderID = folder?.id; copy.folderName = folder?.name
        notebooks.append(copy); persist(copy)
    }

    func synchronize() async {
        guard cloudEnabled, !isSyncing, !isLoading, !isEditorOpen else { return }
        isSyncing = true; syncMessage = "Синхронизация…"
        await saveTask?.value
        do {
            let result = try await cloud.synchronize(notes: notebooks, folders: folders)
            guard !isEditorOpen else {
                syncMessage = "Синхронизация продолжится после закрытия страницы"
                isSyncing = false
                return
            }
            for folder in result.folders where !folders.contains(where: { $0.id == folder.id }) { folders.append(folder) }
            for incoming in result.notes {
                let merged = notebooks.first(where: { $0.id == incoming.id })
                    .map { RevisionMerge.merge($0, incoming) } ?? [incoming]
                for note in merged {
                    if let index = notebooks.firstIndex(where: { $0.id == note.id }) {
                        if notebooks[index] == note { continue }
                        notebooks[index] = note
                    } else { notebooks.append(note) }
                    recoverFolder(from: note)
                    persist(note, scheduleSync: false)
                }
            }
            persistFolders(scheduleSync: false)
            await saveTask?.value
            syncMessage = "Синхронизировано с iCloud"
        } catch { syncMessage = error.localizedDescription }
        isSyncing = false
    }

    private func recoverFolder(from note: Notebook) {
        if let id = note.folderID, let name = note.folderName, !folders.contains(where: { $0.id == id }) {
            folders.append(NotebookFolder(id: id, name: name))
        }
    }

    private func persist(_ note: Notebook, scheduleSync: Bool = true) {
        pendingWrites += 1
        let previous = saveTask
        saveTask = Task {
            await previous?.value
            do { try await repository.save(note) }
            catch { errorMessage = "Не удалось сохранить блокнот: \(error.localizedDescription). Не закрывай приложение; освободи место и повтори сохранение." }
            pendingWrites -= 1
        }
        if scheduleSync { queueSync() }
    }

    private func persistFolders(scheduleSync: Bool = true) {
        let snapshot = folders
        let previous = saveTask
        saveTask = Task {
            await previous?.value
            do { try await repository.saveFolders(snapshot) }
            catch { errorMessage = "Не удалось сохранить папки: \(error.localizedDescription)" }
        }
        if scheduleSync { queueSync() }
    }

    func retrySave() {
        for note in notebooks { persist(note, scheduleSync: false) }
        persistFolders()
    }

    func flush() async { await saveTask?.value }

    private func queueSync() {
        guard cloudEnabled else { return }
        syncTask?.cancel()
        syncTask = Task {
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            await synchronize()
        }
    }
}
