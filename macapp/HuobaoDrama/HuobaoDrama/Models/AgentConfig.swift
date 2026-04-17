import Foundation

struct AgentConfig: Codable, Identifiable, Sendable {
    let id: Int
    var agentType: String
    var name: String
    var description: String?
    var model: String?
    var systemPrompt: String?
    var temperature: Double?
    var maxTokens: Int?
    var maxIterations: Int?
    var isActive: Bool
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, model
        case agentType = "agent_type"
        case systemPrompt = "system_prompt"
        case temperature
        case maxTokens = "max_tokens"
        case maxIterations = "max_iterations"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        agentType = try c.decode(String.self, forKey: .agentType)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens)
        maxIterations = try c.decodeIfPresent(Int.self, forKey: .maxIterations)
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}
