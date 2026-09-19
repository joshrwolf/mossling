import Foundation
import Testing
@testable import MosslingCore

@Suite("Non-destructive backup recovery")
struct BackupTests {
    @Test func mergeKeepsIdentitySettingsAndExistingProgress() throws {
        let first = sampleEvent(), second = sampleEvent(sampleOpportunity(hour: 10))
        var current = AppDocument(configuration: AppConfiguration(companionName: "Current"), events: [first])
        let identity = current.deviceID
        let backup = AppDocument(configuration: AppConfiguration(companionName: "Old"), events: [first, second])
        try DocumentSync.mergeBackup(backup, into: &current)
        #expect(current.deviceID == identity)
        #expect(current.configuration.companionName == "Current")
        #expect(current.events.count == 2)
        #expect(current.pendingEventIDs == [second.eventID])
        #expect(CompletionLedger(events: current.events).progress.growth == 20)
        try DocumentSync.mergeBackup(backup, into: &current)
        #expect(current.events.count == 2)
        #expect(current.pendingEventIDs == [second.eventID])
    }

    @Test func invalidBackupCannotPartiallyMerge() throws {
        var current = AppDocument()
        let original = current
        var backup = AppDocument(events: [sampleEvent()])
        backup.schemaVersion = 999
        #expect(throws: DocumentError.unsupportedVersion(999)) {
            try DocumentSync.mergeBackup(backup, into: &current)
        }
        #expect(current == original)
    }
}
