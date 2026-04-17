import Foundation

struct Drama: Codable, Identifiable, Sendable {
    let id: Int
    var title: String
    var description: String?
    var genre: String?
    var style: String?
    var totalEpisodes: Int
    var status: String
    var thumbnail: String?
    var tags: [String]
    var createdAt: String
    var updatedAt: String
    var episodes: [Episode]
    var characters: [Character]
    var scenes: [Scene]

    enum CodingKeys: String, CodingKey {
        case id, title, description, genre, style, status, thumbnail, tags
        case totalEpisodes = "total_episodes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case episodes, characters, scenes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        style = try c.decodeIfPresent(String.self, forKey: .style)
        totalEpisodes = try c.decodeIfPresent(Int.self, forKey: .totalEpisodes) ?? 0
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "draft"
        thumbnail = try c.decodeIfPresent(String.self, forKey: .thumbnail)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        episodes = try c.decodeIfPresent([Episode].self, forKey: .episodes) ?? []
        characters = try c.decodeIfPresent([Character].self, forKey: .characters) ?? []
        scenes = try c.decodeIfPresent([Scene].self, forKey: .scenes) ?? []
    }

    var progress: Double {
        guard !episodes.isEmpty else { return 0 }
        let done = episodes.filter { $0.scriptContent != nil && !($0.scriptContent?.isEmpty ?? true) }.count
        return Double(done) / Double(episodes.count)
    }
}
