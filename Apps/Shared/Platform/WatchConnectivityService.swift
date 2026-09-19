import Foundation
@preconcurrency import WatchConnectivity

/// Byte transport only. Delivery completion is NOT a durable application acknowledgment.
@MainActor
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    enum Channel: Sendable { case snapshot, events }
    enum State: Equatable, Sendable {
        case unsupported, inactive, activating, ready, waitingForCompanion, failed(String)
    }
    enum ServiceError: LocalizedError {
        case unsupported, notActivated, counterpartUnavailable, oversized, wrongDirection, emptyPayload
        var errorDescription: String? {
            switch self {
            case .unsupported: "Watch connection is not supported on this device."
            case .notActivated: "Watch connection is starting. Your changes remain saved on this device."
            case .counterpartUnavailable: "Install Mossling on the paired device to synchronize."
            case .oversized: "The sync packet is too large. Your changes remain saved for retry."
            case .wrongDirection: "Only iPhone can publish settings to Apple Watch."
            case .emptyPayload: "An empty sync packet cannot be sent."
            }
        }
    }

    static let maximumPayloadBytes = 48 * 1024
    var onReceive: ((Data, Channel) -> Void)?
    var onResync: (() -> Void)?
    var onError: ((String) -> Void)?
    var onStateChange: (() -> Void)?
    private(set) var state: State = .inactive {
        didSet { if oldValue != state { onStateChange?() } }
    }
    private(set) var isReachable = false {
        didSet { if oldValue != isReachable { onStateChange?() } }
    }

    private let session: WCSession?
    private nonisolated static let payloadKey = "mossling.payload.v1"

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        if session == nil { state = .unsupported }
    }

    func activate() {
        guard let session else { state = .unsupported; return }
        session.delegate = self
        if session.activationState == .activated {
            updateSessionState()
            consumeCachedSnapshot()
            onResync?()
        } else {
            state = .activating
            session.activate()
        }
    }

    func sendSnapshot(_ data: Data) throws {
        #if os(iOS)
        let activeSession = try validatedSession(for: data)
        try activeSession.updateApplicationContext([Self.payloadKey: data])
        #else
        throw ServiceError.wrongDirection
        #endif
    }

    func sendEvents(_ data: Data) throws {
        let activeSession = try validatedSession(for: data)
        guard !activeSession.outstandingUserInfoTransfers.contains(where: {
            ($0.userInfo[Self.payloadKey] as? Data) == data
        }) else { return }
        activeSession.transferUserInfo([Self.payloadKey: data])
    }

    private func validatedSession(for data: Data) throws -> WCSession {
        guard !data.isEmpty else { throw ServiceError.emptyPayload }
        guard data.count <= Self.maximumPayloadBytes else { throw ServiceError.oversized }
        guard let session else { throw ServiceError.unsupported }
        guard session.activationState == .activated else { throw ServiceError.notActivated }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { throw ServiceError.counterpartUnavailable }
        #else
        guard session.isCompanionAppInstalled else { throw ServiceError.counterpartUnavailable }
        #endif
        return session
    }

    private func updateSessionState() {
        guard let session else { state = .unsupported; return }
        isReachable = session.isReachable
        guard session.activationState == .activated else { state = .inactive; return }
        #if os(iOS)
        state = session.isPaired && session.isWatchAppInstalled ? .ready : .waitingForCompanion
        #else
        state = session.isCompanionAppInstalled ? .ready : .waitingForCompanion
        #endif
    }

    private func consumeCachedSnapshot() {
        #if os(watchOS)
        if let data = session?.receivedApplicationContext[Self.payloadKey] as? Data {
            receive(data, channel: .snapshot)
        }
        #endif
    }

    private func receive(_ data: Data?, channel: Channel) {
        guard let data, !data.isEmpty, data.count <= Self.maximumPayloadBytes else {
            onError?("The other device sent an invalid or oversized sync packet.")
            return
        }
        onReceive?(data, channel)
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let message {
                self.state = .failed(message)
                self.onError?(message)
                return
            }
            self.updateSessionState()
            self.consumeCachedSnapshot()
            self.onResync?()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.updateSessionState()
            self?.onResync?()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[Self.payloadKey] as? Data
        #if os(watchOS)
        Task { @MainActor [weak self] in self?.receive(data, channel: .snapshot) }
        #else
        Task { @MainActor [weak self] in
            self?.onError?("Ignored settings from Apple Watch: iPhone owns configuration.")
        }
        #endif
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let data = userInfo[Self.payloadKey] as? Data
        Task { @MainActor [weak self] in self?.receive(data, channel: .events) }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: (any Error)?
    ) {
        guard let message = error?.localizedDescription else { return }
        Task { @MainActor [weak self] in
            self?.onError?("Sync delivery failed; saved changes will retry. \(message)")
        }
    }

    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.updateSessionState()
            self?.onResync?()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.state = .inactive }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate to connect to the newly selected paired watch.
        Task { @MainActor [weak self] in self?.activate() }
    }
    #endif
}
