import Foundation

@MainActor
@Observable
final class ConnectionSettingsStore {
    static let shared = ConnectionSettingsStore()

    private let baseURLKey = "huobao_backend_base_url"
    private let defaults = UserDefaults.standard

    var baseURL: String {
        didSet { defaults.set(baseURL, forKey: baseURLKey) }
    }

    private init() {
        baseURL = defaults.string(forKey: "huobao_backend_base_url") ?? "http://localhost:5680"
    }

    var apiBaseURL: String { baseURL.trimmingCharacters(in: .init(charactersIn: "/")) + "/api/v1" }
}
