import SwiftUI

@main
struct MosslingWatchApp: App {
    @State private var store = MosslingStore.live(role: .watch)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchForestView()
                .environment(store)
                .tint(MossPalette.mint)
                .task { await store.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refresh()
                        Task { await store.bootstrap() }
                    }
                }
        }
    }
}
