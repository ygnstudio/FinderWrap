import SwiftUI
@main
struct FinderWrapApp: App {
    @StateObject private var state = AppState()
    @State private var menuInserted = true

    var body: some Scene {
        MenuBarExtra("FinderWrap", systemImage: "arrow.turn.down.right", isInserted: $menuInserted) {
            MenuBarView(state: state)
        }
        .menuBarExtraStyle(.window)
        #if DEBUG
        Window("FinderWrap · 界面验收", id: "preview") {
            MenuBarView(state: state)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(ProcessInfo.processInfo.arguments.contains("--preview-panel") ? .presented : .suppressed)
        #endif
    }
}
