import SwiftUI
import MosslingApplication
import MosslingCore

struct ForestDetailsView: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    CompanionPortrait(stage: store.progress.stage).frame(height: 190)
                    Text(store.progress.stage.title).font(.title2.weight(.semibold))
                    growthCard
                    affinityCard
                    if !store.progress.forestUnlocks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Taking root").font(.title3.weight(.semibold))
                            ForEach(store.progress.forestUnlocks, id: \.self) { unlock in
                                Label(unlock.title, systemImage: unlock.symbolName)
                            }
                        }.mossCard()
                    }
                }.padding(20)
            }
            .background(MossPalette.cream).foregroundStyle(MossPalette.ink)
            .navigationTitle("Your forest").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var growthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Growth").font(.system(.title3, design: .serif, weight: .medium))
                Spacer()
                Text("\(store.progress.growth) growth").font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("earnedGrowthValue")
            }
            if let milestone = store.progress.nextMilestone {
                let earned = Double(store.progress.growth)
                ProgressView(value: min(1, earned / Double(milestone.requiredGrowth)))
                    .tint(MossPalette.fern)
                    .accessibilityLabel("Progress toward " + milestone.title)
                Label(milestone.title, systemImage: milestone.symbolName)
                    .font(.subheadline.weight(.semibold))
                let remaining = (milestone.requiredGrowth - store.progress.growth + ProgressionCatalog.growthPerSnack - 1) / ProgressionCatalog.growthPerSnack
                Text("\(remaining) more \(remaining == 1 ? "snack" : "snacks") to unlock.")
                    .font(.footnote).foregroundStyle(MossPalette.moss)
            } else {
                Text("All forest milestones unlocked. Keep earning growth with every snack.")
                    .font(.footnote).foregroundStyle(MossPalette.moss)
            }
            Text("\(store.progress.completedSnackCount) \(store.progress.completedSnackCount == 1 ? "snack completed" : "snacks completed")")
                .font(.caption).foregroundStyle(MossPalette.moss)
        }.mossCard()
    }

    private var affinityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A forest of your own").font(.system(.title3, design: .serif, weight: .medium))
            if store.progress.canChooseAffinity {
                Text("Choose sunlight or moonlight for your forest. You can change it anytime.")
                    .font(.subheadline)
                ForEach(CompanionAffinity.allCases, id: \.self) { affinity in
                    Button {
                        Task { await store.saveAffinity(affinity) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: affinity == .sunlit ? "sun.max.fill" : "moon.stars.fill")
                                .foregroundStyle(affinity == .sunlit ? MossPalette.gold : MossPalette.moss)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(affinity.title).font(.headline)
                                Text(affinity.detail).font(.caption)
                                if store.configuration.companionAffinity == affinity {
                                    Label("Selected", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold))
                                }
                            }
                            Spacer(minLength: 0)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(MossPalette.mint.opacity(store.configuration.companionAffinity == affinity ? 0.5 : 0.18), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier(affinity == .sunlit ? "affinitySunlit" : "affinityMoonlit")
                        .accessibilityValue(store.configuration.companionAffinity == affinity ? "Selected" : "Not selected")
                        .accessibilityAddTraits(store.configuration.companionAffinity == affinity ? .isSelected : [])
                }
            } else {
                Label("Sunlit or Moonlit", systemImage: "lock")
                    .font(.subheadline.weight(.semibold))
                Text("Complete three snacks to unlock Sunlit and Moonlit forests.")
                    .font(.footnote).foregroundStyle(MossPalette.moss)
            }
        }.mossCard()
    }

}
