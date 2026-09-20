import SwiftUI
import MosslingApplication
import MosslingCore

struct SnackSessionView: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var finishing = false
    @State private var confirmCancel = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let session = store.session {
                    VStack(spacing: 26) {
                        MosslingCharacter(mood: .curious)
                            .frame(width: 170, height: 160)
                            .accessibilityHidden(true)
                        Text(session.activity.title)
                            .font(.system(.largeTitle, design: .serif, weight: .medium))
                            .multilineTextAlignment(.center)
                        Text(session.activity.instructions)
                            .font(.body).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if let error = store.error {
                            Text(error).font(.subheadline).foregroundStyle(Color.red)
                        }

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let elapsed = session.elapsed(at: store.currentDate)
                            let remaining = max(0, Double(session.activity.targetValue) - elapsed)
                            let isTimed = session.activity.targetKind == .duration
                            let expired = store.currentDate >= session.completionDeadline
                            VStack(spacing: 22) {
                                if isTimed {
                                    Text(timerText(remaining))
                                        .font(.system(size: 62, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .minimumScaleFactor(0.5).lineLimit(1)
                                        .accessibilityLabel("\(Int(ceil(remaining))) seconds remaining")
                                    ProgressView(value: min(elapsed / Double(session.activity.targetValue), 1))
                                        .tint(MossPalette.fern).accessibilityHidden(true)
                                    Text(remaining == 0 ? "Timer finished. Ready to finish your snack?" : session.runningSince == nil ? "Timer paused" : "Timer running")
                                        .font(.subheadline).foregroundStyle(MossPalette.moss)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("\(session.activity.targetValue)")
                                        .font(.system(size: 62, weight: .medium, design: .rounded))
                                    Text("repetitions")
                                        .font(.subheadline).foregroundStyle(MossPalette.moss)
                                }

                                if expired {
                                    Text("This snack has expired.")
                                        .font(.subheadline).multilineTextAlignment(.center)
                                    Button("Return to forest") { store.cancelSession(); dismiss() }
                                        .buttonStyle(MossPrimaryButtonStyle())
                                } else {
                                    Button {
                                        finishing = true
                                        Task {
                                            let completed = await store.complete()
                                            finishing = false
                                            if completed {
                                                AppDiagnostics.event("completionViewDismiss")
                                                dismiss()
                                            }
                                        }
                                    } label: {
                                        Label(finishing ? "Saving…" : "Finish snack", systemImage: "checkmark")
                                    }
                                    .buttonStyle(MossPrimaryButtonStyle())
                                    .disabled(finishing || (isTimed && remaining > 0))
                                    .accessibilityIdentifier("completeSnack")
                                    if isTimed && remaining > 0 {
                                        Button(session.runningSince == nil ? "Resume timer" : "Pause timer") {
                                            if session.runningSince == nil { store.resume() } else { store.pause() }
                                        }.font(.headline).padding(.vertical, 8)
                                    }
                                }
                            }
                        }
                        Text("Move within a comfortable range. Use End to stop this activity.")
                            .font(.footnote).foregroundStyle(MossPalette.moss)
                            .multilineTextAlignment(.center)
                    }.padding(26)
                } else {
                    ContentUnavailableView("No snack in progress", systemImage: "leaf")
                }
            }
            .background(MossPalette.cream).foregroundStyle(MossPalette.ink)
            .navigationTitle("Your snack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End", role: .destructive) { confirmCancel = true }
                }
            }
            .confirmationDialog("End this snack?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("End snack", role: .destructive) { store.cancelSession(); dismiss() }
                Button("Keep going", role: .cancel) { }
            } message: { Text("You can choose another activity while this snack is available.") }
            .onChange(of: store.navigationRequest) { _, _ in dismiss() }
        }
    }

    private func timerText(_ seconds: TimeInterval) -> String {
        let count = Int(ceil(seconds))
        return String(format: "%d:%02d", count / 60, count % 60)
    }
}

struct CharacterPlayground: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mood: MosslingCharacter.Mood = .cozy
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    Text("Meet your Mossling")
                        .font(.system(.largeTitle, design: .serif, weight: .medium))
                        .multilineTextAlignment(.center)
                    ForestHabitat(mood: mood).frame(height: 320).id(mood)
                    VStack(spacing: 12) {
                        ForEach(MosslingCharacter.Mood.allCases, id: \.self) { candidate in
                            Button {
                                mood = candidate
                            } label: {
                                HStack {
                                    Text(candidate.rawValue.capitalized)
                                    Spacer()
                                    if mood == candidate { Image(systemName: "checkmark") }
                                }
                                .font(.headline).padding(18)
                                .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                    Text("Your woodland companion grows with every snack you complete.")
                        .font(.body).multilineTextAlignment(.center).foregroundStyle(MossPalette.moss)
                }.padding(24)
            }
            .background(MossPalette.cream).foregroundStyle(MossPalette.ink)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct WelcomeView: View {
    @Environment(MosslingStore.self) private var store
    var onFinish: () -> Void
    @State private var requesting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForestHabitat().frame(height: 260)
                Text("Movement snacks.\nWoodland magic.")
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
                Text("Fit short exercises into your day and grow your Mossling, one snack at a time.")
                    .font(.title3).foregroundStyle(MossPalette.moss)
                VStack(alignment: .leading, spacing: 18) {
                    Label("Choose your activities.", systemImage: "figure.flexibility")
                    Label("Set your snack schedule.", systemImage: "sun.max")
                    Label("Complete snacks to grow your forest.", systemImage: "leaf")
                }.font(.body)
                Text("Start with weekday reminders, 9 am–5 pm, every hour. You can change everything in Rhythm. Missed snacks never take growth away.")
                    .font(.footnote).foregroundStyle(MossPalette.moss)
                Button {
                    requesting = true
                    Task { await store.requestNotificationPermission(); requesting = false; onFinish() }
                } label: {
                    Text(requesting ? "Enabling…" : "Enable reminders")
                }.buttonStyle(MossPrimaryButtonStyle()).disabled(requesting)
                Button("Explore first") { onFinish() }
                    .frame(maxWidth: .infinity).padding(.bottom, 16)
            }.padding(26)
        }.background(MossPalette.cream).foregroundStyle(MossPalette.ink)
    }
}
