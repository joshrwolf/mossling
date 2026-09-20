import Dispatch

/// Notification removal can block in synchronous system IPC. Await its return
/// on a dedicated queue, keeping both MainActor and the cooperative pool free.
public final class NotificationMutationQueue: Sendable {
    private let queue = DispatchQueue(label: "com.joshrwolf.mossling.notification-mutations", qos: .utility)

    public init() {}

    public func perform(_ operation: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            queue.async {
                operation()
                continuation.resume()
            }
        }
    }
}
