import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var store: NotebookStore
    @State private var folderID: UUID?
    @State private var showUnfiled = false
    @State private var path: [UUID] = []
    @State private var search = ""
    @State private var showNewNotebook = false
    @State private var showNewFolder = false
    @State private var folderName = ""
    @State private var importing = false
    @State private var settings = false
    @State private var deleteID: UUID?
    @State private var renameID: UUID?
    @State private var newName = ""

    private var currentFolder: NotebookFolder? { store.folders.first { $0.id == folderID } }
    private var filtered: [Notebook] {
        store.visibleNotebooks.filter { note in
            (folderID == nil || note.folderID == folderID) && (!showUnfiled || note.folderID == nil) && (search.isEmpty || note.title.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Button { folderID = nil; showUnfiled = false; path = [] } label: { Label("Все блокноты", systemImage: "square.grid.2x2") }
                    .listRowBackground(folderID == nil && !showUnfiled ? Color.teal.opacity(0.12) : Color.clear)
                Button { folderID = nil; showUnfiled = true; path = [] } label: { Label("Без папки", systemImage: "tray") }
                    .listRowBackground(showUnfiled ? Color.teal.opacity(0.12) : Color.clear)
                Section("Папки") {
                    ForEach(store.folders.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { folder in
                        Button { folderID = folder.id; showUnfiled = false; path = [] } label: { Label(folder.name, systemImage: "folder") }
                            .listRowBackground(folderID == folder.id ? Color.teal.opacity(0.12) : Color.clear)
                    }
                    Button { showNewFolder = true } label: { Label("Новая папка", systemImage: "folder.badge.plus") }
                        .accessibilityIdentifier("newFolder")
                }
            }.navigationTitle("Blockyees")
                .safeAreaInset(edge: .bottom) {
                    Button { settings = true } label: {
                        Label("Настройки", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading).padding()
                    }.background(.bar)
                }
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if store.isLoading { ProgressView("Открываем библиотеку…") }
                    else if filtered.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "book.closed").font(.system(size: 48)).foregroundStyle(.secondary)
                            Text(search.isEmpty ? "Место для твоих идей" : "Ничего не найдено").font(.title2.bold())
                            Text(search.isEmpty ? "Создай блокнот или импортируй документ." : "Попробуй другое название.")
                                .foregroundStyle(.secondary)
                            Button("Создать блокнот") { showNewNotebook = true }.buttonStyle(.borderedProminent)
                        }.multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 24)], spacing: 24) {
                                ForEach(filtered) { note in notebookCard(note) }
                            }.padding(24)
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(currentFolder?.name ?? (showUnfiled ? "Без папки" : "Мои блокноты"))
                .searchable(text: $search, prompt: "Найти блокнот")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                            .accessibilityLabel("Импортировать блокнот")
                        Button { showNewNotebook = true } label: { Label("Новый блокнот", systemImage: "plus") }
                            .accessibilityIdentifier("newNotebook")
                    }
                }
                .navigationDestination(for: UUID.self) { id in NotebookView(notebookID: id) }
            }
        }
        .sheet(isPresented: $showNewNotebook) {
            NewNotebookSheet { title, width, height in
                let id = store.createNotebook(title: title, folder: currentFolder, width: width, height: height)
                showNewNotebook = false; path = [id]
            }
        }
        .sheet(isPresented: $settings) { AppSettingsView() }
        .alert("Новая папка", isPresented: $showNewFolder) {
            TextField("Название", text: $folderName)
            Button("Создать") { store.createFolder(folderName); folderName = "" }
            Button("Отмена", role: .cancel) { folderName = "" }
        }
        .alert("Название блокнота", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("Название", text: $newName)
            Button("Сохранить") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = renameID, !trimmed.isEmpty { store.mutate(id) { $0.title = trimmed } }
                renameID = nil
            }
            Button("Отмена", role: .cancel) { renameID = nil }
        }
        .alert("Удалить блокнот?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Удалить", role: .destructive) { if let id = deleteID { store.delete(id) }; deleteID = nil }
            Button("Отмена", role: .cancel) { deleteID = nil }
        } message: { Text("Блокнот будет удалён из библиотеки и синхронизированных устройств.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.blockyees, .image, .pdf, .data]) { result in
            do { store.addImported(try DocumentIO.importNotebook(at: result.get()), folder: currentFolder) }
            catch { store.errorMessage = error.localizedDescription }
        }
    }

    private func notebookCard(_ note: Notebook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { path.append(note.id) } label: {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 18).fill(Color.teal.opacity(0.10))
                    if let page = note.pages.first {
                        PageThumbnail(page: page).padding(18).rotationEffect(.degrees(-3))
                    } else { Image(systemName: "book.closed").font(.system(size: 48)).foregroundStyle(.teal) }
                }.frame(height: 220).clipped()
            }.buttonStyle(.plain).accessibilityLabel("Открыть \(note.title)")
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(note.title).font(.headline).lineLimit(2)
                    Text("\(note.pages.count) страниц").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Переименовать") { newName = note.title; renameID = note.id }
                    Menu("Переместить") {
                        Button("Без папки") { store.move(note.id, to: nil) }
                        ForEach(store.folders) { folder in Button(folder.name) { store.move(note.id, to: folder) } }
                    }
                    Button("Дублировать") { store.addImported(note, folder: currentFolder) }
                    Button("Удалить", role: .destructive) { deleteID = note.id }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Действия блокнота \(note.title)")
            }
        }
    }
}

struct NewNotebookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var format = 0
    @State private var customWidth = 1200.0
    @State private var customHeight = 1600.0
    var create: (String, Double, Double) -> Void
    private let sizes: [(String, Double, Double)] = [("Портрет 3:4", 1200, 1600), ("Альбом 4:3", 1600, 1200), ("Квадрат", 1400, 1400), ("Широкая 16:9", 1920, 1080), ("Вертикальная 9:16", 1080, 1920)]
    var body: some View {
        NavigationStack {
            Form {
                Section("Название") { TextField("Новый блокнот", text: $title).accessibilityIdentifier("notebookTitle") }
                Section("Страница") {
                    Picker("Формат", selection: $format) {
                        ForEach(sizes.indices, id: \.self) { Text(sizes[$0].0).tag($0) }
                        Text("Свой размер").tag(5)
                    }
                    if format == 5 {
                        Stepper("Ширина: \(Int(customWidth))", value: $customWidth, in: 200...4000, step: 100)
                        Stepper("Высота: \(Int(customHeight))", value: $customHeight, in: 200...4000, step: 100)
                    }
                }
            }.navigationTitle("Новый блокнот")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Создать") { create(title, format == 5 ? customWidth : sizes[format].1, format == 5 ? customHeight : sizes[format].2) }
                            .accessibilityIdentifier("createNotebook")
                    }
                }
        }.presentationDetents([.medium, .large])
    }
}

struct AppSettingsView: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            Form {
                Section("Оформление") {
                    Picker("Тема", selection: $appearance) {
                        Text("Системная").tag("system"); Text("Светлая").tag("light"); Text("Тёмная").tag("dark")
                    }
                }
                Section("iCloud") {
                    Toggle("Синхронизация", isOn: $store.cloudEnabled)
                        .onChange(of: store.cloudEnabled) { _, enabled in if enabled { Task { await store.synchronize() } } }
                    Text(store.syncMessage).font(.footnote).foregroundStyle(.secondary)
                    Button("Синхронизировать сейчас") { Task { await store.synchronize() } }
                        .disabled(!store.cloudEnabled || store.isSyncing)
                    Text("При одновременных изменениях сохраняются обе версии блокнота. Конфликтующая копия появится в библиотеке.").font(.footnote)
                }
                Section("Файлы") {
                    Text("Формат .blockyees сохраняет слои и штрихи. Изображения и PDF импортируются как изображения страниц. Для редактируемой резервной копии используй экспорт блокнота.").font(.footnote)
                    Button("Повторить сохранение") { store.retrySave() }
                }
            }.navigationTitle("Настройки").toolbar { Button("Готово") { dismiss() } }
        }
    }
}
