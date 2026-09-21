import SwiftUI
import MosslingApplication
import MosslingCore

struct MosslingRootView: View {
    @Environment(MosslingStore.self) private var store
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingWelcome = false
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if store.isReady {
                TabView(selection: $selectedTab) {
                    ForestView(isSelected: selectedTab == 0 && !showingWelcome)
                        .tabItem { Label("Forest", systemImage: "leaf") }.tag(0)
                    ActivitiesView()
                        .tabItem { Label("Snacks", systemImage: "figure.flexibility") }.tag(1)
                    RhythmView()
                        .tabItem { Label("Rhythm", systemImage: "sun.max") }.tag(2)
                    JournalView()
                        .tabItem { Label("Journal", systemImage: "book.closed") }.tag(3)
                }
            } else {
                ContentUnavailableView {
                    Label("Couldn’t open saved progress", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.error ?? "We couldn’t open your saved forest. Your existing data has been preserved. Close and reopen Mossling to try again.")
                } actions: {
                    Text("Close and reopen Mossling after resolving the storage issue. No progress has been replaced.")
                        .font(.footnote).multilineTextAlignment(.center)
                }.background(MossPalette.cream)
            }
        }
        .preferredColorScheme(selectedTab == 0 || selectedTab == 1 ? .dark : .light)
        .onAppear { showingWelcome = store.isReady && !hasSeenWelcome }
        .onChange(of: store.navigationRequest) { _, _ in
            showingWelcome = false
            selectedTab = 0
        }
        .sheet(isPresented: $showingWelcome, onDismiss: { hasSeenWelcome = true }) {
            WelcomeView { hasSeenWelcome = true; showingWelcome = false }.preferredColorScheme(.light)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.isReady && store.error != nil },
            set: { if !$0 { store.clearError() } }
        )) {
            Button("OK") { store.clearError() }
        } message: { Text(store.error ?? "Please try again.") }
    }
}

struct MossPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16).padding(.horizontal, 18)
            .foregroundStyle(Color.white)
            .background(MossPalette.moss.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.40), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

extension View {
    func mossCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24))
    }
}
