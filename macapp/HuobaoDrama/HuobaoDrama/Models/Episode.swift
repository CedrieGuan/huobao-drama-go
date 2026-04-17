import Foundation

struct Episode: Codable, Identifiable, Sendable {
    let id: Int
    var dramaId: Int
    var episodeNumber: Int
    var title: String
    var content: String?
    var scriptContent: String?
    var description: String?
    var duration: Int
    var status: String
    var videoUrl: String?
    var thumbnail: String?
    var imageConfigId: Int?
    var videoConfigId: Int?
    var audioConfigId: Int?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, content, description, duration, status, thumbnail
        case dramaId = "drama_id"
        case episodeNumber = "episode_number"
        case scriptContent = "script_content"
        case videoUrl = "video_url"
        case imageConfigId = "image_config_id"
        case videoConfigId = "video_config_id"
        case audioConfigId = "audio_config_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        dramaId = try c.decodeIfPresent(Int.self, forKey: .dramaId) ?? 0
        episodeNumber = try c.decodeIfPresent(Int.self, forKey: .episodeNumber) ?? 1
        title = try c.decode(String.self, forKey: .title)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        scriptContent = try c.decodeIfPresent(String.self, forKey: .scriptContent)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "draft"
        videoUrl = try c.decodeIfPresent(String.self, forKey: .videoUrl)
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)
        imageConfigId = try c.decodeIfPresent(Int.self, forKey: .imageConfigId)
        videoConfigId = try c.decodeIfPresent(Int.self, forKey: .videoConfigId)
        audioConfigId = try c.decodeIfPresent(Int.self, forKey: .audioConfigId)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }

    var episodeLabel: String { String(format: "E%02d", episodeNumber) }
}
