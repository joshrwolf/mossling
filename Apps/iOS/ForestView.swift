import SwiftUI
import MosslingCore
import MosslingApplication

struct ForestView: View {
    var isSelected: Bool
    @Environment(MosslingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingSession = false
    @State private var showingDetails = false
    @State private var showingBuilder = false
    @State private var celebrating = false

    private var snapshot: ForestSnapshot {
        ForestSnapshot(progress: store.progress, affinity: store.configuration.companionAffinity, world: store.configuration.world)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                forest
                    .overlay(alignment: .top) { if !typeSize.isAccessibilitySize { forestHeader } }
                    .frame(maxHeight: typeSize.isAccessibilitySize ? 220 : .infinity)
                if typeSize.isAccessibilitySize {
                    ScrollView {
                        VStack(spacing: 0) {
                            forestHeader
                            snackDock
                        }
                    }
                } else {
                    snackDock
                }
            }
            .background(MossPalette.ink)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSession) { SnackSessionView().preferredColorScheme(.dark) }
            .sheet(isPresented: $showingBuilder) { ForestBuilderView().preferredColorScheme(.dark) }
            .sheet(isPresented: $showingDetails) { ForestDetailsView().preferredColorScheme(.light) }
            .sensoryFeedback(.success, trigger: store.celebrationID)
            .onChange(of: store.celebrationID) { _, _ in celebrating = true }
            .onChange(of: store.navigationRequest) { _, _ in showingSession = false; showingDetails = false; showingBuilder = false }
            .task(id: isSelected) {
                guard isSelected else { return }
                while !Task.isCancelled {
                    if scenePhase == .active { store.refresh() }
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                }
            }
        }
    }

    private var forest: some View {
        ForestCanvas(snapshot: snapshot, active: isSelected && !showingSession && !showingDetails && !showingBuilder)
            .frame(maxWidth: .infinity)
            .clipped()
    }

    private var forestHeader: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top))
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.configuration.companionName).font(.system(.title, design: .rounded, weight: .bold))
                Text(store.progress.stage.title).font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("companionStage")
            }
            if !typeSize.isAccessibilitySize { Spacer() }
            Button { showingDetails = true } label: {
                HStack(spacing: 6) {
                    if !typeSize.isAccessibilitySize { Image(systemName: "leaf.fill") }
                    Text("\(store.progress.growth) growth")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(MossPalette.ink.opacity(0.9), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("forestDetails")
            .accessibilityLabel("\(store.progress.growth) growth")
            .accessibilityHint("Show growth, discoveries, and forest appearance")
        }
        .foregroundStyle(MossPalette.cream)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [MossPalette.ink.opacity(0.9), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var snackDock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Build forest", systemImage: "square.grid.3x3") { showingBuilder = true }
                .font(.subheadline.weight(.semibold)).accessibilityIdentifier("buildForest")
            if store.progress.growth >= ForestRegion.grove.requiredGrowth && !store.configuration.world.regions.contains(.grove) {
                Text("Upper grove ready to open").font(.caption).foregroundStyle(MossPalette.mint)
            }
            if celebrating {
                HStack {
                    Label("+\(ProgressionCatalog.growthPerSnack) growth", systemImage: "leaf.fill")
                        .foregroundStyle(MossPalette.mint)
                    Spacer()
                    Button("Done") { celebrating = false }
                }.font(.subheadline.weight(.semibold))
            }
            if let session = store.session {
                HStack {
                    activityLabel(session.activity)
                    Spacer()
                    dockButton("Continue snack", id: "resumeSnack") { showingSession = true }
                }
            } else if store.isPausedToday {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paused for today").font(.headline).accessibilityIdentifier("pausedDayState")
                        Text("Your schedule resumes tomorrow.").font(.caption)
                    }
                    Spacer()
                    dockButton("Resume", id: "resumeToday") { Task { await store.resumeToday() } }
                }
            } else if let opportunity = store.currentOpportunity {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        activityLabel(opportunity.activity)
                        Spacer(minLength: 0)
                        dockButton("Start snack", id: "startSnack") { begin(opportunity.activity) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        activityLabel(opportunity.activity)
                        dockButton("Start snack", id: "startSnack") { begin(opportunity.activity) }
                    }
                }
                HStack {
                    Menu("Choose another") {
                        ForEach(store.configuration.activities.filter(\.isEnabled)) { activity in
                            Button(activity.title + " · " + activity.targetSummary) { begin(activity) }
                        }
                    }
                    Spacer()
                    Menu("Snack options") {
                        Button("Snooze 10 minutes") { Task { await store.snooze() } }
                        Button("Skip snack") { Task { await store.skipCurrentSnack() } }.accessibilityIdentifier("skipSnack")
                        Button("Pause for today") { Task { await store.pauseToday() } }.accessibilityIdentifier("pauseToday")
                    }
                }.font(.subheadline.weight(.medium)).foregroundStyle(MossPalette.mint)
            } else {
                Text(store.isCurrentCompleted ? "Snack complete" : store.isCurrentSkipped ? "Snack skipped" : "No snack scheduled now")
                    .font(.headline)
                    .accessibilityIdentifier(store.isCurrentCompleted ? "completedSnackState" : store.isCurrentSkipped ? "skippedSnackState" : "restingSnackState")
                if let next = store.nextOpportunity {
                    Text("Next snack: \(next.scheduledAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())).")
                        .font(.subheadline).foregroundStyle(MossPalette.mint)
                } else {
                    Text("Set your snack schedule in Rhythm.").font(.subheadline)
                }
            }
            if let status = store.status {
                Text(status).font(.caption).foregroundStyle(MossPalette.mint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .foregroundStyle(MossPalette.cream)
        .tint(MossPalette.cream)
        .background(MossPalette.ink)
    }

    private func activityLabel(_ activity: ActivityDefinition) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(activity.title).font(.headline)
            Text(activity.targetSummary).font(.subheadline).foregroundStyle(MossPalette.mint)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func dockButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.bold))
                .padding(.horizontal, 18).padding(.vertical, 14)
                .foregroundStyle(MossPalette.ink)
                .background(MossPalette.cream, in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func begin(_ activity: ActivityDefinition) {
        if store.start(activity: activity) { showingSession = true }
    }
}
