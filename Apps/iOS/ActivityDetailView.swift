import SwiftUI
import MosslingCore
import MosslingApplication

struct ActivityDetailView: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var targetWidth = 75.0
    @State private var draft: ActivityDefinition
    @State private var saving = false
    @State private var failure: String?
    @State private var editing = false
    @State private var confirmRemoval = false

    init(activity: ActivityDefinition) { _draft = State(initialValue: activity) }

    private var saved: ActivityDefinition? { store.configuration.activities.first { $0.id == draft.id } }
    private var family: ActivityFamily? { draft.family }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ActivityDemonstration(activity: draft)
                        .frame(maxWidth: .infinity)
                        .background(RadialGradient(colors: [MossPalette.mint.opacity(0.16), .clear],
                                                   center: .center, startRadius: 15, endRadius: 160))
                    Text(draft.title).font(.system(.title, design: .serif, weight: .bold))
                        .accessibilityIdentifier("activityDetailTitle")
                    Text(draft.instructions).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("activityDescription")
                    if let variation = draft.variation {
                        Label(variation.equipment, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundStyle(MossPalette.mint)
                    }
                    if let family {
                        variations(family)
                        if !family.guidance.isEmpty {
                            Text(family.guidance).font(.footnote).foregroundStyle(MossPalette.mint)
                        }
                    }
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Snack target").font(.headline)
                            targetInput
                        }
                    } else {
                        HStack {
                            Text("Snack target").font(.headline)
                            Spacer()
                            targetInput
                        }
                    }
                    if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("activitySaveError") }
                }.padding(22)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MossPalette.ink).foregroundStyle(MossPalette.cream)
            .navigationTitle(family?.title ?? "Activity").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if family == nil { Button("Edit activity", systemImage: "pencil") { editing = true } }
                        if saved != nil {
                            Button("Remove activity", systemImage: "trash", role: .destructive) { confirmRemoval = true }
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("Activity options").disabled(saving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(saved == nil ? "Add to rotation" : "Save changes") { save() }
                    .buttonStyle(MossPrimaryButtonStyle()).disabled(saving)
                    .accessibilityIdentifier("useVariation")
                    .padding(.horizontal, 22).padding(.vertical, 12).background(MossPalette.ink)
            }
            .sheet(isPresented: $editing, onDismiss: {
                if let saved { draft = saved } else { dismiss() }
            }) { ActivityEditor(activity: draft) }
            .confirmationDialog("Remove this activity?", isPresented: $confirmRemoval, titleVisibility: .visible) {
                Button("Remove activity", role: .destructive) { remove() }
            } message: { Text("Completed snacks stay in your journal.") }
            .interactiveDismissDisabled(saving)
            .onChange(of: store.navigationRequest) { _, _ in dismiss() }
        }.tint(MossPalette.mint)
    }

    private var targetInput: some View {
        HStack {
            TextField("Target", value: $draft.targetValue, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .frame(width: targetWidth).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("variationTarget")
                .accessibilityLabel(draft.targetKind == .duration ? "Duration in seconds" : "Number of repetitions")
            Text(draft.targetKind == .duration ? "sec" : "reps").foregroundStyle(MossPalette.mint)
        }
    }

    private func variations(_ family: ActivityFamily) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose your variation").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: typeSize.isAccessibilitySize ? 1 : min(3, family.variations.count)), spacing: 8) {
                ForEach(family.variations) { variation in
                    Button {
                        guard draft.catalogVariationID != variation.id else { return }
                        draft = draft.selecting(variation)
                        failure = nil
                    } label: {
                        VStack(spacing: 5) {
                            ActivityIllustration(activity: variation.activity).frame(height: typeSize.isAccessibilitySize ? 85 : 65)
                            Text(variation.label).font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: draft.catalogVariationID == variation.id ? "checkmark.circle.fill" : "circle")
                                .font(.caption).accessibilityHidden(true)
                        }.padding(10).frame(maxWidth: .infinity, minHeight: 118)
                            .background(MossPalette.mint.opacity(draft.catalogVariationID == variation.id ? 0.2 : 0.07),
                                        in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
                                MossPalette.mint.opacity(draft.catalogVariationID == variation.id ? 0.9 : 0.2)))
                    }.buttonStyle(.plain).disabled(saving)
                        .accessibilityLabel(variation.label)
                        .accessibilityAddTraits(draft.catalogVariationID == variation.id ? .isSelected : [])
                        .accessibilityIdentifier("variation_\(variation.id)")
                }
            }
        }
    }

    private func save() {
        do { try draft.validate() } catch { failure = error.localizedDescription; return }
        var config = store.configuration
        if let index = config.activities.firstIndex(where: { $0.id == draft.id }) {
            config.activities[index] = draft
        } else if let family, config.activities.contains(where: { $0.family == family }) {
            failure = "This family is already in your rotation. Open its card to change the variation."
            return
        } else { config.activities.append(draft) }
        persist(config)
    }

    private func remove() {
        var config = store.configuration
        config.activities.removeAll { $0.id == draft.id }
        persist(config)
    }

    private func persist(_ config: AppConfiguration) {
        saving = true
        failure = nil
        Task {
            let success = await store.saveConfig(config)
            saving = false
            if success { dismiss() } else { failure = store.error }
        }
    }
}
