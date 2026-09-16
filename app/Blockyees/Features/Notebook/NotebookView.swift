import SwiftUI

struct NotebookView: View {
    @EnvironmentObject private var store: NotebookStore
    let notebookID: UUID
    @State private var editingPage: NotebookPage?
    @State private var pendingDelete: UUID?
    @State private var copiedPage: NotebookPage?
    @State private var horizontal = false
    @State private var thumbnailWidth: Double = 220
    @State private var exporting = false
    @State private var share: ShareItem?
    @State private var shareError: String?
    @State private var selectedPageIDs: Set<UUID> = []

    var body: some View {
        if let notebook = store.notebook(notebookID) {
            VStack(spacing: 0) {
                HStack {
                    Text("\(notebook.pages.count) страниц").foregroundStyle(.secondary)
                    Spacer()
                    Picker("Порядок страниц", selection: Binding(get: { notebook.pageOrder }, set: { order in
                        store.mutate(notebookID) { $0.pageOrder = order }
                    })) {
                        ForEach(PageOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("pageOrder")
                }.padding()
                if notebook.pages.isEmpty {
                    ContentUnavailableView {
                        Label("Первая чистая страница", systemImage: "doc.badge.plus")
                    } description: { Text("Добавь страницу, чтобы начать рисовать.") }
                    actions: { Button("Добавить страницу") { addPage(to: notebook) } }
                } else if horizontal {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 24) {
                            ForEach(notebook.orderedPages) { page in pageCard(page, notebook: notebook).frame(width: thumbnailWidth) }
                        }.padding(24)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailWidth), spacing: 24)], spacing: 24) {
                            ForEach(notebook.orderedPages) { page in pageCard(page, notebook: notebook) }
                        }.padding(24)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(notebook.title)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { addPage(to: notebook) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить страницу").accessibilityIdentifier("addPage").keyboardShortcut("n", modifiers: .command)
                    Menu {
                        Toggle("Горизонтальный обзор", isOn: $horizontal)
                        Button(thumbnailWidth < 200 ? "Крупные страницы" : "Компактные страницы") { thumbnailWidth = thumbnailWidth < 200 ? 220 : 150 }
                        Button("Вставить страницу") {
                            guard let copy = copiedPage?.duplicated() else { return }
                            store.mutate(notebookID) { $0.pages.append(copy) }
                        }.disabled(copiedPage == nil)
                        Button("Экспорт блокнота") { exporting = true }
                        Button("Экспорт PDF") {
                            do {
                                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
                                try DocumentIO.pdf(notebook).write(to: url, options: .atomic)
                                share = ShareItem(items: [url])
                            } catch { shareError = error.localizedDescription }
                        }.disabled(notebook.pages.isEmpty)
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Действия блокнота")
                }
            }
            .fullScreenCover(item: $editingPage) { page in
                EditorView(notebookID: notebookID, page: page) { changed in store.updatePage(notebookID, page: changed) }
                    .environmentObject(store)
            }
            .fileExporter(isPresented: $exporting, document: NotebookDocument(notebook: notebook), contentType: .blockyees, defaultFilename: notebook.title) { result in
                if case .failure(let error) = result { shareError = error.localizedDescription }
            }
            .sheet(item: $share) { ShareSheet(items: $0.items) }
            .alert("Удалить страницу?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Удалить", role: .destructive) {
                    if let id = pendingDelete { store.mutate(notebookID) { $0.pages.removeAll { $0.id == id } } }
                    pendingDelete = nil
                }
                Button("Отмена", role: .cancel) { pendingDelete = nil }
            } message: { Text("Действие удалит страницу из этого блокнота.") }
            .alert("Ошибка экспорта", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
                Button("Понятно") { shareError = nil }
            } message: { Text(shareError ?? "") }
        } else { ContentUnavailableView("Блокнот недоступен", systemImage: "doc") }
    }

    private func addPage(to notebook: Notebook, after pageID: UUID? = nil) {
        var page = NotebookPage()
        if let template = notebook.pages.first { page.width = template.width; page.height = template.height }
        store.mutate(notebookID) { note in
            if let pageID, let index = note.pages.firstIndex(where: { $0.id == pageID }) { note.pages.insert(page, at: index + 1) }
            else { note.pages.append(page) }
        }
    }

    private func pageCard(_ page: NotebookPage, notebook: Notebook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { editingPage = page } label: {
                PageThumbnail(page: page)
                    .aspectRatio(page.width / page.height, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            }.buttonStyle(.plain).accessibilityLabel("Открыть страницу \((notebook.pages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1)")
                .accessibilityIdentifier("page-\(page.id.uuidString)")
            HStack {
                Text("Страница \((notebook.pages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Menu {
                    Button("Открыть") { editingPage = page }
                    Button("Добавить после") { addPage(to: notebook, after: page.id) }
                    Button("Дублировать") {
                        let copy = page.duplicated()
                        store.mutate(notebookID) { note in
                            let index = note.pages.firstIndex { $0.id == page.id } ?? note.pages.count - 1
                            note.pages.insert(copy, at: index + 1)
                        }
                    }
                    Button("Копировать") { copiedPage = page }
                    Button("В начало основного порядка") {
                        store.mutate(notebookID) { note in
                            note.pages.removeAll { $0.id == page.id }; note.pages.insert(page, at: 0)
                        }
                    }
                    Button("Удалить", role: .destructive) { pendingDelete = page.id }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Действия страницы")
            }
        }
    }
}

struct PageThumbnail: View {
    let page: NotebookPage
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Rectangle().fill(.white).overlay { ProgressView() } }
        }.task(id: "\(page.id)-\(page.modifiedAt.timeIntervalSince1970)") { image = PageRenderer.image(page) }
    }
}
