import Foundation

// MARK: - Drama Requests
struct CreateDramaRequest: Encodable {
    var title: String
    var description: String?
    var genre: String?
    var style: String?
    var totalEpisodes: Int
    var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case title, description, genre, style, tags
        case totalEpisodes = "total_episodes"
    }
}

struct UpdateDramaRequest: Encodable {
    var title: String?
    var description: String?
    var genre: String?
    var style: String?
    var status: String?
    var tags: [String]?
}

// MARK: - Episode Requests
struct CreateEpisodeRequest: Encodable {
    var dramaId: Int
    var title: String?
    var imageConfigId: Int
    var videoConfigId: Int
    var audioConfigId: Int

    enum CodingKeys: String, CodingKey {
        case title
        case dramaId = "drama_id"
        case imageConfigId = "image_config_id"
        case videoConfigId = "video_config_id"
        case audioConfigId = "audio_config_id"
    }
}

struct UpdateEpisodeRequest: Encodable {
    var content: String?
    var scriptContent: String?
    var title: String?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case content, title, status
        case scriptContent = "script_content"
    }
}

// MARK: - Agent Requests
struct AgentChatRequest: Encodable {
    var message: String
    var episodeId: Int?
    var dramaId: Int?

    enum CodingKeys: String, CodingKey {
        case message
        case episodeId = "episode_id"
        case dramaId = "drama_id"
    }
}

// MARK: - AIServiceConfig Requests
struct CreateAIServiceConfigRequest: Encodable {
    var serviceType: String
    var provider: String?
    var name: String
    var baseUrl: String
    var apiKey: String
    var model: String?
    var priority: Int?
    var isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case name, provider, model
        case serviceType = "service_type"
        case baseUrl = "base_url"
        case apiKey = "api_key"
        case priority
        case isActive = "is_active"
    }
}

struct UpdateAIServiceConfigRequest: Encodable {
    var name: String?
    var baseUrl: String?
    var apiKey: String?
    var model: String?
    var priority: Int?
    var isActive: Bool?
    var isDefault: Bool?

    enum CodingKeys: String, CodingKey {
        case name, model, priority
        case baseUrl = "base_url"
        case apiKey = "api_key"
        case isActive = "is_active"
        case isDefault = "is_default"
    }
}

// MARK: - AgentConfig Requests
struct UpsertAgentConfigRequest: Encodable {
    var agentType: String
    var name: String?
    var model: String?
    var systemPrompt: String?
    var temperature: Double?
    var maxTokens: Int?
    var isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case name, model, temperature
        case agentType = "agent_type"
        case systemPrompt = "system_prompt"
        case maxTokens = "max_tokens"
        case isActive = "is_active"
    }
}

// MARK: - Storyboard Requests
struct UpdateStoryboardRequest: Encodable {
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
    var dialogue: String?
    var characterIds: [Int]?

    enum CodingKeys: String, CodingKey {
        case title, location, time, angle, movement, action, result, atmosphere, dialogue
        case shotType = "shot_type"
        case imagePrompt = "image_prompt"
        case videoPrompt = "video_prompt"
        case characterIds = "character_ids"
    }
}

// MARK: - Pipeline Status
struct PipelineStatus: Decodable {
    var episodeId: Int
    var steps: PipelineSteps

    enum CodingKeys: String, CodingKey {
        case episodeId = "episode_id"
        case steps
    }
}

struct PipelineSteps: Decodable {
    var scriptRewrite: StepInfo
    var extractCharacters: StepInfo
    var extractScenes: StepInfo
    var assignVoices: StepInfo
    var generateVoiceSamples: StepInfo
    var extractStoryboards: StepInfo
    var generateImages: StepInfo
    var generateVideos: StepInfo
    var composeShots: StepInfo
    var mergeEpisode: StepInfo

    enum CodingKeys: String, CodingKey {
        case scriptRewrite = "script_rewrite"
        case extractCharacters = "extract_characters"
        case extractScenes = "extract_scenes"
        case assignVoices = "assign_voices"
        case generateVoiceSamples = "generate_voice_samples"
        case extractStoryboards = "extract_storyboards"
        case generateImages = "generate_images"
        case generateVideos = "generate_videos"
        case composeShots = "compose_shots"
        case mergeEpisode = "merge_episode"
    }
}

struct StepInfo: Decodable {
    var status: String
    var count: Int?
    var completed: Int?
    var total: Int?
    var assigned: Int?
    var mergedUrl: String?

    enum CodingKeys: String, CodingKey {
        case status, count, completed, total, assigned
        case mergedUrl = "merged_url"
    }
}

// MARK: - Image Generation Requests
struct GenerateCharacterImageRequest: Encodable {
    var characterId: Int
    var prompt: String?
    var referenceImages: [String]?

    enum CodingKeys: String, CodingKey {
        case characterId = "character_id"
        case prompt
        case referenceImages = "reference_images"
    }
}

struct GenerateStoryboardImageRequest: Encodable {
    var storyboardId: Int
    var frameType: String?

    enum CodingKeys: String, CodingKey {
        case storyboardId = "storyboard_id"
        case frameType = "frame_type"
    }
}

// MARK: - Huobao Preset
struct HuobaoPresetRequest: Encodable {
    var apiKey: String

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
    }
}
