import SwiftUI
import MosslingCore
import UniformTypeIdentifiers

struct RhythmView: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var showingSchedule = false
    @State private var companionName = ""
    @State private var exportDocument = ForestExportDocument(data: Data())
    @State private var exporting = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A rhythm that fits your real life.")
                        .font(.system(.title2, design: .serif, weight: .medium))
                        .foregroundStyle(MossPalette.ink)
                        .listRowBackground(Color.clear)
                }
                Section("Your rhythm") {
                    Button { showingSchedule = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.configuration.schedule.enabled ? "Every \(store.configuration.schedule.intervalMinutes) minutes" : "Reminders paused")
                                    .font(.headline)
                                Text(scheduleSummary).font(.subheadline).foregroundStyle(MossPalette.moss)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.foregroundStyle(MossPalette.ink)
                    }.accessibilityIdentifier("editSchedule")
                } footer: {
                    Text("Times follow your current local time zone. Skipped breaks never cost you growth.")
                }
                Section("Gentle reminders") {
                    LabeledContent("Notifications", value: store.notificationStatus)
                    Button("Enable reminders") { Task { await store.requestNotificationPermission() } }
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text("Your device’s Focus and notification settings decide when reminders appear. Your app never needs to run in the background for scheduled reminders.")
                }
                Section("Your forest friend") {
                    TextField("Companion name", text: $companionName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { saveName() }
                    if companionName != store.configuration.companionName {
                        Button("Save name") { saveName() }
                    }
                }
                Section("Your data") {
                    Button { prepareExport() } label: { Label("Export your forest", systemImage: "square.and.arrow.up") }
                    if let status = store.status { Text(status).font(.footnote).foregroundStyle(MossPalette.moss) }
                } footer: {
                    Text("Your history is saved on your devices. No account, ads, or analytics. The phone manages your schedule and snacks; your watch can record breaks offline and sync when connected.")
                }
                Section {
                    HStack {
                        Text("Mossling")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                            .foregroundStyle(MossPalette.moss)
                    }
                } footer: { Text("A little movement. A little magic.") }
            }
            .scrollContentBackground(.hidden).background(MossPalette.cream)
            .navigationTitle("Find your rhythm")
            .onAppear { companionName = store.configuration.companionName }
            .sheet(isPresented: $showingSchedule) { ScheduleEditor(schedule: store.configuration.schedule) }
            .onChange(of: store.navigationRequest) { _, _ in showingSchedule = false; exporting = false }
            .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "Mossling-forest") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
            .alert("Export couldn’t finish", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button("OK") { exportError = nil }
            } message: { Text(exportError ?? "") }
        }
    }

    private var scheduleSummary: String {
        let schedule = store.configuration.schedule
        let days = schedule.weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        return "\(days) · \(minuteLabel(schedule.startMinute))–\(minuteLabel(schedule.endMinute))"
    }
    private func saveName() {
        var config = store.configuration
        config.companionName = companionName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { _ = await store.saveConfig(config) }
    }
    private func prepareExport() {
        do { exportDocument = ForestExportDocument(data: try store.exportData()); exporting = true }
        catch { exportError = error.localizedDescription }
    }
}

struct ScheduleEditor: View {
    @Environment(MosslingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var schedule: ScheduleConfiguration
    @State private var validationMessage: String?
    @State private var saving = false

    init(schedule: ScheduleConfiguration) { _schedule = State(initialValue: schedule) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Make room for movement breaks", isOn: $schedule.enabled)
                }
                Section("Active days") {
                    // Full-width rows adapt cleanly to the largest accessibility sizes.
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(
                            get: { schedule.weekdays.contains(day) },
                            set: { enabled in if enabled { schedule.weekdays.insert(day) } else { schedule.weekdays.remove(day) } }
                        ))
                    }
                }.disabled(!schedule.enabled)
                Section("Active hours") {
                    DatePicker("First break", selection: minuteBinding(isEnd: false), displayedComponents: .hourAndMinute)
                    DatePicker("Reminders stop", selection: minuteBinding(isEnd: true), displayedComponents: .hourAndMinute)
                    Picker("A break every", selection: $schedule.intervalMinutes) {
                        Text("60 minutes").tag(60)
                        Text("90 minutes").tag(90)
                        Text("120 minutes").tag(120)
                    }
                } footer: {
                    Text("Breaks begin at your first time and stop before the end time. Use midnight as the end to include the rest of the day. Overnight schedules aren’t supported yet. You can schedule up to 56 reminders a week.")
                }.disabled(!schedule.enabled)
                if let validationMessage {
                    Section { Text(validationMessage).font(.subheadline).foregroundStyle(Color.red) }
                }
                Section {
                    Text("Your forest rests outside these hours. There’s no catch-up list and no lost progress.")
                        .font(.subheadline).foregroundStyle(MossPalette.moss)
                }
            }
            .scrollContentBackground(.hidden).background(MossPalette.cream)
            .navigationTitle("Your rhythm").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }.disabled(saving)
                        .accessibilityIdentifier("saveSchedule")
                }
            }
        }
    }

    private func minuteBinding(isEnd: Bool) -> Binding<Date> {
        Binding(
            get: {
                let minute = isEnd ? schedule.endMinute % 1440 : schedule.startMinute
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                let value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                if isEnd { schedule.endMinute = value == 0 ? 1440 : value }
                else { schedule.startMinute = value }
            }
        )
    }
    private func save() {
        do { try schedule.validate() } catch { validationMessage = error.localizedDescription; return }
        var config = store.configuration
        config.schedule = schedule
        saving = true
        Task {
            let saved = await store.saveConfig(config)
            saving = false
            if saved { dismiss() } else { validationMessage = store.error ?? "We couldn’t save that rhythm. Please try again." }
        }
    }
}

private func minuteLabel(_ value: Int) -> String {
    let minute = value % 1440
    let date = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
    return date.formatted(date: .omitted, time: .shortened)
}

struct ForestExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
