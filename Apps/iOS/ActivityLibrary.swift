import SwiftUI
import MosslingCore
import MosslingApplication

struct ActivityLibrary: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var selected: ActivityDefinition?

    private var results: [ActivityFamily] {
        ActivityFamily.allCases.filter { family in
            query.isEmpty || family.title.localizedStandardContains(query)
                || family.variations.contains { $0.title.localizedStandardContains(query) || $0.label.localizedStandardContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Choose a movement, then pick your variation.")
                        .font(.subheadline).foregroundStyle(MossPalette.mint)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                             count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(results) { family in
                            let saved = store.configuration.activities.first { $0.family == family }
                            let activity = store.configuration.activityDraft(for: family)
                            Button { selected = activity } label: {
                                VStack(spacing: 8) {
                                    ActivityIllustration(activity: activity).frame(height: 100)
                                    Text(family.title).font(.subheadline.bold())
                                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                    Text("\(family.variations.count) variations").font(.caption).foregroundStyle(MossPalette.mint)
                                    Label(saved == nil ? "Choose" : "In rotation", systemImage: saved == nil ? "plus.circle" : "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold)).foregroundStyle(MossPalette.mint)
                                }.padding(12).frame(maxWidth: .infinity)
                                    .background(MossPalette.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                                .accessibilityLabel("\(family.title), \(family.variations.count) variations\(saved == nil ? "" : ", in rotation")")
                                .accessibilityIdentifier("family_\(family.id)")
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
            .sheet(item: $selected) { ActivityDetailView(activity: $0) }
        }.tint(MossPalette.mint)
    }
}
