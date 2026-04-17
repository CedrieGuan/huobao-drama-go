import Foundation

@MainActor
final class PollingCoordinator {
    static let shared = PollingCoordinator()

    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func startPolling(key: String, interval: TimeInterval = 3.0, action: @escaping @MainActor () async -> Void) {
        stopPolling(key: key)
        tasks[key] = Task {
            while !Task.isCancelled {
                await action()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling(key: String) {
        tasks[key]?.cancel()
        tasks.removeValue(forKey: key)
    }

    func stopAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
