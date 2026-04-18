import Foundation

struct AIServiceConfig: Codable, Identifiable, Sendable {
    let id: Int
    var serviceType: String
    var provider: String?
    var name: String
    var baseUrl: String
    var apiKey: String
    var model: [String]
    var endpoint: String?
    var queryEndpoint: String?
    var priority: Int
    var isDefault: Bool
    var isActive: Bool
    var settings: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, provider, model, endpoint, settings
        case serviceType = "service_type"
        case baseUrl = "base_url"
        case apiKey = "api_key"
        case queryEndpoint = "query_endpoint"
        case priority
        case isDefault = "is_default"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        serviceType = try c.decode(String.self, forKey: .serviceType)
        provider = try c.decodeIfPresent(String.self, forKey: .provider)
        name = try c.decode(String.self, forKey: .name)
        baseUrl = try c.decode(String.self, forKey: .baseUrl)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        model = try c.decodeIfPresent([String].self, forKey: .model) ?? []
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
        queryEndpoint = try c.decodeIfPresent(String.self, forKey: .queryEndpoint)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        settings = try c.decodeIfPresent(String.self, forKey: .settings)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}

struct AIServiceProvider: Codable, Identifiable, Sendable {
    let id: Int
    var name: String
    var displayName: String?
    var serviceType: String
    var provider: String
    var defaultUrl: String?
    var presetModels: [String]
    var description: String?
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case displayName = "display_name"
        case serviceType = "service_type"
        case provider
        case defaultUrl = "default_url"
        case presetModels = "preset_models"
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        serviceType = try c.decode(String.self, forKey: .serviceType)
        provider = try c.decode(String.self, forKey: .provider)
        defaultUrl = try c.decodeIfPresent(String.self, forKey: .defaultUrl)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        // Backend returns preset_models as array (already parsed from JSON)
        if let arr = try? c.decodeIfPresent([String].self, forKey: .presetModels) {
            presetModels = arr ?? []
        } else if let raw = try c.decodeIfPresent(String.self, forKey: .presetModels),
                  let decoded = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) {
            presetModels = decoded
        } else {
            presetModels = []
        }
    }
}
