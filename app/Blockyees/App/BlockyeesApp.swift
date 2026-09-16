import SwiftUI

@main
struct BlockyeesApp: App {
    @StateObject private var store = NotebookStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .tint(.teal)
                .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
                .task { await store.load() }
                .alert("Не удалось выполнить действие", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button("Понятно") { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "") }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.synchronize() } }
                    if phase == .background { Task { await store.flush() } }
                }
        }
    }
}
