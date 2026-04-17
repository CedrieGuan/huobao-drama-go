import Foundation

struct VoiceProfile: Codable, Identifiable, Sendable {
    let id: Int
    var voiceId: String
    var voiceName: String
    var description: [String]
    var language: String?
    var provider: String

    enum CodingKeys: String, CodingKey {
        case id, language, provider
        case voiceId = "voice_id"
        case voiceName = "voice_name"
        case description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        voiceId = try c.decode(String.self, forKey: .voiceId)
        voiceName = try c.decode(String.self, forKey: .voiceName)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        provider = try c.decode(String.self, forKey: .provider)
        if let raw = try c.decodeIfPresent(String.self, forKey: .description),
           let arr = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) {
            description = arr
        } else {
            description = []
        }
    }

    var displayName: String { "\(voiceName) (\(voiceId))" }
}
