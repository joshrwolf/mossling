import SwiftUI
import MosslingApplication

@main
struct MosslingApp: App {
    @State private var store = MosslingStore.live(role: .phone)
    @Environment(\.scenePhase) private var scenePhase
    private let preferences: UserDefaults

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let suite = (Bundle.main.bundleIdentifier ?? "Mossling") + ".ui-testing"
            guard let testPreferences = UserDefaults(suiteName: suite) else {
                preconditionFailure("Could not create the isolated UI test preferences")
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") {
                testPreferences.removePersistentDomain(forName: suite)
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-skip-welcome") {
                    testPreferences.set(true, forKey: "hasSeenWelcome")
                }
            }
            preferences = testPreferences
        } else {
            preferences = .standard
        }
        #else
        preferences = .standard
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MosslingRootView()
                .defaultAppStorage(preferences)
                .environment(store)
                .tint(MossPalette.moss)
                .transformEnvironment(\.dynamicTypeSize) { value in
                    #if DEBUG && targetEnvironment(simulator)
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
                       ProcessInfo.processInfo.arguments.contains("--ui-testing-accessibility-size") { value = .accessibility5 }
                    #endif
                }
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
