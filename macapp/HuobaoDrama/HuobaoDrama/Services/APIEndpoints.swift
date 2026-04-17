import Foundation

// All API calls go through APIClient.shared
// Usage: let dramas = try await APIEndpoints.DramaAPI.list()

@MainActor
enum APIEndpoints {

    // MARK: - Drama
    enum DramaAPI {
        static func list(page: Int = 1, pageSize: Int = 20) async throws -> PaginatedResponse<Drama> {
            try await APIClient.shared.get("/dramas?page=\(page)&page_size=\(pageSize)")
        }
        static func get(id: Int) async throws -> Drama {
            try await APIClient.shared.get("/dramas/\(id)")
        }
        static func create(_ req: CreateDramaRequest) async throws -> Drama {
            try await APIClient.shared.post("/dramas", body: req)
        }
        static func update(id: Int, _ req: UpdateDramaRequest) async throws -> EmptyData {
            try await APIClient.shared.put("/dramas/\(id)", body: req)
        }
        static func delete(id: Int) async throws {
            try await APIClient.shared.delete("/dramas/\(id)")
        }
        static func saveCharacters(dramaId: Int, characters: [Character]) async throws -> EmptyData {
            struct Body: Encodable { var characters: [Character] }
            return try await APIClient.shared.put("/dramas/\(dramaId)/characters", body: Body(characters: characters))
        }
    }

    // MARK: - Episode
    enum EpisodeAPI {
        static func create(_ req: CreateEpisodeRequest) async throws -> Episode {
            try await APIClient.shared.post("/episodes", body: req)
        }
        static func update(id: Int, _ req: UpdateEpisodeRequest) async throws -> EmptyData {
            try await APIClient.shared.put("/episodes/\(id)", body: req)
        }
        static func storyboards(episodeId: Int) async throws -> [Storyboard] {
            try await APIClient.shared.get("/episodes/\(episodeId)/storyboards")
        }
        static func characters(episodeId: Int) async throws -> [Character] {
            try await APIClient.shared.get("/episodes/\(episodeId)/characters")
        }
        static func scenes(episodeId: Int) async throws -> [Scene] {
            try await APIClient.shared.get("/episodes/\(episodeId)/scenes")
        }
        static func pipelineStatus(episodeId: Int) async throws -> PipelineStatus {
            try await APIClient.shared.get("/episodes/\(episodeId)/pipeline-status")
        }
    }

    // MARK: - Agent
    @MainActor enum AgentAPI {
        static func chat(agentType: String, episodeId: Int, message: String) -> AsyncThrowingStream<String, Error> {
            let body = AgentChatRequest(message: message, episodeId: episodeId)
            return APIClient.shared.streamSSE(path: "/agent/\(agentType)/chat", body: body)
        }
        static func run(agentType: String, episodeId: Int) -> AsyncThrowingStream<String, Error> {
            struct Body: Encodable { var episodeId: Int; enum CodingKeys: String, CodingKey { case episodeId = "episode_id" } }
            return APIClient.shared.streamSSE(path: "/agent/\(agentType)/run", body: Body(episodeId: episodeId))
        }
    }

    // MARK: - Storyboard
    enum StoryboardAPI {
        static func update(id: Int, _ req: UpdateStoryboardRequest) async throws -> EmptyData {
            try await APIClient.shared.put("/storyboards/\(id)", body: req)
        }
        static func delete(id: Int) async throws {
            try await APIClient.shared.delete("/storyboards/\(id)")
        }
    }

    // MARK: - AI Service Config
    enum AIConfigAPI {
        static func list() async throws -> [AIServiceConfig] {
            try await APIClient.shared.get("/ai-configs")
        }
        static func create(_ req: CreateAIServiceConfigRequest) async throws -> AIServiceConfig {
            try await APIClient.shared.post("/ai-configs", body: req)
        }
        static func update(id: Int, _ req: UpdateAIServiceConfigRequest) async throws -> EmptyData {
            try await APIClient.shared.put("/ai-configs/\(id)", body: req)
        }
        static func delete(id: Int) async throws {
            try await APIClient.shared.delete("/ai-configs/\(id)")
        }
        static func test(id: Int) async throws -> EmptyData {
            struct Body: Encodable { var id: Int }
            return try await APIClient.shared.post("/ai-configs/test", body: Body(id: id))
        }
        static func providers() async throws -> [AIServiceProvider] {
            try await APIClient.shared.get("/ai-configs/providers")
        }
        static func setupHuobaoPreset(apiKey: String) async throws -> EmptyData {
            try await APIClient.shared.post("/ai-configs/huobao-preset", body: HuobaoPresetRequest(apiKey: apiKey))
        }
    }

    // MARK: - Agent Config
    enum AgentConfigAPI {
        static func list() async throws -> [AgentConfig] {
            try await APIClient.shared.get("/agent-configs")
        }
        static func upsert(_ req: UpsertAgentConfigRequest) async throws -> AgentConfig {
            try await APIClient.shared.post("/agent-configs", body: req)
        }
        static func update(id: Int, _ req: UpsertAgentConfigRequest) async throws -> EmptyData {
            try await APIClient.shared.put("/agent-configs/\(id)", body: req)
        }
    }

    // MARK: - Skills
    enum SkillsAPI {
        static func list() async throws -> [Skill] {
            try await APIClient.shared.get("/skills")
        }
        static func get(id: String) async throws -> Skill {
            try await APIClient.shared.get("/skills/\(id)")
        }
        static func update(id: String, content: String) async throws -> EmptyData {
            struct Body: Encodable { var content: String }
            return try await APIClient.shared.put("/skills/\(id)", body: Body(content: content))
        }
        static func delete(id: String) async throws {
            try await APIClient.shared.delete("/skills/\(id)")
        }
    }

    // MARK: - AI Voices
    enum VoicesAPI {
        static func list() async throws -> [VoiceProfile] {
            try await APIClient.shared.get("/ai-voices")
        }
    }

    // MARK: - Images
    enum ImagesAPI {
        static func generateCharacter(_ req: GenerateCharacterImageRequest) async throws -> EmptyData {
            try await APIClient.shared.post("/images/character", body: req)
        }
        static func generateStoryboard(_ req: GenerateStoryboardImageRequest) async throws -> EmptyData {
            try await APIClient.shared.post("/images/storyboard", body: req)
        }
        static func generateScene(sceneId: Int) async throws -> EmptyData {
            struct Body: Encodable { var sceneId: Int; enum CodingKeys: String, CodingKey { case sceneId = "scene_id" } }
            return try await APIClient.shared.post("/images/scene", body: Body(sceneId: sceneId))
        }
    }

    // MARK: - Videos
    enum VideosAPI {
        static func generate(storyboardId: Int) async throws -> EmptyData {
            struct Body: Encodable { var storyboardId: Int; enum CodingKeys: String, CodingKey { case storyboardId = "storyboard_id" } }
            return try await APIClient.shared.post("/videos/generate", body: Body(storyboardId: storyboardId))
        }
    }

    // MARK: - Compose
    enum ComposeAPI {
        static func shot(storyboardId: Int) async throws -> EmptyData {
            struct Body: Encodable { var storyboardId: Int; enum CodingKeys: String, CodingKey { case storyboardId = "storyboard_id" } }
            return try await APIClient.shared.post("/compose/shot", body: Body(storyboardId: storyboardId))
        }
        static func tts(storyboardId: Int) async throws -> EmptyData {
            struct Body: Encodable { var storyboardId: Int; enum CodingKeys: String, CodingKey { case storyboardId = "storyboard_id" } }
            return try await APIClient.shared.post("/compose/tts", body: Body(storyboardId: storyboardId))
        }
    }

    // MARK: - Merge
    enum MergeAPI {
        static func episode(episodeId: Int) async throws -> EmptyData {
            struct Body: Encodable { var episodeId: Int; enum CodingKeys: String, CodingKey { case episodeId = "episode_id" } }
            return try await APIClient.shared.post("/merge/episode", body: Body(episodeId: episodeId))
        }
    }

    // MARK: - Grid
    enum GridAPI {
        static func generate(episodeId: Int, characterId: Int) async throws -> EmptyData {
            struct Body: Encodable {
                var episodeId: Int; var characterId: Int
                enum CodingKeys: String, CodingKey { case episodeId = "episode_id"; case characterId = "character_id" }
            }
            return try await APIClient.shared.post("/grid/generate", body: Body(episodeId: episodeId, characterId: characterId))
        }
    }
}
