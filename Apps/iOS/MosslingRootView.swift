import SwiftUI
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
                    ForestView()
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
                    Label("Your forest is safe", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.error ?? "We couldn’t open your saved forest. Your existing data has been preserved. Close and reopen Mossling to try again.")
                } actions: {
                    Text("Close and reopen Mossling after resolving the storage issue. No progress has been replaced.")
                        .font(.footnote).multilineTextAlignment(.center)
                }.background(MossPalette.cream)
            }
        }
        .onAppear { showingWelcome = store.isReady && !hasSeenWelcome }
        .onChange(of: store.navigationRequest) { _, _ in
            showingWelcome = false
            selectedTab = 0
        }
        .sheet(isPresented: $showingWelcome, onDismiss: { hasSeenWelcome = true }) {
            WelcomeView { hasSeenWelcome = true; showingWelcome = false }
        }
        .alert("A little snag", isPresented: Binding(
            get: { store.isReady && store.error != nil },
            set: { if !$0 { store.clearError() } }
        )) {
            Button("OK") { store.clearError() }
        } message: { Text(store.error ?? "Please try again.") }
    }
}

struct ForestView: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSession = false
    @State private var showingPlayground = false
    @State private var celebrating = false

    private var stageNumber: Int {
        switch store.progress.stage { case .seedling: 0; case .sprout: 1; case .guardian: 2 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("A LITTLE MOVEMENT. A LITTLE MAGIC.")
                                .font(.caption2.weight(.semibold)).tracking(1.4)
                                .foregroundStyle(MossPalette.moss)
                            Text("Your quiet corner.")
                                .font(.system(.largeTitle, design: .serif, weight: .medium))
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(spacing: 0) {
                        ForestHabitat(mood: celebrating ? .celebrating : (store.currentOpportunity == nil ? .sleeping : .cozy), stage: stageNumber, unlocks: store.progress.forestUnlocks, animate: scenePhase == .active)
                            .frame(height: 270)
                        Text(store.configuration.companionName)
                            .font(.system(.title, design: .rounded, weight: .semibold))
                        Text(store.progress.stage.title + " · growing at your pace")
                            .font(.subheadline).foregroundStyle(MossPalette.moss)
                            .padding(.top, 4)
                    }.frame(maxWidth: .infinity)

                    if celebrating {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("A small break. A little more forest.", systemImage: "sparkles")
                                .font(.headline)
                            Text("Your movement earned 10 growth. \(store.configuration.companionName) is very pleased.")
                                .font(.subheadline)
                            Button("Lovely") { celebrating = false }.font(.subheadline.weight(.semibold))
                        }.mossCard()
                        .accessibilityElement(children: .contain)
                    }

                    opportunityCard
                    if let status = store.status {
                        Label(status, systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(MossPalette.moss)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    growthCard
                    if !store.progress.forestUnlocks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Taking root").font(.system(.title3, design: .serif, weight: .medium))
                            ForEach(store.progress.forestUnlocks, id: \.self) { unlock in
                                Label(unlock.title, systemImage: unlockIcon(unlock))
                                    .font(.subheadline)
                            }
                        }.mossCard()
                    }
                    Text("No streaks to lose. Every little break counts.")
                        .font(.footnote).foregroundStyle(MossPalette.moss)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                        .padding(.bottom, 12)
                }.padding(22)
            }
            .background(MossPalette.cream)
            .foregroundStyle(MossPalette.ink)
            .navigationTitle("Mossling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingPlayground = true } label: { Image(systemName: "sparkles") }
                        .accessibilityLabel("Meet your Mossling")
                }
            }
            .sheet(isPresented: $showingSession) { SnackSessionView() }
            .sheet(isPresented: $showingPlayground) { CharacterPlayground() }
            .onChange(of: store.celebrationID) { _, _ in celebrating = true }
            .onChange(of: store.navigationRequest) { _, _ in showingSession = false; showingPlayground = false }
            .task {
                while !Task.isCancelled {
                    if scenePhase == .active { store.refresh() }
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                }
            }
        }
    }

    @ViewBuilder private var opportunityCard: some View {
        if let session = store.session {
            VStack(alignment: .leading, spacing: 12) {
                Label("Your snack is waiting", systemImage: "pause.circle")
                    .font(.caption.weight(.semibold)).foregroundStyle(MossPalette.moss)
                Text(session.activity.title).font(.title2.weight(.semibold))
                Text("Pick up where you left off.").font(.subheadline)
                Button("Return to snack") { showingSession = true }
                    .buttonStyle(MossPrimaryButtonStyle())
                    .accessibilityIdentifier("resumeSnack")
            }.mossCard()
        } else if store.isPausedToday {
            VStack(alignment: .leading, spacing: 12) {
                Label("Resting for today", systemImage: "moon.zzz").font(.headline)
                Text("Your usual rhythm returns tomorrow. Everything you’ve grown stays yours.")
                Button("Resume today") { Task { await store.resumeToday() } }
                    .buttonStyle(MossPrimaryButtonStyle()).accessibilityIdentifier("resumeToday")
            }.mossCard().accessibilityIdentifier("pausedDayState")
        } else if let opportunity = store.currentOpportunity {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("A moment for you", systemImage: "sun.max")
                        .font(.caption.weight(.semibold)).foregroundStyle(MossPalette.moss)
                    Spacer()
                    Text("+10 growth").font(.caption.weight(.semibold)).foregroundStyle(MossPalette.moss)
                }
                Text(opportunity.activity.title).font(.title2.weight(.semibold))
                Text(opportunity.activity.targetSummary + " · " + opportunity.activity.instructions)
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text("This break is available until \(opportunity.expiresAt.formatted(date: .omitted, time: .shortened)).")
                    .font(.caption).foregroundStyle(MossPalette.moss)
                Button { begin(opportunity.activity) } label: {
                    Label("Take a little break", systemImage: "play.fill")
                }.buttonStyle(MossPrimaryButtonStyle())
                    .accessibilityIdentifier("startSnack")
                HStack {
                    Menu("Choose another") {
                        ForEach(store.configuration.activities.filter(\.isEnabled)) { activity in
                            Button(activity.title + " · " + activity.targetSummary) { begin(activity) }
                        }
                    }
                    Spacer()
                    Button("In 10 minutes") { Task { await store.snooze() } }
                }.font(.subheadline).tint(MossPalette.moss)
                Button("Skip this break") { Task { await store.skipCurrentSnack() } }
                    .font(.subheadline).tint(MossPalette.moss).accessibilityIdentifier("skipSnack")
                Button("Pause for today") { Task { await store.pauseToday() } }
                    .font(.subheadline).tint(MossPalette.moss).accessibilityIdentifier("pauseToday")
            }.mossCard()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Room to breathe", systemImage: "moon.stars")
                    .font(.caption.weight(.semibold)).foregroundStyle(MossPalette.moss)
                Text(store.isCurrentCompleted ? "A little movement, safely saved." : store.isCurrentSkipped ? "This break is yours to skip." : "Nothing to catch up on.")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier(store.isCurrentCompleted ? "completedSnackState" : store.isCurrentSkipped ? "skippedSnackState" : "restingSnackState")
                if let next = store.nextOpportunity {
                    Text("Your next little break is \(next.scheduledAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())). Until then, enjoy your day.")
                        .font(.subheadline)
                } else {
                    Text("Set your active days and hours in Rhythm. Your forest will be here when you’re ready.")
                        .font(.subheadline)
                }
            }.mossCard()
        }
    }

    private var growthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Little by little").font(.system(.title3, design: .serif, weight: .medium))
                Spacer()
                Text("\(store.progress.growth) growth").font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("earnedGrowthValue")
            }
            ProgressView(value: store.progress.stageProgress).tint(MossPalette.fern)
                .accessibilityLabel("Progress to the next growth stage")
            if let target = store.progress.nextStageGrowth {
                Text("\(max(0, (target - store.progress.growth + 9) / 10)) more little breaks until the next chapter.")
                    .font(.footnote).foregroundStyle(MossPalette.moss)
            } else {
                Text("A forest guardian. Your story keeps growing with every break.")
                    .font(.footnote).foregroundStyle(MossPalette.moss)
            }
            Text("\(store.progress.completedSnackCount) movement breaks, all yours.")
                .font(.caption).foregroundStyle(MossPalette.moss)
        }.mossCard()
    }

    private func begin(_ activity: ActivityDefinition) {
        if store.start(activity: activity) { showingSession = true }
    }
    private func unlockIcon(_ unlock: ForestUnlock) -> String {
        switch unlock { case .fern: "leaf"; case .mushrooms: "sparkles"; case .pond: "water.waves" }
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
