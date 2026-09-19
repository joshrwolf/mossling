import SwiftUI
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
                        Text("A SMALL PAUSE, JUST FOR YOU")
                            .font(.caption.weight(.semibold)).tracking(1.3)
                            .foregroundStyle(MossPalette.moss)
                            .padding(.top, 20)
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
                            let elapsed = session.elapsed(at: context.date)
                            let remaining = max(0, Double(session.activity.targetValue) - elapsed)
                            let isTimed = session.activity.targetKind == .duration
                            let expired = context.date >= session.opportunity.expiresAt
                            VStack(spacing: 22) {
                                if isTimed {
                                    Text(timerText(remaining))
                                        .font(.system(size: 62, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .minimumScaleFactor(0.5).lineLimit(1)
                                        .accessibilityLabel("\(Int(ceil(remaining))) seconds remaining")
                                    ProgressView(value: min(elapsed / Double(session.activity.targetValue), 1))
                                        .tint(MossPalette.fern).accessibilityHidden(true)
                                    Text(remaining == 0 ? "All done? Give yourself a little credit." : session.runningSince == nil ? "Paused. Take your time." : "A little movement goes a long way.")
                                        .font(.subheadline).foregroundStyle(MossPalette.moss)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text("\(session.activity.targetValue)")
                                        .font(.system(size: 62, weight: .medium, design: .rounded))
                                    Text("repetitions, at your own pace")
                                        .font(.subheadline).foregroundStyle(MossPalette.moss)
                                }

                                if expired {
                                    Text("This break’s window has ended. Your next break is a fresh start.")
                                        .font(.subheadline).multilineTextAlignment(.center)
                                    Button("Return to forest") { store.cancelSession(); dismiss() }
                                        .buttonStyle(MossPrimaryButtonStyle())
                                } else {
                                    Button {
                                        finishing = true
                                        Task {
                                            let completed = await store.complete()
                                            finishing = false
                                            if completed { dismiss() }
                                        }
                                    } label: {
                                        Label(finishing ? "Growing…" : "I did it", systemImage: "checkmark")
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
                        Text("Move in a way that feels comfortable. You can stop or switch activities anytime.")
                            .font(.footnote).foregroundStyle(MossPalette.moss)
                            .multilineTextAlignment(.center)
                    }.padding(26)
                } else {
                    ContentUnavailableView("A little more forest", systemImage: "leaf", description: Text("Your snack has been saved."))
                }
            }
            .background(MossPalette.cream).foregroundStyle(MossPalette.ink)
            .navigationTitle("Your movement break")
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
            } message: { Text("There’s no penalty. You can choose another activity while this break is available.") }
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
                    Text("Small spirit. Big feelings.")
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
                    Text("Cozy while you work. Quiet while you rest. Delighted by your smallest wins.")
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
                Text("Make room for\na little magic.")
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
                Text("A tiny forest spirit. A few moments of movement. A softer rhythm for your day.")
                    .font(.title3).foregroundStyle(MossPalette.moss)
                VStack(alignment: .leading, spacing: 18) {
                    Label("Choose the breaks that feel good to you.", systemImage: "figure.flexibility")
                    Label("Set your own days, hours, and rhythm.", systemImage: "sun.max")
                    Label("Grow a little forest, one break at a time.", systemImage: "leaf")
                }.font(.body)
                Text("Start with weekday reminders, 9 am–5 pm, every hour. You can change everything in Rhythm. Missed breaks never take growth away.")
                    .font(.footnote).foregroundStyle(MossPalette.moss)
                Button {
                    requesting = true
                    Task { await store.requestNotificationPermission(); requesting = false; onFinish() }
                } label: {
                    Text(requesting ? "Just a moment…" : "Enable gentle reminders")
                }.buttonStyle(MossPrimaryButtonStyle()).disabled(requesting)
                Button("Explore first") { onFinish() }
                    .frame(maxWidth: .infinity).padding(.bottom, 16)
            }.padding(26)
        }.background(MossPalette.cream).foregroundStyle(MossPalette.ink)
    }
}
