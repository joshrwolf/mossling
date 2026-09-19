import SwiftUI
import MosslingCore
import UniformTypeIdentifiers

struct JournalView: View {
    @Environment(MosslingStore.self) private var store
    @State private var showingImporter = false
    @State private var pendingImport: Data?
    @State private var importMessage: String?
    @State private var importing = false

    /// A reward is one moment, even when both devices recorded it offline.
    /// Keep all source events in the ledger; this is a presentation projection.
    private var moments: [CompletionEvent] {
        var seen = Set<String>()
        return store.events.sorted {
            $0.completedAt == $1.completedAt ? $0.eventID.uuidString < $1.eventID.uuidString : $0.completedAt < $1.completedAt
        }.filter { seen.insert($0.rewardKey).inserted }
    }

    private var days: [Date] {
        Set(moments.map { Calendar.current.startOfDay(for: $0.completedAt) }).sorted(by: >)
    }

    var body: some View {
        NavigationStack {
            Group {
                if moments.isEmpty {
                    ContentUnavailableView {
                        Label("Your story starts small", systemImage: "leaf")
                    } description: {
                        Text("Your completed movement breaks will find a home here. No empty days, missed streaks, or catching up.")
                    }
                } else {
                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(store.progress.completedSnackCount) little moments")
                                    .font(.system(.title2, design: .serif, weight: .medium))
                                Text("A record of making time for yourself.")
                                    .font(.subheadline).foregroundStyle(MossPalette.moss)
                            }.padding(.vertical, 10).listRowBackground(Color.clear)
                        }
                        ForEach(days, id: \.self) { day in
                            Section(day.formatted(date: .abbreviated, time: .omitted)) {
                                ForEach(moments.filter { Calendar.current.isDate($0.completedAt, inSameDayAs: day) }.sorted { $0.completedAt > $1.completedAt }) { event in
                                    HStack(alignment: .top, spacing: 14) {
                                        Image(systemName: "leaf.fill").foregroundStyle(MossPalette.fern).padding(.top, 3)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(event.activity.title).font(.headline)
                                            Text(event.activity.targetSummary + " · " + event.completedAt.formatted(date: .omitted, time: .shortened))
                                                .font(.subheadline).foregroundStyle(MossPalette.moss)
                                        }
                                    }.padding(.vertical, 5)
                                }
                            }
                        }
                    }.scrollContentBackground(.hidden)
                }
            }
            .background(MossPalette.cream).foregroundStyle(MossPalette.ink)
            .navigationTitle("Your forest journal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingImporter = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Import a forest backup")
                        .disabled(importing)
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20_000_000 else {
                            importMessage = "This file is too large to be a supported forest backup."; return
                        }
                        pendingImport = try Data(contentsOf: url)
                    } catch { importMessage = error.localizedDescription }
                case .failure(let error): importMessage = error.localizedDescription
                }
            }
            .confirmationDialog("Merge this forest backup?", isPresented: Binding(
                get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }
            ), titleVisibility: .visible) {
                Button("Merge backup") {
                    guard let data = pendingImport else { return }
                    pendingImport = nil
                    importing = true
                    Task {
                        let saved = await store.importData(data)
                        importing = false
                        if saved { importMessage = "Your backed-up progress has joined your forest. Your current rhythm and activities are unchanged." }
                    }
                }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                Text("Add saved movement history to this forest. Your existing progress, rhythm, and activities will stay. Repeated entries won’t earn growth twice.")
            }
            .alert("Forest backup", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK") { importMessage = nil }
            } message: { Text(importMessage ?? "") }
            .onChange(of: store.navigationRequest) { _, _ in showingImporter = false; pendingImport = nil }
        }
    }
}
