import Foundation

struct Storyboard: Codable, Identifiable, Sendable {
    let id: Int
    var episodeId: Int
    var sceneId: Int?
    var storyboardNumber: Int
    var title: String?
    var location: String?
    var time: String?
    var shotType: String?
    var angle: String?
    var movement: String?
    var action: String?
    var result: String?
    var atmosphere: String?
    var imagePrompt: String?
    var videoPrompt: String?
    var bgmPrompt: String?
    var soundEffect: String?
    var dialogue: String?
    var description: String?
    var duration: Int
    var composedImage: String?
    var firstFrameImage: String?
    var lastFrameImage: String?
    var referenceImages: [String]
    var videoUrl: String?
    var ttsAudioUrl: String?
    var subtitleUrl: String?
    var composedVideoUrl: String?
    var status: String
    var characterIds: [Int]
    var characters: [Character]
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, location, time, angle, movement, action, result, atmosphere, description, duration, status
        case episodeId = "episode_id"
        case sceneId = "scene_id"
        case storyboardNumber = "storyboard_number"
        case shotType = "shot_type"
        case imagePrompt = "image_prompt"
        case videoPrompt = "video_prompt"
        case bgmPrompt = "bgm_prompt"
        case soundEffect = "sound_effect"
        case dialogue
        case composedImage = "composed_image"
        case firstFrameImage = "first_frame_image"
        case lastFrameImage = "last_frame_image"
        case referenceImages = "reference_images"
        case videoUrl = "video_url"
        case ttsAudioUrl = "tts_audio_url"
        case subtitleUrl = "subtitle_url"
        case composedVideoUrl = "composed_video_url"
        case characterIds = "character_ids"
        case characters
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        episodeId = try c.decode(Int.self, forKey: .episodeId)
        sceneId = try c.decodeIfPresent(Int.self, forKey: .sceneId)
        storyboardNumber = try c.decode(Int.self, forKey: .storyboardNumber)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        shotType = try c.decodeIfPresent(String.self, forKey: .shotType)
        angle = try c.decodeIfPresent(String.self, forKey: .angle)
        movement = try c.decodeIfPresent(String.self, forKey: .movement)
        action = try c.decodeIfPresent(String.self, forKey: .action)
        result = try c.decodeIfPresent(String.self, forKey: .result)
        atmosphere = try c.decodeIfPresent(String.self, forKey: .atmosphere)
        imagePrompt = try c.decodeIfPresent(String.self, forKey: .imagePrompt)
        videoPrompt = try c.decodeIfPresent(String.self, forKey: .videoPrompt)
        bgmPrompt = try c.decodeIfPresent(String.self, forKey: .bgmPrompt)
        soundEffect = try c.decodeIfPresent(String.self, forKey: .soundEffect)
        dialogue = try c.decodeIfPresent(String.self, forKey: .dialogue)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        composedImage = try c.decodeIfPresent(String.self, forKey: .composedImage)
        firstFrameImage = try c.decodeIfPresent(String.self, forKey: .firstFrameImage)
        lastFrameImage = try c.decodeIfPresent(String.self, forKey: .lastFrameImage)
        videoUrl = try c.decodeIfPresent(String.self, forKey: .videoUrl)
        ttsAudioUrl = try c.decodeIfPresent(String.self, forKey: .ttsAudioUrl)
        subtitleUrl = try c.decodeIfPresent(String.self, forKey: .subtitleUrl)
        composedVideoUrl = try c.decodeIfPresent(String.self, forKey: .composedVideoUrl)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        characterIds = try c.decodeIfPresent([Int].self, forKey: .characterIds) ?? []
        characters = try c.decodeIfPresent([Character].self, forKey: .characters) ?? []
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        if let raw = try c.decodeIfPresent(String.self, forKey: .referenceImages),
           let arr = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) {
            referenceImages = arr
        } else {
            referenceImages = try c.decodeIfPresent([String].self, forKey: .referenceImages) ?? []
        }
    }

    var label: String { String(format: "%02d", storyboardNumber) }
}
