import SwiftUI
import MosslingCore
import MosslingApplication

struct ForestBuilderView: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var kind = HabitatKind.stump
    @State private var cell = ForestCell(4, 3)
    @State private var message: String?

    private var snapshot: ForestSnapshot {
        ForestSnapshot(progress: store.progress, affinity: store.configuration.companionAffinity, world: store.configuration.world)
    }
    private var validation: String? {
        var draft = store.configuration.world
        do { try draft.place(kind, at: cell, growth: store.progress.growth); return nil }
        catch { return error.localizedDescription }
    }
    private var placed: HabitatPlacement? { store.configuration.world.placements.first { $0.kind == kind } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ForestCanvas(snapshot: snapshot, draftKind: kind, selectedCell: cell, onSelectCell: { cell = $0; message = nil })
                    .frame(height: typeSize.isAccessibilitySize ? 160 : 260).clipped()
                Form {
                    Section("Arrange your habitat") {
                        Picker("Object", selection: $kind) {
                            ForEach(HabitatKind.allCases) { object in
                                Text(object.title + (object.requiredGrowth > store.progress.growth ? " · \(object.requiredGrowth) growth" : ""))
                                    .tag(object).disabled(object.requiredGrowth > store.progress.growth)
                            }
                        }.accessibilityIdentifier("habitatKind")
                        Text("Tap a spot on the map, or choose its column and row.")
                            .font(.footnote)
                        Picker("Column", selection: Binding(get: { cell.x }, set: { cell = ForestCell($0, cell.y) })) {
                            ForEach(0..<(store.configuration.world.regions.contains(.grove) ? 10 : 6), id: \.self) { Text("Column \($0 + 1)").tag($0) }
                        }.accessibilityIdentifier("habitatColumn")
                        Picker("Row", selection: Binding(get: { cell.y }, set: { cell = ForestCell(cell.x, $0) })) {
                            ForEach(0..<6, id: \.self) { Text("Row \($0 + 1)").tag($0) }
                        }.accessibilityIdentifier("habitatRow")
                        if let validation { Text(validation).font(.footnote).foregroundStyle(.orange).accessibilityIdentifier("placementError") }
                        Button(placed == nil ? "Place \(kind.title)" : "Move \(kind.title)") {
                            if store.placeHabitat(kind, at: cell) { message = "Saved \(kind.title) at \(cell.title.lowercased())." }
                            else { message = store.error }
                        }.disabled(validation != nil).accessibilityIdentifier("saveHabitat")
                        if placed != nil {
                            Button("Put away \(kind.title)") {
                                if store.removeHabitat(kind) { message = "\(kind.title) is ready to place again." }
                            }.accessibilityIdentifier("removeHabitat")
                        }
                        if let message { Text(message).accessibilityIdentifier("habitatSaveStatus") }
                    }
                    Section("Explore") {
                        if store.configuration.world.regions.contains(.grove) {
                            Label("Upper grove open", systemImage: "checkmark").accessibilityIdentifier("groveOpen")
                        } else {
                            Text("Open the upper grove at 30 growth. Earned growth stays yours.")
                            Button("Open upper grove") { _ = store.expandForest(.grove) }
                                .disabled(store.progress.growth < ForestRegion.grove.requiredGrowth)
                                .accessibilityIdentifier("expandGrove")
                        }
                    }
                    Section("Placed objects") {
                        ForEach(store.configuration.world.placements) { object in
                            Text("\(object.kind.title): \(object.cell.title)")
                                .accessibilityIdentifier("placement_\(object.id)")
                        }
                    }
                }.accessibilityIdentifier("habitatControls")
            }
            .background(MossPalette.ink)
            .navigationTitle("Build forest").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: kind) { _, _ in message = nil }
            .onChange(of: cell) { _, _ in message = nil }
        }
        .tint(MossPalette.mint)
    }
}
