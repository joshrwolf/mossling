import Foundation
import MosslingCore

public enum CompanionChannel: Sendable { case snapshot, events }
public enum CompanionConnectionState: Equatable, Sendable {
    case unsupported, inactive, activating, ready, waitingForCompanion, failed(String)
}

/// Transport success is not a durable peer acknowledgment.
@MainActor
public protocol CompanionConnection: AnyObject {
    var state: CompanionConnectionState { get }
    var onReceive: ((Data, CompanionChannel) -> Void)? { get set }
    var onResync: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onStateChange: (() -> Void)? { get set }
    func activate()
    func sendSnapshot(_ data: Data) throws
    func sendEvents(_ data: Data) throws
}

public enum ReminderAuthorization: String, Sendable, CaseIterable {
    case notDetermined, denied, authorized, provisional, ephemeral, unknown

    public var canSchedule: Bool {
        self == .authorized || self == .provisional || self == .ephemeral
    }
}

public struct ReminderAction: Sendable {
    public enum Kind: Sendable { case open, snooze }
    public let kind: Kind
    public let requestIdentifier: String
    public let deliveredAt: Date
    public let opportunityID: String?
    public let scheduledAt: Date?

    public init(kind: Kind, requestIdentifier: String, deliveredAt: Date,
                opportunityID: String?, scheduledAt: Date?) {
        self.kind = kind
        self.requestIdentifier = requestIdentifier
        self.deliveredAt = deliveredAt
        self.opportunityID = opportunityID
        self.scheduledAt = scheduledAt
    }
}

/// The Store serializes reminder mutations after durable document commits.
@MainActor
public protocol ReminderService: AnyObject {
    var onAction: ((ReminderAction) -> Void)? { get set }
    func authorizationStatus() async -> ReminderAuthorization
    func requestAuthorization() async throws -> ReminderAuthorization
    func replaceSchedule(_ plan: ReminderPlan) async throws
    func snooze(opportunity: Opportunity, until: Date) async throws
    func markCompleted(opportunityID: String) async
}
