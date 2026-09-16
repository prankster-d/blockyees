import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject private var store: NotebookStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: EditorSession
    let notebookID: UUID
    @State private var showLayers = false
    @State private var showSettings = false
    @State private var importImage = false
    @State private var shareItem: ShareItem?
    @State private var localError: String?

    init(notebookID: UUID, page: NotebookPage, onSave: @escaping (NotebookPage) -> Void) {
        self.notebookID = notebookID
        _session = StateObject(wrappedValue: EditorSession(page: page, onSave: onSave))
    }

    private var neighbors: ([NotebookPage], [NotebookPage]) {
        guard let pages = store.notebook(notebookID)?.orderedPages,
              let index = pages.firstIndex(where: { $0.id == session.page.id }) else { return ([], []) }
        return (Array(pages.prefix(index).reversed()), Array(pages.dropFirst(index + 1)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tools
                    .padding(.horizontal).padding(.vertical, 10)
                    .background(.bar)
                if !session.canDraw {
                    Text("Выбранный слой скрыт. Включи его видимость или выбери другой слой.")
                        .font(.callout).foregroundStyle(.orange).padding(8)
                }
                DrawingCanvas(session: session, previousPages: neighbors.0, nextPages: neighbors.1)
                if session.tool == .select { selectionTools.padding(8).background(.bar) }
                HStack {
                    Label(session.page.layers.first(where: { $0.id == session.activeLayerID })?.name ?? "Слой", systemImage: "square.3.layers.3d")
                    Spacer()
                    Text(store.pendingWrites > 0 ? "Сохранение…" : "Два пальца — масштаб и перемещение")
                }.font(.caption).foregroundStyle(.secondary).padding(10).background(.bar)
            }
            .navigationTitle(store.notebook(notebookID)?.title ?? "Блокнот")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { store.isEditorOpen = true }
            .onDisappear {
                store.isEditorOpen = false
                Task { await store.synchronize() }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Страницы") { dismiss() }.accessibilityIdentifier("closeEditor")
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(session.undoStack.isEmpty).accessibilityLabel("Отменить").keyboardShortcut("z", modifiers: .command)
                    Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(session.redoStack.isEmpty).accessibilityLabel("Повторить").keyboardShortcut("z", modifiers: [.command, .shift])
                    Button { showLayers = true } label: { Image(systemName: "square.3.layers.3d") }
                        .accessibilityLabel("Слои").accessibilityIdentifier("layersButton")
                    Menu {
                        Button("Импорт изображения", systemImage: "photo.badge.plus") { importImage = true }
                        Button("Поделиться PNG", systemImage: "square.and.arrow.up") {
                            shareItem = ShareItem(items: [PageRenderer.image(session.page, maxDimension: 2400)])
                        }
                        Button("Вписать страницу", systemImage: "arrow.up.left.and.arrow.down.right") { session.fitRequest = UUID() }
                        Toggle("Зеркальный вид", isOn: $session.mirror)
                        Button("Настройки рисования", systemImage: "slider.horizontal.3") { showSettings = true }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Действия страницы")
                }
            }
            .sheet(isPresented: $showLayers) { LayerPanel(session: session) }
            .sheet(isPresented: $showSettings) { drawingSettings }
            .sheet(item: $shareItem) { ShareSheet(items: $0.items) }
            .fileImporter(isPresented: $importImage, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= NotebookCodec.maximumBytes else { throw DocumentError.tooLarge }
                    guard let image = UIImage(data: try Data(contentsOf: url)) else { throw DocumentError.invalidDocument }
                    try session.insertImage(image)
                } catch { localError = error.localizedDescription }
            }
            .alert("Не удалось выполнить действие", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("Понятно") { localError = nil }
            } message: { Text(localError ?? "") }
        }
    }

    private var tools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    Button {
                        session.tool = tool
                        if tool != .select { session.selection = [] }
                    } label: {
                        Label(tool.title, systemImage: tool.symbol)
                            .labelStyle(.iconOnly).frame(width: 44, height: 40)
                            .background(session.tool == tool ? Color.teal.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }.tint(session.tool == tool ? .teal : .primary)
                        .accessibilityLabel(tool.title).accessibilityAddTraits(session.tool == tool ? .isSelected : [])
                }
                Divider().frame(height: 28)
                ColorPicker("Цвет", selection: $session.color, supportsOpacity: true).labelsHidden().accessibilityLabel("Цвет штриха")
                Slider(value: $session.width, in: 1...100).frame(width: 120).accessibilityLabel("Толщина штриха")
                Text("\(Int(session.width))").monospacedDigit().frame(width: 30)
                Button { session.straightLine.toggle() } label: { Image(systemName: "line.diagonal").frame(width: 44, height: 40) }
                    .tint(session.straightLine ? .teal : .primary).accessibilityLabel("Прямые линии")
            }
        }
    }

    private var selectionTools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                Text(session.selection.isEmpty ? "Обведи объекты на активном слое" : "Выбрано: \(session.selection.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Копировать") { session.copySelection() }.disabled(session.selection.isEmpty)
                Button("Вставить") { session.pasteSelection() }.disabled(session.selectionClipboard.isEmpty)
                Button { session.transformSelection(scale: 0.9) } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(session.selection.isEmpty).accessibilityLabel("Уменьшить выделенное")
                Button { session.transformSelection(scale: 1.1) } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(session.selection.isEmpty).accessibilityLabel("Увеличить выделенное")
                Button { session.transformSelection(rotation: -.pi / 12) } label: { Image(systemName: "rotate.left") }
                    .disabled(session.selection.isEmpty).accessibilityLabel("Повернуть влево")
                Button { session.transformSelection(rotation: .pi / 12) } label: { Image(systemName: "rotate.right") }
                    .disabled(session.selection.isEmpty).accessibilityLabel("Повернуть вправо")
                Button(role: .destructive) { session.deleteSelection() } label: { Image(systemName: "trash") }
                    .disabled(session.selection.isEmpty).accessibilityLabel("Удалить выделенное")
            }.buttonStyle(.borderless).frame(minHeight: 44)
        }
    }

    private var drawingSettings: some View {
        NavigationStack {
            Form {
                Section("Ввод") {
                    Toggle("Только Apple Pencil", isOn: $session.pencilOnly)
                    Toggle("Палец работает ластиком", isOn: $session.fingerEraser).disabled(session.pencilOnly)
                    Toggle("Толщина без учёта нажима", isOn: $session.fixedWidth)
                    Toggle("Прямые линии", isOn: $session.straightLine)
                }
                Section("Соседние страницы") {
                    Stepper("Предыдущих: \(session.onionBefore)", value: $session.onionBefore, in: 0...3)
                    Stepper("Следующих: \(session.onionAfter)", value: $session.onionAfter, in: 0...3)
                }
                Section { Text("Для обычных ёмкостных стилусов оставь режим «Только Apple Pencil» выключенным. Нажим учитывается, только если устройство передаёт его.").font(.footnote) }
            }.navigationTitle("Рисование")
                .toolbar { Button("Готово") { showSettings = false } }
        }.presentationDetents([.medium, .large])
    }
}

struct LayerPanel: View {
    @ObservedObject var session: EditorSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(session.page.layers.enumerated()).reversed(), id: \.element.id) { index, layer in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button {
                                session.activeLayerID = layer.id; session.selection = []
                            } label: {
                                Label(layer.name, systemImage: session.activeLayerID == layer.id ? "checkmark.circle.fill" : "circle")
                            }.buttonStyle(.borderless)
                            Spacer()
                            Button {
                                session.edit { $0.layers[index].isVisible.toggle() }
                            } label: { Image(systemName: layer.isVisible ? "eye" : "eye.slash") }
                                .buttonStyle(.borderless).accessibilityLabel(layer.isVisible ? "Скрыть слой" : "Показать слой")
                            Menu {
                                Button("Выше") { session.edit { $0.layers.swapAt(index, index + 1) } }.disabled(index == session.page.layers.count - 1)
                                Button("Ниже") { session.edit { $0.layers.swapAt(index, index - 1) } }.disabled(index == 0)
                                Button("Дублировать") {
                                    let copy = layer.duplicated(); session.edit { $0.layers.insert(copy, at: index + 1) }
                                }
                                Button("Удалить", role: .destructive) {
                                    session.edit { $0.layers.remove(at: index) }
                                    session.activeLayerID = session.page.layers[0].id; session.selection = []
                                }.disabled(session.page.layers.count == 1)
                            } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Действия слоя")
                        }
                        HStack {
                            Text("Непрозрачность").font(.caption)
                            Slider(value: Binding(get: { session.page.layers.first(where: { $0.id == layer.id })?.opacity ?? 1 },
                                set: { value in session.edit { $0.layers[index].opacity = value } }), in: 0...1)
                            Text("\(Int(layer.opacity * 100))%").font(.caption).monospacedDigit()
                        }
                    }.padding(.vertical, 6)
                }
                Button("Добавить слой", systemImage: "plus") { session.addLayer() }.accessibilityIdentifier("addLayer")
                Button("Копировать активный слой") { session.copyLayer() }
                Button("Вставить слой") { session.pasteLayer() }.disabled(session.layerClipboard == nil)
            }.navigationTitle("Слои")
                .toolbar { Button("Готово") { dismiss() } }
        }.presentationDetents([.medium, .large])
    }
}

struct ShareItem: Identifiable { let id = UUID(); let items: [Any] }
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
