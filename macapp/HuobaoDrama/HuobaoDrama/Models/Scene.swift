import Foundation

struct Scene: Codable, Identifiable, Sendable {
    let id: Int
    var dramaId: Int
    var episodeId: Int?
    var location: String
    var time: String
    var prompt: String
    var storyboardCount: Int
    var imageUrl: String?
    var status: String
    var localPath: String?
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, location, time, prompt, status
        case dramaId = "drama_id"
        case episodeId = "episode_id"
        case storyboardCount = "storyboard_count"
        case imageUrl = "image_url"
        case localPath = "local_path"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        dramaId = try c.decodeIfPresent(Int.self, forKey: .dramaId) ?? 0
        episodeId = try c.decodeIfPresent(Int.self, forKey: .episodeId)
        location = try c.decode(String.self, forKey: .location)
        time = try c.decode(String.self, forKey: .time)
        prompt = try c.decode(String.self, forKey: .prompt)
        storyboardCount = try c.decodeIfPresent(Int.self, forKey: .storyboardCount) ?? 1
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        localPath = try c.decodeIfPresent(String.self, forKey: .localPath)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}
