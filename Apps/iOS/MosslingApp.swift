import SwiftUI

@main
struct MosslingApp: App {
    @State private var store = MosslingStore.live(role: .phone)
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MosslingRootView()
                .environment(store)
                .tint(MossPalette.moss)
                .preferredColorScheme(.light)
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
