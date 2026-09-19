import SwiftUI
import MosslingCore

struct ActivitiesView: View {
    @Environment(MosslingStore.self) private var store
    @State private var editing: ActivityDefinition?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Small enough to fit your day. Choose which snacks appear in your rotation, or make one your own.")
                        .font(.body).foregroundStyle(MossPalette.moss)
                        .listRowBackground(Color.clear)
                }
                Section("Your rotation") {
                    ForEach(store.configuration.activities) { activity in
                        HStack(alignment: .center, spacing: 14) {
                            Button { editing = activity } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(activity.title).font(.headline).foregroundStyle(MossPalette.ink)
                                    Text(activity.targetSummary).font(.subheadline).foregroundStyle(MossPalette.moss)
                                    Text(activity.instructions).font(.caption).foregroundStyle(MossPalette.moss)
                                        .lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit \(activity.title), \(activity.targetSummary)")
                            Toggle("Include \(activity.title)", isOn: Binding(
                                get: { activity.isEnabled },
                                set: { value in
                                    var config = store.configuration
                                    if let index = config.activities.firstIndex(where: { $0.id == activity.id }) {
                                        config.activities[index].isEnabled = value
                                        Task { _ = await store.saveConfig(config) }
                                    }
                                }
                            )).labelsHidden().fixedSize()
                        }.padding(.vertical, 7)
                    }.onDelete(perform: delete)
                }
                Section {
                    Button { adding = true } label: { Label("Create a snack", systemImage: "plus.circle") }
                        .accessibilityIdentifier("createActivity")
                } footer: {
                    Text("All snacks earn the same growth. Keep at least one enabled. Repetition snacks use your honest confirmation; timed snacks finish when you confirm after the timer.")
                }
            }
            .scrollContentBackground(.hidden).background(MossPalette.cream)
            .navigationTitle("Your little breaks")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            .sheet(item: $editing) { ActivityEditor(activity: $0) }
            .sheet(isPresented: $adding) { ActivityEditor(activity: nil) }
            .onChange(of: store.navigationRequest) { _, _ in editing = nil; adding = false }
        }
    }

    private func delete(at offsets: IndexSet) {
        var config = store.configuration
        config.activities.remove(atOffsets: offsets)
        Task { _ = await store.saveConfig(config) }
    }
}

struct ActivityEditor: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let activity: ActivityDefinition?
    @State private var title: String
    @State private var instructions: String
    @State private var kind: ActivityTargetKind
    @State private var target: Int
    @State private var enabled: Bool
    @State private var saving = false
    @State private var validationMessage: String?

    init(activity: ActivityDefinition?) {
        self.activity = activity
        _title = State(initialValue: activity?.title ?? "")
        _instructions = State(initialValue: activity?.instructions ?? "")
        _kind = State(initialValue: activity?.targetKind ?? .duration)
        _target = State(initialValue: activity?.targetValue ?? 120)
        _enabled = State(initialValue: activity?.isEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Make it yours") {
                    TextField("Name, like a kitchen dance", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("activityTitle")
                    TextField("A short reminder of what to do", text: $instructions, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Your target") {
                    Picker("Measure by", selection: $kind) {
                        Text("Time").tag(ActivityTargetKind.duration)
                        Text("Repetitions").tag(ActivityTargetKind.repetitions)
                    }.pickerStyle(.segmented)
                    HStack {
                        Text(kind == .duration ? "Seconds" : "Repetitions")
                        Spacer()
                        TextField("Target", value: $target, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            .frame(minWidth: 70, maxWidth: 120)
                            .accessibilityLabel(kind == .duration ? "Duration in seconds" : "Number of repetitions")
                    }
                    if kind == .duration {
                        HStack {
                            ForEach([30, 60, 120, 180], id: \.self) { seconds in
                                Button(seconds < 60 ? "30 sec" : "\(seconds / 60) min") { target = seconds }
                                    .buttonStyle(.bordered).font(.caption)
                            }
                        }
                    }
                }
                Section {
                    Toggle("Include in my rotation", isOn: $enabled)
                } footer: {
                    Text("Choose a comfortable amount. More effort doesn’t earn extra growth—showing up is enough.")
                }
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(Color.red).font(.subheadline) }
                }
            }
            .scrollContentBackground(.hidden).background(MossPalette.cream)
            .navigationTitle(activity == nil ? "Create a snack" : "Edit snack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.disabled(saving)
                        .accessibilityIdentifier("saveActivity")
                }
            }
            .onChange(of: kind) { _, kind in target = kind == .duration ? 120 : 10 }
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80 else {
            validationMessage = "Choose a snack name between 1 and 80 characters."; return
        }
        guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, instructions.count <= 1000 else {
            validationMessage = "Add a short description, up to 1,000 characters."; return
        }
        guard target > 0, target <= (kind == .duration ? 3600 : 1000) else {
            validationMessage = kind == .duration ? "Choose a duration from 1 to 3,600 seconds." : "Choose a target from 1 to 1,000 repetitions."; return
        }
        let value = ActivityDefinition(
            id: activity?.id ?? UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            targetKind: kind, targetValue: target, isEnabled: enabled
        )
        do { try value.validate() } catch { validationMessage = error.localizedDescription; return }
        var config = store.configuration
        if let index = config.activities.firstIndex(where: { $0.id == value.id }) {
            config.activities[index] = value
        } else { config.activities.append(value) }
        saving = true
        Task {
            let saved = await store.saveConfig(config)
            saving = false
            if saved { dismiss() } else { validationMessage = store.error ?? "We couldn’t save that change. Please try again." }
        }
    }
}
