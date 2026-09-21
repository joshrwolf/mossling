import SwiftUI
import MosslingCore
import MosslingApplication

struct ActivityLibrary: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var saving = false
    @State private var failure: String?

    private var results: [ActivityDefinition] {
        ActivityDefinition.catalog.filter {
            query.isEmpty || $0.title.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Add a movement to your rotation. You can edit its target and instructions afterward.")
                        .font(.subheadline).foregroundStyle(MossPalette.mint)
                    if let failure { Text(failure).foregroundStyle(.red) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                             count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(results) { activity in
                            let added = store.configuration.activities.contains { $0.id == activity.id }
                            VStack(spacing: 8) {
                                ActivityIllustration(activity: activity).frame(height: 100)
                                Text(activity.title).font(.subheadline.bold())
                                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                    .frame(minHeight: typeSize.isAccessibilitySize ? 0 : 40)
                                Text(activity.targetSummary).font(.caption).foregroundStyle(MossPalette.mint)
                                Button {
                                    add(activity)
                                } label: {
                                    Label(added ? "Added" : "Add", systemImage: added ? "checkmark" : "plus")
                                        .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered).disabled(added || saving)
                                .accessibilityLabel(added ? "\(activity.title) added" : "Add \(activity.title)")
                                .accessibilityIdentifier("add_\(activity.id)")
                            }
                            .padding(12).frame(maxWidth: .infinity)
                            .background(MossPalette.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    if results.isEmpty { ContentUnavailableView.search(text: query) }
                }.padding(20)
            }
            .background(MossPalette.ink).foregroundStyle(MossPalette.cream)
            .navigationTitle("Activity library").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find a movement")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(MossPalette.mint)
    }

    private func add(_ activity: ActivityDefinition) {
        guard !saving, !store.configuration.activities.contains(where: { $0.id == activity.id }) else { return }
        var configuration = store.configuration
        configuration.activities.append(activity)
        saving = true
        failure = nil
        Task {
            if !(await store.saveConfig(configuration)) { failure = store.error }
            saving = false
        }
    }
}
