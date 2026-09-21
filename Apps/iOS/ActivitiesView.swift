import SwiftUI
import MosslingApplication
import MosslingCore

struct ActivitiesView: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing: ActivityDefinition?
    @State private var adding = false
    @State private var changingRotation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Your rotation").font(.title2.weight(.bold))
                        Spacer()
                        Text("\(store.configuration.activities.filter(\.isEnabled).count) active")
                            .font(.subheadline).foregroundStyle(MossPalette.mint)
                    }
                    Text("Pick the activities that come up in your snacks.")
                        .font(.subheadline).foregroundStyle(MossPalette.mint)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                             count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(store.configuration.activities) { activity in card(activity) }
                    }
                    Button { adding = true } label: {
                        Label("Create activity", systemImage: "plus")
                            .font(.headline).frame(maxWidth: .infinity).padding(16)
                            .background(MossPalette.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    }.accessibilityIdentifier("createActivity")
                    Text("Keep at least one activity in your rotation.")
                        .font(.footnote).foregroundStyle(MossPalette.mint)
                }.padding(20)
            }
            .background(MossPalette.ink).foregroundStyle(MossPalette.cream)
            .navigationTitle("Snacks")
            .sheet(item: $editing) { ActivityEditor(activity: $0) }
            .sheet(isPresented: $adding) { ActivityEditor(activity: nil) }
            .onChange(of: store.navigationRequest) { _, _ in editing = nil; adding = false }
        }.tint(MossPalette.mint)
    }

    private func card(_ activity: ActivityDefinition) -> some View {
        VStack(spacing: 0) {
            Button { editing = activity } label: {
                VStack(spacing: 6) {
                    ActivityIllustration(activity: activity)
                        .frame(height: typeSize.isAccessibilitySize ? 110 : 88)
                        .frame(maxWidth: .infinity)
                        .background(RadialGradient(colors: [MossPalette.mint.opacity(0.16), .clear],
                                                   center: .center, startRadius: 8, endRadius: 85))
                    Text(activity.title).font(.subheadline.weight(.bold))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: typeSize.isAccessibilitySize ? 0 : 36)
                    Text(activity.targetSummary).font(.caption.weight(.semibold)).foregroundStyle(MossPalette.mint)
                }.padding(12).frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(activity.title), \(activity.targetSummary)")
            .accessibilityHint("Change the target, instructions or remove this activity")
            Divider().overlay(MossPalette.mint.opacity(0.16)).padding(.horizontal, 12)
            Toggle("In rotation", isOn: Binding(get: { activity.isEnabled }, set: { include(activity, enabled: $0) }))
                .font(.caption.weight(.medium)).tint(MossPalette.fern)
                .accessibilityLabel("Include \(activity.title)")
                .disabled(changingRotation)
                .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(MossPalette.mint.opacity(activity.isEnabled ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MossPalette.mint.opacity(0.16)))
    }

    private func include(_ activity: ActivityDefinition, enabled: Bool) {
        var config = store.configuration
        guard let index = config.activities.firstIndex(where: { $0.id == activity.id }) else { return }
        config.activities[index].isEnabled = enabled
        changingRotation = true
        Task { _ = await store.saveConfig(config); changingRotation = false }
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
    @State private var confirmDelete = false

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
                Section("Activity") {
                    TextField("Activity name", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("activityTitle")
                    TextField("Instructions", text: $instructions, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("activityInstructions")
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
                    Text("Every completed snack earns the same growth, regardless of duration or repetitions.")
                }
                if activity != nil {
                    Section {
                        Button("Delete activity", role: .destructive) { confirmDelete = true }
                            .disabled(saving).accessibilityIdentifier("deleteActivity")
                    }
                }
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(Color.red).font(.subheadline) }
                }
            }
            .scrollContentBackground(.hidden).background(MossPalette.ink).foregroundStyle(MossPalette.cream)
            .navigationTitle(activity == nil ? "Create activity" : "Edit activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.disabled(saving)
                        .accessibilityIdentifier("saveActivity")
                }
            }
            .confirmationDialog("Delete this activity?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete activity", role: .destructive) { delete() }
            } message: { Text("Completed snacks stay in your journal.") }
            .onChange(of: kind) { _, kind in target = kind == .duration ? 120 : 10 }
        }.tint(MossPalette.mint)
    }

    private func delete() {
        guard let activity else { return }
        var config = store.configuration
        config.activities.removeAll { $0.id == activity.id }
        saving = true
        Task {
            let saved = await store.saveConfig(config)
            saving = false
            if saved { dismiss() } else { validationMessage = store.error }
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80 else {
            validationMessage = "Choose an activity name between 1 and 80 characters."; return
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
