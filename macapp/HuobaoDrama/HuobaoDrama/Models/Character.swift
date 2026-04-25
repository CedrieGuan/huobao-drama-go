import Foundation

struct Character: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    var dramaId: Int
    var name: String
    var role: String?
    var description: String?
    var appearance: String?
    var personality: String?
    var voiceStyle: String?
    var imageUrl: String?
    var referenceImages: [String]
    var seedValue: String?
    var sortOrder: Int?
    var localPath: String?
    var voiceSampleUrl: String?
    var voiceProvider: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, role, description, appearance, personality
        case dramaId = "drama_id"
        case voiceStyle = "voice_style"
        case imageUrl = "image_url"
        case referenceImages = "reference_images"
        case seedValue = "seed_value"
        case sortOrder = "sort_order"
        case localPath = "local_path"
        case voiceSampleUrl = "voice_sample_url"
        case voiceProvider = "voice_provider"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        dramaId = try c.decodeIfPresent(Int.self, forKey: .dramaId) ?? 0
        name = try c.decode(String.self, forKey: .name)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance)
        personality = try c.decodeIfPresent(String.self, forKey: .personality)
        voiceStyle = try c.decodeIfPresent(String.self, forKey: .voiceStyle)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        seedValue = try c.decodeIfPresent(String.self, forKey: .seedValue)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder)
        localPath = try c.decodeIfPresent(String.self, forKey: .localPath)
        voiceSampleUrl = try c.decodeIfPresent(String.self, forKey: .voiceSampleUrl)
        voiceProvider = try c.decodeIfPresent(String.self, forKey: .voiceProvider)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        if let raw = try c.decodeIfPresent(String.self, forKey: .referenceImages),
           let arr = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) {
            referenceImages = arr
        } else {
            referenceImages = []
        }
    }
}
