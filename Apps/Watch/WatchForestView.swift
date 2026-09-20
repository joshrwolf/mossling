import SwiftUI
import MosslingApplication
import MosslingCore
import WatchKit

struct WatchForestView: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var showingSession = false
    @State private var showingActivities = false
    @State private var celebrating = false

    private var stageNumber: Int { store.progress.stage.visualLevel }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !store.isReady {
                    VStack(spacing: 14) {
                        Image(systemName: "externaldrive.badge.exclamationmark").font(.title)
                        Text("Couldn’t open saved progress").font(.headline)
                        Text(store.error ?? "Your saved forest could not be opened. No data has been replaced.")
                            .font(.caption)
                        Text("Close and reopen Mossling to try again.").font(.caption)
                    }.multilineTextAlignment(.center)
                } else {
                VStack(spacing: 12) {
                    MosslingCharacter(mood: celebrating ? .celebrating : .cozy, stage: stageNumber, affinity: store.configuration.companionAffinity, animate: scenePhase == .active && !isLuminanceReduced)
                        .frame(height: 116)
                    Text(store.configuration.companionName)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    if celebrating {
                        Text("Snack complete\n+\(ProgressionCatalog.growthPerSnack) growth")
                            .font(.headline).multilineTextAlignment(.center).foregroundStyle(MossPalette.mint)
                        ForEach(store.celebrationMilestones) { milestone in
                            Label(milestone.title, systemImage: milestone.symbolName)
                                .font(.caption).multilineTextAlignment(.center)
                        }
                        Button("Done") { celebrating = false }
                    } else if let session = store.session {
                        Text(session.activity.title).font(.headline).multilineTextAlignment(.center)
                        Button("Continue snack") { showingSession = true }
                            .buttonStyle(.borderedProminent)
                    } else if store.isPausedToday {
                        Text("Paused for today").font(.headline)
                        Text("Your schedule resumes tomorrow. Resume today on your iPhone.")
                            .font(.caption).multilineTextAlignment(.center)
                    } else if let opportunity = store.currentOpportunity {
                        Text(opportunity.activity.title).font(.headline).multilineTextAlignment(.center)
                        Text(opportunity.activity.targetSummary).font(.caption).foregroundStyle(MossPalette.mint)
                        Button("Start snack") { begin(opportunity.activity) }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("watchStartSnack")
                        Button("Choose another") { showingActivities = true }.font(.caption)
                    } else {
                        Text("No snack available now").font(.headline)
                        if let next = store.nextOpportunity {
                            Text("Next snack\n\(next.scheduledAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                                .font(.caption).multilineTextAlignment(.center).foregroundStyle(MossPalette.mint)
                        }
                    }
                    Divider().padding(.vertical, 4)
                    Text("\(store.progress.completedSnackCount) \(store.progress.completedSnackCount == 1 ? "snack" : "snacks") · \(store.progress.growth) growth")
                        .font(.caption2).foregroundStyle(MossPalette.mint)
                        .multilineTextAlignment(.center)
                    if let milestone = store.progress.nextMilestone {
                        Text("Next: " + milestone.title).font(.caption2)
                            .foregroundStyle(MossPalette.mint).multilineTextAlignment(.center)
                    }
                    if let status = store.status {
                        Text(status).font(.caption2).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }.padding(.horizontal, 6).padding(.bottom, 12)
                }
            }
            .navigationTitle("Mossling")
            .sheet(isPresented: $showingSession) { WatchSnackSessionView() }
            .sheet(isPresented: $showingActivities, onDismiss: {
                if store.session != nil { showingSession = true }
            }) {
                List(store.configuration.activities.filter(\.isEnabled)) { activity in
                    Button {
                        if store.start(activity: activity) { showingActivities = false }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(activity.title).font(.headline)
                            Text(activity.targetSummary).font(.caption).foregroundStyle(MossPalette.mint)
                        }
                    }
                }.navigationTitle("Choose an activity")
            }
            .onChange(of: store.celebrationID) { _, _ in
                celebrating = true
                WKInterfaceDevice.current().play(.success)
            }
            .alert("Something went wrong", isPresented: Binding(get: { store.isReady && store.error != nil }, set: { if !$0 { store.clearError() } })) {
                Button("OK") { store.clearError() }
            } message: { Text(store.error ?? "Please try again.") }
            .task {
                while !Task.isCancelled {
                    if scenePhase == .active { store.refresh() }
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                }
            }
        }
    }

    private func begin(_ activity: ActivityDefinition) {
        if store.start(activity: activity) { showingSession = true }
    }
}

struct WatchSnackSessionView: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var finishing = false
    @State private var confirmEnd = false

    var body: some View {
        ScrollView {
            if let session = store.session {
                VStack(spacing: 14) {
                    Text(session.activity.title).font(.headline).multilineTextAlignment(.center)
                    Text(session.activity.instructions).font(.caption).multilineTextAlignment(.center)
                    if let error = store.error { Text(error).font(.caption).foregroundStyle(Color.orange) }
                    TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { context in
                        let isTimed = session.activity.targetKind == .duration
                        let remaining = max(0, Double(session.activity.targetValue) - session.elapsed(at: store.currentDate))
                        let expired = store.currentDate >= session.completionDeadline
                        VStack(spacing: 12) {
                            Text(isTimed ? timerText(remaining) : "\(session.activity.targetValue) reps")
                                .font(.system(.largeTitle, design: .rounded, weight: .medium))
                                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                                .accessibilityLabel(isTimed ? "\(Int(ceil(remaining))) seconds remaining" : "\(session.activity.targetValue) repetitions")
                            if expired {
                                Text("This snack has expired.")
                                    .font(.caption).multilineTextAlignment(.center)
                                Button("Back to forest") { store.cancelSession(); dismiss() }
                            } else {
                                Button(finishing ? "Saving…" : "Finish snack") {
                                    finishing = true
                                    Task {
                                        let saved = await store.complete()
                                        finishing = false
                                        if saved { dismiss() }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(finishing || (isTimed && remaining > 0))
                                .accessibilityIdentifier("watchCompleteSnack")
                                if isTimed && remaining > 0 {
                                    Button(session.runningSince == nil ? "Resume" : "Pause") {
                                        if session.runningSince == nil { store.resume() } else { store.pause() }
                                    }
                                }
                                Button("End snack", role: .destructive) { confirmEnd = true }
                                    .font(.caption)
                            }
                        }
                    }
                }.padding(.horizontal, 4)
            } else {
                Text("No snack in progress").font(.headline)
                Button("Back to forest") { dismiss() }
            }
        }
        .confirmationDialog("End this snack?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End snack", role: .destructive) { store.cancelSession(); dismiss() }
            Button("Keep going", role: .cancel) { }
        }
    }
    private func timerText(_ seconds: TimeInterval) -> String {
        let value = Int(ceil(seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
