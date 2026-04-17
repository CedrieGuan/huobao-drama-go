# Swift 原生化架构设计

> 本文档定义 HuobaoDrama Mac 原生客户端的完整技术架构，为多 Agent 并行开发提供精确的实施蓝图。
> 产品定位已经确认：**HuobaoDrama 将从 Web 产品迁移为 macOS 专用客户端**。Nuxt 前端只作为功能基线，不再作为长期交付形态。

---

## 1. 架构总览

### 1.1 技术选型

| 层面 | 选型 | 说明 |
|------|------|------|
| 语言 | Swift 6.0 | 严格并发安全 |
| UI 框架 | SwiftUI (macOS 14+) | 声明式 UI，原生性能 |
| 架构模式 | MVVM + `@Observable` | SwiftUI 原生观察机制 |
| 网络层 | `URLSession` + async/await | 原生 HTTP 客户端 |
| 任务状态 | 轮询现有 JSON API | 当前后端基线是非 SSE Agent 和轮询式异步任务 |
| 本地存储 | `UserDefaults` | 只持久化窗口状态、最近连接、用户偏好 |
| 包管理 | SPM (Swift Package Manager) | 依赖管理 |
| 最低版本 | macOS 14.0 (Sonoma) | 支持 `@Observable` / `NavigationSplitView` |

### 1.2 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                      Presentation Layer                      │
│  SwiftUI Views ─────────── @Observable ViewModels            │
│  (NavigationSplitView / Sheets / Alerts)                     │
├─────────────────────────────────────────────────────────────┤
│                       Service Layer                           │
│  APIClient ── PollingCoordinator ── DownloadExportService     │
├─────────────────────────────────────────────────────────────┤
│                        Model Layer                            │
│  Codable Structs ── Enums ── Constants                        │
├─────────────────────────────────────────────────────────────┤
│                      Platform Layer                           │
│  FileManager ── UserDefaults ── NSWorkspace ── AVFoundation  │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 SPM 包结构

```
HuobaoDrama/
├── HuobaoDrama.xcodeproj
├── HuobaoDama/
│   ├── App/
│   │   ├── HuobaoDramaApp.swift
│   │   ├── AppDelegate.swift
│   │   └── Router.swift
│   ├── Models/
│   │   ├── Drama.swift
│   │   ├── Episode.swift
│   │   ├── Character.swift
│   │   ├── Scene.swift
│   │   ├── Storyboard.swift
│   │   ├── AIServiceConfig.swift
│   │   ├── AgentConfig.swift
│   │   ├── Skill.swift
│   │   ├── VoiceProfile.swift
│   │   ├── GridImage.swift
│   │   ├── APIResponse.swift
│   │   └── Enums.swift
│   ├── Services/
│   │   ├── APIClient.swift
│   │   ├── APIEndpoints.swift
│   │   ├── ConnectionSettingsStore.swift
│   │   ├── PollingCoordinator.swift
│   │   ├── DownloadExportService.swift
│   │   └── ImageCacheService.swift
│   ├── ViewModels/
│   │   ├── DramaListViewModel.swift
│   │   ├── DramaDetailViewModel.swift
│   │   ├── StudioViewModel.swift
│   │   ├── ScriptPanelViewModel.swift
│   │   ├── ProductionPanelViewModel.swift
│   │   ├── GridToolViewModel.swift
│   │   ├── SettingsViewModel.swift
│   │   └── AgentConfigViewModel.swift
│   ├── Views/
│   │   ├── Common/
│   │   │   ├── SearchablePicker.swift
│   │   │   ├── CardView.swift
│   │   │   ├── StatusDot.swift
│   │   │   ├── TagView.swift
│   │   │   ├── LoadingOverlay.swift
│   │   │   ├── ImageViewer.swift
│   │   │   ├── AudioPlayerView.swift
│   │   │   ├── VideoPlayerView.swift
│   │   │   ├── EmptyStateView.swift
│   │   │   ├── StepBubbleBar.swift
│   │   │   └── ModalSheet.swift
│   │   ├── DramaList/
│   │   │   └── DramaListView.swift
│   │   ├── DramaDetail/
│   │   │   ├── DramaDetailView.swift
│   │   │   └── AddEpisodeSheet.swift
│   │   ├── Studio/
│   │   │   ├── StudioView.swift
│   │   │   ├── StudioTopbar.swift
│   │   │   ├── PipelineSidebar.swift
│   │   │   ├── ScriptPanel.swift
│   │   │   ├── RawContentStep.swift
│   │   │   ├── ScriptRewriteStep.swift
│   │   │   ├── ExtractStep.swift
│   │   │   ├── VoiceAssignStep.swift
│   │   │   ├── StoryboardStep.swift
│   │   │   ├── StoryboardDetailPanel.swift
│   │   │   ├── ProductionPanel.swift
│   │   │   ├── CharactersSubpanel.swift
│   │   │   ├── ScenesSubpanel.swift
│   │   │   ├── DubbingSubpanel.swift
│   │   │   ├── ShotsSubpanel.swift
│   │   │   ├── VideosSubpanel.swift
│   │   │   ├── ComposeSubpanel.swift
│   │   │   ├── GridToolSheet.swift
│   │   │   ├── ExportPanel.swift
│   │   │   └── StepNavigationView.swift
│   │   └── Settings/
│   │       ├── SettingsView.swift
│   │       ├── AIServiceConfigSection.swift
│   │       ├── AIServiceConfigSheet.swift
│   │       ├── HuobaoPresetSheet.swift
│   │       ├── AgentConfigSection.swift
│   │       ├── SkillsSection.swift
│   │       └── SkillEditSheet.swift
│   ├── DesignSystem/
│   │   ├── Colors.swift
│   │   ├── Typography.swift
│   │   ├── Spacing.swift
│   │   ├── Shadows.swift
│   │   └── DesignTokens.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── huobao-logo.png
└── HuobaoDramaTests/
    ├── Services/
    │   ├── APIClientTests.swift
    │   └── ConnectionSettingsStoreTests.swift
    └── ViewModels/
        ├── DramaListViewModelTests.swift
        └── StudioViewModelTests.swift
```

### 1.4 产品边界与连接策略

macOS 客户端是新的主产品形态，但**后端仍然是独立服务**，不嵌入 App：

- App 默认连接 `http://127.0.0.1:5679`
- 设置页允许用户修改 backend base URL
- App 不依赖 Nuxt 的 `/api` 代理，也不假设同源环境
- App 不在本地直接执行 ffmpeg、Codex、Gemini CLI；媒体处理仍由后端负责
- Agent 交互基线是当前后端的**非流式** `POST /api/v1/agent/:type/chat`

---

## 2. 数据模型层 (Models)

### 2.1 API 响应包装

```swift
// APIResponse.swift
struct APIResponse<T: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let data: T?
}
```

### 2.2 核心模型

```swift
// Drama.swift
struct Drama: Decodable, Identifiable, Hashable {
    let id: Int
    var title: String
    var style: String?
    var totalEpisodes: Int?
    var characters: [Character]?
    var scenes: [Scene]?
    var episodes: [Episode]?
    var updatedAt: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, style, characters, scenes, episodes
        case totalEpisodes = "total_episodes"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }
}

// Episode.swift
struct Episode: Decodable, Identifiable, Hashable {
    let id: Int
    var dramaId: Int
    var episodeNumber: Int
    var title: String?
    var content: String?              // 原始内容
    var scriptContent: String?        // 改写后剧本
    var duration: Int?
    var imageConfigId: Int?           // 锁定配置
    var videoConfigId: Int?
    var audioConfigId: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, content, duration
        case dramaId = "drama_id"
        case episodeNumber = "episode_number"
        case scriptContent = "script_content"
        case imageConfigId = "image_config_id"
        case videoConfigId = "video_config_id"
        case audioConfigId = "audio_config_id"
    }
}

// Character.swift
struct Character: Decodable, Identifiable, Hashable {
    let id: Int
    var name: String
    var role: String?
    var description: String?
    var appearance: String?
    var personality: String?
    var voiceStyle: String?
    var voiceSampleUrl: String?
    var imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, role, description, appearance, personality
        case voiceStyle = "voice_style"
        case voiceSampleUrl = "voice_sample_url"
        case imageUrl = "image_url"
    }
}

// Scene.swift
struct Scene: Decodable, Identifiable, Hashable {
    let id: Int
    var location: String
    var time: String?
    var description: String?
    var imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, location, time, description
        case imageUrl = "image_url"
    }
}

// Storyboard.swift
struct Storyboard: Decodable, Identifiable, Hashable {
    let id: Int
    var episodeId: Int
    var storyboardNumber: Int?
    var title: String?
    var description: String?
    var shotType: String?
    var angle: String?
    var movement: String?
    var location: String?
    var time: String?
    var duration: Int?
    var action: String?
    var result: String?
    var atmosphere: String?
    var dialogue: String?
    var imagePrompt: String?
    var videoPrompt: String?
    var bgmPrompt: String?
    var soundEffect: String?
    var sceneId: Int?
    var characterIds: [Int]?
    var firstFrameImage: String?
    var lastFrameImage: String?
    var videoUrl: String?
    var composedVideoUrl: String?
    var ttsAudioUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, angle, movement, location, time
        case duration, action, result, atmosphere, dialogue
        case episodeId = "episode_id"
        case storyboardNumber = "storyboard_number"
        case shotType = "shot_type"
        case imagePrompt = "image_prompt"
        case videoPrompt = "video_prompt"
        case bgmPrompt = "bgm_prompt"
        case soundEffect = "sound_effect"
        case sceneId = "scene_id"
        case characterIds = "character_ids"
        case firstFrameImage = "first_frame_image"
        case lastFrameImage = "last_frame_image"
        case videoUrl = "video_url"
        case composedVideoUrl = "composed_video_url"
        case ttsAudioUrl = "tts_audio_url"
    }
}
```

### 2.3 配置模型

```swift
// AIServiceConfig.swift
struct AIServiceConfig: Decodable, Identifiable, Hashable {
    let id: Int
    var name: String?
    var provider: String
    var apiKey: String?
    var baseUrl: String?
    var model: [String]
    var serviceType: String     // text / image / video / audio
    var priority: Int
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, provider, priority
        case apiKey = "api_key"
        case baseUrl = "base_url"
        case model
        case serviceType = "service_type"
        case isActive = "is_active"
    }

    /// 显示用标签
    var displayLabel: String {
        let firstModel = model.first ?? ""
        if let name, !name.isEmpty {
            return firstModel.isEmpty ? name : "\(name) · \(firstModel) (\(provider))"
        }
        return firstModel.isEmpty ? provider : "\(provider) · \(firstModel)"
    }
}

// AgentConfig.swift
struct AgentConfig: Decodable, Identifiable {
    let id: Int
    var agentType: String
    var model: String?
    var temperature: Double?
    var maxTokens: Int?
    var systemPrompt: String?

    enum CodingKeys: String, CodingKey {
        case id, model, temperature
        case agentType = "agent_type"
        case maxTokens = "max_tokens"
        case systemPrompt = "system_prompt"
    }
}

// Skill.swift
struct Skill: Decodable, Identifiable, Hashable {
    let id: String
    var name: String
    var description: String?
    var content: String?
}

// VoiceProfile.swift
struct VoiceProfile: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let gender: String
    let traits: String
    let suitable: String
}
```

### 2.4 枚举

```swift
// Enums.swift

/// 服务类型
enum ServiceType: String, CaseIterable {
    case text, image, video, audio

    var label: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        }
    }

    var description: String {
        switch self {
        case .text: return "剧本改写、角色场景提取、分镜拆解等 Agent 文本能力"
        case .image: return "角色图、场景图、镜头图与首尾帧等静态图像生成"
        case .video: return "镜头视频生成，支持单图、多图和首尾帧模式"
        case .audio: return "角色试听、旁白与对白语音生成"
        }
    }
}

/// 服务商
enum Provider: String, CaseIterable {
    case ali, chatfire, gemini, minimax, openai, openrouter, vidu, volcengine
}

/// Agent 类型
enum AgentType: String, CaseIterable {
    case scriptRewriter = "script_rewriter"
    case extractor = "extractor"
    case storyboardBreaker = "storyboard_breaker"
    case voiceAssigner = "voice_assigner"
    case gridPromptGenerator = "grid_prompt_generator"

    var label: String {
        switch self {
        case .scriptRewriter: return "剧本改写"
        case .extractor: return "角色场景提取"
        case .storyboardBreaker: return "分镜拆解"
        case .voiceAssigner: return "音色分配"
        case .gridPromptGenerator: return "图片提示词生成"
        }
    }

    var icon: String {
        switch self {
        case .scriptRewriter: return "doc.text"
        case .extractor: return "magnifyingglass"
        case .storyboardBreaker: return "film"
        case .voiceAssigner: return "mic"
        case .gridPromptGenerator: return "square.grid.3x3"
        }
    }
}

/// 视觉风格
enum VisualStyle: String, CaseIterable {
    case realistic, anime, ghibli, cinematic, comic, watercolor
}

/// Pipeline 步骤
enum PipelineStep: Int, CaseIterable {
    case rawContent = 0
    case scriptRewrite = 1
    case extract = 2
    case voiceAssign = 3
    case storyboard = 4

    var label: String {
        switch self {
        case .rawContent: return "原始内容"
        case .scriptRewrite: return "AI 改写"
        case .extract: return "提取角色与场景"
        case .voiceAssign: return "分配音色"
        case .storyboard: return "分镜列表"
        }
    }

    var stepNumber: String {
        String(format: "%02d", rawValue + 1)
    }
}

/// 生产标签页
enum ProductionTab: String, CaseIterable {
    case chars, scenes, dubbing, shots, videos, compose

    var label: String {
        switch self {
        case .chars: return "角色"
        case .scenes: return "场景"
        case .dubbing: return "配音"
        case .shots: return "帧图"
        case .videos: return "视频"
        case .compose: return "合成"
        }
    }

    var icon: String {
        switch self {
        case .chars: return "person.2"
        case .scenes: return "map"
        case .dubbing: return "mic"
        case .shots: return "photo.on.rectangle"
        case .videos: return "video"
        case .compose: return "square.grid.2x2"
        }
    }
}

/// Grid 模式
enum GridMode: String, CaseIterable {
    case firstFrame = "first_frame"
    case firstLast = "first_last"
    case multiRef = "multi_ref"

    var label: String {
        switch self {
        case .firstFrame: return "首帧"
        case .firstLast: return "首尾帧"
        case .multiRef: return "多参考"
        }
    }
}

/// Grid 布局
enum GridLayout: String, CaseIterable {
    case twoByTwo = "2x2"
    case threeByThree = "3x3"
    case fourByFour = "4x4"
    case fiveByFive = "5x5"

    var rows: Int {
        switch self {
        case .twoByTwo: return 2
        case .threeByThree: return 3
        case .fourByFour: return 4
        case .fiveByFive: return 5
        }
    }

    var cols: Int { rows }
    var total: Int { rows * cols }
}

/// 帧类型
enum FrameType: String, CaseIterable {
    case firstFrame = "first_frame"
    case lastFrame = "last_frame"
}
```

---

## 3. 服务层 (Services)

### 3.1 API 客户端

```swift
// APIClient.swift
actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession

    init(baseURLString: String = ConnectionSettingsStore.shared.apiBaseURL) {
        self.baseURL = URL(string: baseURLString)!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300  // 长任务（视频生成等）
        self.session = URLSession(configuration: config)
    }

    func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: Encodable? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // 尝试解析为 APIResponse 包装
        if let wrapper = try? JSONDecoder().decode(APIResponse<T>.self, from: data) {
            if http.statusCode >= 400 || (wrapper.code ?? 0) >= 400 {
                throw APIError.server(wrapper.message ?? "HTTP \(http.statusCode)")
            }
            if let data = wrapper.data {
                return data
            }
        }

        // 直接解析
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 下载文件到本地临时目录
    func download(path: String) async throws -> URL {
        let url = baseURL.deletingLastPathComponent()  // 去掉 /api/v1
            .appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let (tempURL, _) = try await session.download(from: url)
        return tempURL
    }

    /// 获取资源的完整 URL（用于图片/视频/audio 的 src）
    func resourceURL(path: String) -> URL {
        baseURL.deletingLastPathComponent()
            .appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case server(String)
    case network(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效响应"
        case .server(let msg): return msg
        case .network(let err): return err.localizedDescription
        case .decoding(let err): return "数据解析失败: \(err.localizedDescription)"
        }
    }
}
```

### 3.1.1 连接配置持久化

```swift
@MainActor
final class ConnectionSettingsStore {
    static let shared = ConnectionSettingsStore()

    private let defaults = UserDefaults.standard
    private let key = "huobao.api-base-url"

    var apiBaseURL: String {
        defaults.string(forKey: key) ?? "http://127.0.0.1:5679/api/v1"
    }

    func update(baseURL: String) {
        defaults.set(baseURL, forKey: key)
    }
}
```

### 3.1.2 任务状态基线

- Agent 对话：一次性 `POST /agent/:type/chat`
- 图片、视频、合成、拼接：沿用现有轮询端点
- 当前版本**不依赖 SSE**
- 如果后端未来补流式接口，再作为增强项引入 `AsyncSequence`

### 3.2 API 端点定义

```swift
// APIEndpoints.swift
// 所有 API 调用收敛到一处，方便多 Agent 并行开发时统一接口

enum APIEndpoints {

    // MARK: - Drama
    static func listDramas() async throws -> [Drama] {
        try await APIClient.shared.request("GET", "/dramas")
    }
    static func getDrama(_ id: Int) async throws -> Drama {
        try await APIClient.shared.request("GET", "/dramas/\(id)")
    }
    static func createDrama(_ data: DramaCreateRequest) async throws -> Drama {
        try await APIClient.shared.request("POST", "/dramas", body: data)
    }
    static func updateDrama(_ id: Int, _ data: DramaUpdateRequest) async throws -> Drama {
        try await APIClient.shared.request("PUT", "/dramas/\(id)", body: data)
    }
    static func deleteDrama(_ id: Int) async throws -> EmptyResponse {
        try await APIClient.shared.request("DELETE", "/dramas/\(id)")
    }

    // MARK: - Episode
    static func createEpisode(_ data: EpisodeCreateRequest) async throws -> Episode {
        try await APIClient.shared.request("POST", "/episodes", body: data)
    }
    static func updateEpisode(_ id: Int, _ data: EpisodeUpdateRequest) async throws -> Episode {
        try await APIClient.shared.request("PUT", "/episodes/\(id)", body: data)
    }
    static func getCharacters(episodeId: Int) async throws -> [Character] {
        try await APIClient.shared.request("GET", "/episodes/\(episodeId)/characters")
    }
    static func getScenes(episodeId: Int) async throws -> [Scene] {
        try await APIClient.shared.request("GET", "/episodes/\(episodeId)/scenes")
    }
    static func getStoryboards(episodeId: Int) async throws -> [Storyboard] {
        try await APIClient.shared.request("GET", "/episodes/\(episodeId)/storyboards")
    }
    static func getPipelineStatus(episodeId: Int) async throws -> PipelineStatus {
        try await APIClient.shared.request("GET", "/episodes/\(episodeId)/pipeline-status")
    }

    // MARK: - Storyboard
    static func createStoryboard(_ data: StoryboardCreateRequest) async throws -> Storyboard {
        try await APIClient.shared.request("POST", "/storyboards", body: data)
    }
    static func updateStoryboard(_ id: Int, _ data: StoryboardUpdateRequest) async throws -> Storyboard {
        try await APIClient.shared.request("PUT", "/storyboards/\(id)", body: data)
    }
    static func deleteStoryboard(_ id: Int) async throws -> EmptyResponse {
        try await APIClient.shared.request("DELETE", "/storyboards/\(id)")
    }
    static func generateTTS(storyboardId: Int) async throws -> Storyboard {
        try await APIClient.shared.request("POST", "/storyboards/\(storyboardId)/generate-tts")
    }

    // MARK: - Character
    static func updateCharacter(_ id: Int, _ data: CharacterUpdateRequest) async throws -> Character {
        try await APIClient.shared.request("PUT", "/characters/\(id)", body: data)
    }
    static func generateVoiceSample(characterId: Int, episodeId: Int) async throws -> Character {
        try await APIClient.shared.request("POST", "/characters/\(characterId)/generate-voice-sample",
                                           body: ["episode_id": episodeId])
    }
    static func generateCharacterImage(characterId: Int, episodeId: Int) async throws -> Character {
        try await APIClient.shared.request("POST", "/characters/\(characterId)/generate-image",
                                           body: ["episode_id": episodeId])
    }
    static func batchGenerateImages(characterIds: [Int], episodeId: Int) async throws -> [Character] {
        try await APIClient.shared.request("POST", "/characters/batch-generate-images",
                                           body: ["character_ids": characterIds, "episode_id": episodeId])
    }

    // MARK: - Scene
    static func generateSceneImage(sceneId: Int, episodeId: Int) async throws -> Scene {
        try await APIClient.shared.request("POST", "/scenes/\(sceneId)/generate-image",
                                           body: ["episode_id": episodeId])
    }

    // MARK: - Image
    static func generateImage(_ data: ImageGenerateRequest) async throws -> ImageResult {
        try await APIClient.shared.request("POST", "/images", body: data)
    }
    static func listImages(dramaId: Int? = nil, storyboardId: Int? = nil) async throws -> [ImageResult] {
        var query = [String: String]()
        if let dramaId { query["drama_id"] = String(dramaId) }
        if let storyboardId { query["storyboard_id"] = String(storyboardId) }
        let qs = query.isEmpty ? "" : "?" + query.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        return try await APIClient.shared.request("GET", "/images\(qs)")
    }

    // MARK: - Grid
    static func gridPrompt(_ data: GridPromptRequest) async throws -> GridPromptResult {
        try await APIClient.shared.request("POST", "/grid/prompt", body: data)
    }
    static func gridGenerate(_ data: GridGenerateRequest) async throws -> GridGenerateResult {
        try await APIClient.shared.request("POST", "/grid/generate", body: data)
    }
    static func gridStatus(id: Int) async throws -> GridStatusResult {
        try await APIClient.shared.request("GET", "/grid/status/\(id)")
    }
    static func gridSplit(_ data: GridSplitRequest) async throws -> GridSplitResult {
        try await APIClient.shared.request("POST", "/grid/split", body: data)
    }

    // MARK: - Video
    static func generateVideo(_ data: VideoGenerateRequest) async throws -> VideoResult {
        try await APIClient.shared.request("POST", "/videos", body: data)
    }
    static func getVideo(id: Int) async throws -> VideoResult {
        try await APIClient.shared.request("GET", "/videos/\(id)")
    }

    // MARK: - Compose
    static func composeShot(storyboardId: Int) async throws -> Storyboard {
        try await APIClient.shared.request("POST", "/compose/storyboards/\(storyboardId)/compose")
    }
    static func composeAll(episodeId: Int) async throws -> ComposeResult {
        try await APIClient.shared.request("POST", "/compose/episodes/\(episodeId)/compose-all")
    }
    static func composeStatus(episodeId: Int) async throws -> ComposeStatusResult {
        try await APIClient.shared.request("GET", "/compose/episodes/\(episodeId)/compose-status")
    }

    // MARK: - Merge
    static func mergeEpisode(episodeId: Int) async throws -> MergeResult {
        try await APIClient.shared.request("POST", "/merge/episodes/\(episodeId)/merge")
    }
    static func mergeStatus(episodeId: Int) async throws -> MergeResult {
        try await APIClient.shared.request("GET", "/merge/episodes/\(episodeId)/merge")
    }

    // MARK: - AI Config
    static func listAIConfigs(serviceType: String? = nil) async throws -> [AIServiceConfig] {
        let qs = serviceType.map { "?service_type=\($0)" } ?? ""
        return try await APIClient.shared.request("GET", "/ai-configs\(qs)")
    }
    static func createAIConfig(_ data: AIServiceConfigCreateRequest) async throws -> AIServiceConfig {
        try await APIClient.shared.request("POST", "/ai-configs", body: data)
    }
    static func updateAIConfig(_ id: Int, _ data: AIServiceConfigUpdateRequest) async throws -> AIServiceConfig {
        try await APIClient.shared.request("PUT", "/ai-configs/\(id)", body: data)
    }
    static func deleteAIConfig(_ id: Int) async throws -> EmptyResponse {
        try await APIClient.shared.request("DELETE", "/ai-configs/\(id)")
    }
    static func testAIConfig(_ data: AIConfigTestRequest) async throws -> AIConfigTestResult {
        try await APIClient.shared.request("POST", "/ai-configs/test", body: data)
    }
    static func huobaoPreset(apiKey: String) async throws -> [AIServiceConfig] {
        try await APIClient.shared.request("POST", "/ai-configs/huobao-preset", body: ["api_key": apiKey])
    }

    // MARK: - Agent Config
    static func listAgentConfigs() async throws -> [AgentConfig] {
        try await APIClient.shared.request("GET", "/agent-configs")
    }
    static func getAgentConfig(_ id: Int) async throws -> AgentConfig {
        try await APIClient.shared.request("GET", "/agent-configs/\(id)")
    }
    static func createAgentConfig(_ data: AgentConfigCreateRequest) async throws -> AgentConfig {
        try await APIClient.shared.request("POST", "/agent-configs", body: data)
    }
    static func updateAgentConfig(_ id: Int, _ data: AgentConfigCreateRequest) async throws -> AgentConfig {
        try await APIClient.shared.request("PUT", "/agent-configs/\(id)", body: data)
    }
    static func deleteAgentConfig(_ id: Int) async throws -> EmptyResponse {
        try await APIClient.shared.request("DELETE", "/agent-configs/\(id)")
    }

    // MARK: - Skills
    static func listSkills() async throws -> [Skill] {
        try await APIClient.shared.request("GET", "/skills")
    }
    static func getSkill(_ id: String) async throws -> Skill {
        try await APIClient.shared.request("GET", "/skills/\(id)")
    }
    static func createSkill(_ data: SkillCreateRequest) async throws -> Skill {
        try await APIClient.shared.request("POST", "/skills", body: data)
    }
    static func updateSkill(_ id: String, content: String) async throws -> Skill {
        try await APIClient.shared.request("PUT", "/skills/\(id)", body: ["content": content])
    }
    static func deleteSkill(_ id: String) async throws -> EmptyResponse {
        try await APIClient.shared.request("DELETE", "/skills/\(id)")
    }

    // MARK: - Voices
    static func listVoices(provider: String? = nil) async throws -> [VoiceProfile] {
        let qs = provider.map { "?provider=\($0)" } ?? ""
        return try await APIClient.shared.request("GET", "/ai-voices\(qs)")
    }
    static func syncVoices() async throws -> [VoiceProfile] {
        try await APIClient.shared.request("POST", "/ai-voices/sync", body: [:] as [String: String])
    }

    // MARK: - Agent Chat
    static func agentChat(type: String, message: String, dramaId: Int, episodeId: Int) async throws -> AgentChatResult {
        try await APIClient.shared.request("POST", "/agent/\(type)/chat", body: [
            "message": message,
            "drama_id": dramaId,
            "episode_id": episodeId,
        ])
    }
}
```

### 3.3 轮询协调器

```swift
@MainActor
final class PollingCoordinator {
    private var task: Task<Void, Never>?

    func start(interval: Duration = .seconds(3), tick: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                await tick()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
```

说明：

- 用于图片、视频、合成、拼接状态刷新
- 不承担 Agent token 级流式输出
- 如果后端未来增加 SSE，再在此层之上扩展，不作为当前基线

### 3.4 请求/响应辅助类型

```swift
// 以下类型放在各自的 Model 文件或集中放在 APIRequestTypes.swift

// MARK: - Request Types

struct DramaCreateRequest: Encodable {
    let title: String
    let style: String?
    let totalEpisodes: Int?
    enum CodingKeys: String, CodingKey {
        case title, style
        case totalEpisodes = "total_episodes"
    }
}

struct DramaUpdateRequest: Encodable {
    let title: String?
    let style: String?
}

struct EpisodeCreateRequest: Encodable {
    let dramaId: Int
    let title: String?
    let imageConfigId: Int?
    let videoConfigId: Int?
    let audioConfigId: Int?
    enum CodingKeys: String, CodingKey {
        case title
        case dramaId = "drama_id"
        case imageConfigId = "image_config_id"
        case videoConfigId = "video_config_id"
        case audioConfigId = "audio_config_id"
    }
}

struct EpisodeUpdateRequest: Encodable {
    let content: String?
    let scriptContent: String?
    enum CodingKeys: String, CodingKey {
        case content
        case scriptContent = "script_content"
    }
}

struct CharacterUpdateRequest: Encodable {
    let voiceStyle: String?
    enum CodingKeys: String, CodingKey {
        case voiceStyle = "voice_style"
    }
}

struct StoryboardUpdateRequest: Encodable {
    let title: String?
    let description: String?
    let shotType: String?
    let angle: String?
    let movement: String?
    let location: String?
    let time: String?
    let duration: Int?
    let action: String?
    let result: String?
    let atmosphere: String?
    let dialogue: String?
    let imagePrompt: String?
    let videoPrompt: String?
    let bgmPrompt: String?
    let soundEffect: String?
    let sceneId: Int?
    let characterIds: [Int]?
    enum CodingKeys: String, CodingKey {
        case title, description, angle, movement, location, time, duration
        case action, result, atmosphere, dialogue
        case shotType = "shot_type"
        case imagePrompt = "image_prompt"
        case videoPrompt = "video_prompt"
        case bgmPrompt = "bgm_prompt"
        case soundEffect = "sound_effect"
        case sceneId = "scene_id"
        case characterIds = "character_ids"
    }
}

struct StoryboardCreateRequest: Encodable {
    let episodeId: Int
    let title: String?
    let description: String?
    enum CodingKeys: String, CodingKey {
        case title, description
        case episodeId = "episode_id"
    }
}

struct AIServiceConfigCreateRequest: Encodable {
    let name: String?
    let provider: String
    let apiKey: String?
    let baseUrl: String?
    let model: String?
    let serviceType: String
    let priority: Int?
    enum CodingKeys: String, CodingKey {
        case name, provider, model, priority
        case apiKey = "api_key"
        case baseUrl = "base_url"
        case serviceType = "service_type"
    }
}

struct AIServiceConfigUpdateRequest: Encodable {
    let name: String?
    let provider: String?
    let apiKey: String?
    let baseUrl: String?
    let model: String?
    let serviceType: String?
    let priority: Int?
    let isActive: Bool?
    enum CodingKeys: String, CodingKey {
        case name, provider, model, priority
        case apiKey = "api_key"
        case baseUrl = "base_url"
        case serviceType = "service_type"
        case isActive = "is_active"
    }
}

struct AIConfigTestRequest: Encodable {
    let serviceType: String
    let provider: String
    let apiKey: String
    let baseUrl: String
    let model: String
}

struct AgentConfigCreateRequest: Encodable {
    let agentType: String
    let model: String?
    let temperature: Double?
    let maxTokens: Int?
    let systemPrompt: String?
    enum CodingKeys: String, CodingKey {
        case model, temperature
        case agentType = "agent_type"
        case maxTokens = "max_tokens"
        case systemPrompt = "system_prompt"
    }
}

struct SkillCreateRequest: Encodable {
    let id: String
    let name: String
    let description: String?
}

struct ImageGenerateRequest: Encodable { /* 根据后端定义 */ }
struct GridPromptRequest: Encodable { /* 根据后端定义 */ }
struct GridGenerateRequest: Encodable { /* 根据后端定义 */ }
struct GridSplitRequest: Encodable { /* 根据后端定义 */ }
struct VideoGenerateRequest: Encodable { /* 根据后端定义 */ }

// MARK: - Response Types

struct EmptyResponse: Decodable {}
struct PipelineStatus: Decodable { /* 根据后端定义 */ }
struct ImageResult: Decodable { /* 根据后端定义 */ }
struct GridPromptResult: Decodable { /* 根据后端定义 */ }
struct GridGenerateResult: Decodable { /* 根据后端定义 */ }
struct GridStatusResult: Decodable { /* 根据后端定义 */ }
struct GridSplitResult: Decodable { /* 根据后端定义 */ }
struct VideoResult: Decodable { /* 根据后端定义 */ }
struct ComposeResult: Decodable { /* 根据后端定义 */ }
struct ComposeStatusResult: Decodable { /* 根据后端定义 */ }
struct MergeResult: Decodable {
    let mergedUrl: String?
    enum CodingKeys: String, CodingKey {
        case mergedUrl = "merged_url"
    }
}
struct AIConfigTestResult: Decodable {
    let reachable: Bool
    let status: String?
    let message: String?
    let url: String?
    let method: String?
    let responsePreview: String?
    enum CodingKeys: String, CodingKey {
        case reachable, status, message, url, method
        case responsePreview = "response_preview"
    }
}
struct AgentChatResult: Decodable { /* 根据后端定义 */ }
```

---

## 4. ViewModel 层

### 4.1 ViewModel 职责划分

| ViewModel | 对应前端页面 | 职责 |
|-----------|-------------|------|
| `DramaListViewModel` | `pages/index.vue` | 项目列表 CRUD |
| `DramaDetailViewModel` | `pages/drama/[id]/index.vue` | 剧集管理、添加集 |
| `StudioViewModel` | episode 页面的总协调 | 工作台数据加载、流水线步骤管理 |
| `ScriptPanelViewModel` | episode 页面 script panel | 剧本编辑、Agent 调用（改写/提取/音色/分镜） |
| `ProductionPanelViewModel` | episode 页面 production panel | 角色/场景/配音/帧图/视频/合成管理 |
| `GridToolViewModel` | episode 页面 Grid 对话框 | Grid 宫格图工具完整流程 |
| `SettingsViewModel` | `pages/settings.vue` | AI 配置、Agent 配置、Skills |
| `AgentConfigViewModel` | Settings 的 Agent 配置部分 | Agent 折叠编辑 |

### 4.2 StudioViewModel 示例

```swift
// StudioViewModel.swift
@Observable
final class StudioViewModel {
    // MARK: - State
    var drama: Drama?
    var episode: Episode?
    var characters: [Character] = []
    var scenes: [Scene] = []
    var storyboards: [Storyboard] = []
    var mergeData: MergeResult?

    var isLoading = false
    var errorMessage: String?

    // MARK: - Pipeline Navigation
    var activePanel: StudioPanel = .script
    var scriptStep: PipelineStep = .rawContent
    var productionTab: ProductionTab = .chars

    // MARK: - Selection
    var selectedStoryboard: Storyboard?

    // MARK: - Agent Running State
    var isAgentRunning = false
    var runningAgentType: String?

    // MARK: - Computed
    var pipelineProgress: Int {
        var progress = 0
        if episode?.content?.isEmpty == false { progress += 1 }
        if episode?.scriptContent?.isEmpty == false { progress += 1 }
        if !characters.isEmpty { progress += 1 }
        if characters.filter({ $0.voiceStyle != nil }).count > 0 { progress += 1 }
        if !storyboards.isEmpty { progress += 1 }
        let imgReady = storyboards.filter { $0.firstFrameImage != nil }.count
        progress += min(1, imgReady)  // 首帧
        let vidReady = storyboards.filter { $0.videoUrl != nil }.count
        progress += min(1, vidReady)  // 视频
        let ttsReady = storyboards.filter { $0.audioUrl != nil }.count
        progress += min(1, ttsReady)  // 配音
        let composedReady = storyboards.filter { $0.composedVideoUrl != nil }.count
        progress += min(1, composedReady)  // 合成
        if mergeData?.mergedUrl != nil { progress += 1 }  // 导出
        // 总计 11
        return progress
    }

    // MARK: - Load
    func load(dramaId: Int, episodeNumber: Int) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let dramaTask = APIEndpoints.getDrama(dramaId)
            if let drama = try await dramaTask {
                self.drama = drama
                self.episode = drama.episodes?.first { $0.episodeNumber == episodeNumber }
            }

            guard let epId = episode?.id else { return }

            async let charsTask = APIEndpoints.getCharacters(episodeId: epId)
            async let scenesTask = APIEndpoints.getScenes(episodeId: epId)
            async let sbsTask = APIEndpoints.getStoryboards(episodeId: epId)
            async let mergeTask = APIEndpoints.mergeStatus(episodeId: epId)

            let (chars, scns, sbs, merge) = try await (charsTask, scenesTask, sbsTask, mergeTask)
            self.characters = chars
            self.scenes = scns
            self.storyboards = sbs
            self.mergeData = merge
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        guard let dramaId = drama?.id, let epNumber = episode?.episodeNumber else { return }
        await load(dramaId: dramaId, episodeNumber: epNumber)
    }

    // MARK: - Agent Calls
    func runAgent(_ type: String, message: String) async {
        guard !isAgentRunning else { return }
        guard let dramaId = drama?.id, let episodeId = episode?.id else { return }

        isAgentRunning = true
        runningAgentType = type
        defer {
            isAgentRunning = false
            runningAgentType = nil
        }

        do {
            _ = try await APIEndpoints.agentChat(
                type: type, message: message,
                dramaId: dramaId, episodeId: episodeId
            )
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum StudioPanel: String {
    case script, production, export
}
```

### 4.3 GridToolViewModel 示例

```swift
// GridToolViewModel.swift
@Observable
final class GridToolViewModel {
    // MARK: - Config
    var mode: GridMode = .firstFrame
    var layout: GridLayout = .threeByThree
    var selectedShotIds: Set<Int> = []
    var singleTargetId: Int?

    // MARK: - Flow State
    var step: GridStep = .config
    var isGeneratingPrompt = false
    var isGeneratingImage = false
    var promptText: String?
    var promptSource: String?
    var cellPrompts: [GridCellPrompt] = []
    var generatedImagePath: String?
    var generatedLayout: (rows: Int, cols: Int) = (3, 3)
    var statusText: String?

    // MARK: - Assignments
    var assignments: [GridAssignment] = []
    var activeCellIndex: Int = 0
    var assignmentPage: Int = 0

    // MARK: - History
    var history: [GridHistoryItem] = []

    // MARK: - Computed
    var canStart: Bool {
        if mode == .multiRef { return singleTargetId != nil }
        return !selectedShotIds.isEmpty
    }

    // MARK: - Actions
    func generatePrompt(episodeId: Int) async { /* ... */ }
    func startGeneration(episodeId: Int) async { /* ... */ }
    func pollStatus(id: Int) async { /* ... */ }
    func split(episodeId: Int) async { /* ... */ }
    func reset() { /* ... */ }
}

enum GridStep: Int {
    case config = 0, prompt, generating, preview, done
}

struct GridCellPrompt {
    let shotNumber: Int
    let frameType: String
    let prompt: String
}

struct GridAssignment {
    let index: Int
    var storyboardId: Int?
    var frameType: FrameType?
}

struct GridHistoryItem: Identifiable {
    let id: Int
    let localPath: String
    let layout: (rows: Int, cols: Int)
    let modeLabel: String
    let createdAtLabel: String
}
```

---

## 5. 视图层 (Views)

### 5.1 导航架构

```swift
// HuobaoDramaApp.swift
@main
struct HuobaoDramaApp: App {
    var body: some Scene {
        WindowGroup {
            AppContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 800)

        Settings {
            SettingsView()
        }
    }
}

// Router.swift — 使用 NavigationStack + path
@Observable
final class Router {
    var path = NavigationPath()

    func navigate(to route: Route) {
        path.append(route)
    }

    func pop() {
        path.removeLast()
    }

    func popToRoot() {
        path.removeLast(path.count)
    }
}

enum Route: Hashable {
    case dramaDetail(dramaId: Int)
    case studio(dramaId: Int, episodeNumber: Int)
}

// AppContentView.swift
struct AppContentView: View {
    @State private var router = Router()

    var body: some View {
        NavigationStack(path: $router.path) {
            DramaListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .dramaDetail(let id):
                        DramaDetailView(dramaId: id)
                    case .studio(let dramaId, let episodeNumber):
                        StudioView(dramaId: dramaId, episodeNumber: episodeNumber)
                    }
                }
        }
        .environment(router)
    }
}
```

### 5.2 工作台布局

```swift
// StudioView.swift — 核心页面布局
struct StudioView: View {
    let dramaId: Int
    let episodeNumber: Int

    @State private var vm = StudioViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Topbar
            StudioTopbar(vm: vm)

            // Body: Sidebar + Main
            HSplitView {
                // Left Sidebar (~220pt)
                PipelineSidebar(vm: vm)
                    .frame(minWidth: 200, maxWidth: 240)

                // Right Main Content
                mainContent
            }

            // Bottom Step Navigation (条件显示)
            if vm.activePanel != .export {
                StepBubbleBar(vm: vm)
            }
        }
        .task {
            await vm.load(dramaId: dramaId, episodeNumber: episodeNumber)
        }
        .sheet(isPresented: $vm.showGridTool) {
            GridToolSheet(vm: vm)
        }
        .sheet(isPresented: $vm.showImageViewer) {
            ImageViewer(url: vm.imageViewerURL, title: vm.imageViewerTitle)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            // Sub-navigation
            if vm.activePanel == .script {
                scriptSubnav
            }

            // Content
            Group {
                switch vm.activePanel {
                case .script:
                    ScriptPanel(vm: vm)
                case .production:
                    ProductionPanel(vm: vm)
                case .export:
                    ExportPanel(vm: vm)
                }
            }
        }
    }
}
```

### 5.3 Pipeline 侧边栏

```swift
// PipelineSidebar.swift
struct PipelineSidebar: View {
    let vm: StudioViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 剧本区段
            sidebarSection("剧本") {
                ForEach(PipelineStep.allCases, id: \.rawValue) { step in
                    sidebarItem(
                        step.stepNumber,
                        label: step.label,
                        isDone: isStepDone(step),
                        isActive: vm.activePanel == .script && vm.scriptStep == step
                    ) {
                        vm.activePanel = .script
                        vm.scriptStep = step
                    }
                }
            }

            Divider().padding(.vertical, 8)

            // 制作区段
            sidebarSection("制作") {
                ForEach(ProductionTab.allCases, id: \.rawValue) { tab in
                    sidebarItem(
                        tab.icon,
                        label: tab.label,
                        isDone: isTabDone(tab),
                        isActive: vm.activePanel == .production && vm.productionTab == tab
                    ) {
                        vm.activePanel = .production
                        vm.productionTab = tab
                    }
                }
            }

            Divider().padding(.vertical, 8)

            // 导出
            sidebarItem(
                "arrow.down.doc",
                label: "导出",
                isDone: vm.mergeData?.mergedUrl != nil,
                isActive: vm.activePanel == .export
            ) {
                vm.activePanel = .export
            }

            Spacer()

            // 底部进度条
            progressBar
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("制作进度")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(vm.pipelineProgress)/11")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(vm.pipelineProgress), total: 11)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
```

### 5.4 页面-前端对应关系

| SwiftUI View | 前端 Vue 文件 | 说明 |
|-------------|-------------|------|
| `DramaListView` | `pages/index.vue` | 项目列表网格 |
| `DramaDetailView` | `pages/drama/[id]/index.vue` | 剧集列表 |
| `AddEpisodeSheet` | 上述页面中的模态框 | 创建新集（锁定配置） |
| `StudioView` | `pages/drama/[id]/episode/[episodeNumber].vue` | 工作台主容器 |
| `StudioTopbar` | 上述页面 `<header class="studio-topbar">` | 顶栏 |
| `PipelineSidebar` | 上述页面 `<aside class="sidebar">` | 左侧流水线 |
| `ScriptPanel` | 上述页面 `panel === 'script'` | 剧本面板容器 |
| `RawContentStep` | 上述页面 `scriptStep === 0` | 步骤01 原始内容 |
| `ScriptRewriteStep` | 上述页面 `scriptStep === 1` | 步骤02 AI改写 |
| `ExtractStep` | 上述页面 `scriptStep === 2` | 步骤03 提取角色场景 |
| `VoiceAssignStep` | 上述页面 `scriptStep === 3` | 步骤04 分配音色 |
| `StoryboardStep` | 上述页面 `scriptStep === 4` | 步骤05 分镜列表 |
| `StoryboardDetailPanel` | 上述页面 `detail-panel` | 分镜详情编辑 |
| `ProductionPanel` | 上述页面 `panel === 'production'` | 制作面板容器 |
| `CharactersSubpanel` | 上述页面 `prodTab === 'chars'` | 角色形象 |
| `ScenesSubpanel` | 上述页面 `prodTab === 'scenes'` | 场景图片 |
| `DubbingSubpanel` | 上述页面 `prodTab === 'dubbing'` | 配音 |
| `ShotsSubpanel` | 上述页面 `prodTab === 'shots'` | 帧图 |
| `VideosSubpanel` | 上述页面 `prodTab === 'videos'` | 视频 |
| `ComposeSubpanel` | 上述页面 `prodTab === 'compose'` | 合成 |
| `GridToolSheet` | 上述页面 `gridDialog` | Grid宫格图工具 |
| `ExportPanel` | 上述页面 `panel === 'export'` | 导出拼接 |
| `StepBubbleBar` | 上述页面 `showBottomBubble` | 底部步骤导航 |
| `ImageViewer` | 上述页面 `imageViewer` | 图片全屏预览 |
| `SettingsView` | `pages/settings.vue` | 设置页 |
| `AIServiceConfigSection` | 上述页面 `tab === 'ai'` | AI服务配置 |
| `AIServiceConfigSheet` | 上述页面 `cfgDialog` 模态框 | 配置编辑对话框 |
| `HuobaoPresetSheet` | 上述页面 `presetDialog` 模态框 | 火宝一键配置 |
| `AgentConfigSection` | 上述页面 `tab === 'agents'` | Agent配置 |
| `SkillsSection` | 上述页面 `tab === 'skills'` | Skills管理 |
| `SkillEditSheet` | 上述页面 `addSkillDialog` 模态框 | Skill编辑 |
| `SearchablePicker` | `components/BaseSelect.vue` | 通用下拉选择器 |
| `TagView` | CSS `.tag` | 标签 |
| `StatusDot` | CSS `.dot` | 状态圆点 |
| `EmptyStateView` | CSS `.step-empty` | 空状态 |
| `CardView` | CSS `.card` | 卡片容器 |

---

## 6. 设计系统 (DesignSystem)

### 6.1 色彩映射

```swift
// Colors.swift
import SwiftUI

extension Color {
    // MARK: - 背景
    static let appBackground   = Color(hex: "F3F6FB")  // --bg-base
    static let bg0             = Color(hex: "FFFFFF")  // --bg-0
    static let bg1             = Color(hex: "F8FBFF")  // --bg-1
    static let bg2             = Color(hex: "EEF3F9")  // --bg-2
    static let bg3             = Color(hex: "D7E0EC")  // --bg-3
    static let bgHover         = Color(hex: "F1F5FB")  // --bg-hover
    static let bgInput         = Color(hex: "FCFDFF")  // --bg-input

    // MARK: - 边框
    static let border          = Color(hex: "DBE4F0")  // --border
    static let borderStrong    = Color(hex: "BCC9D9")  // --border-strong
    static let borderFocus     = Color(hex: "3F6FD9")  // --border-focus

    // MARK: - 文字
    static let text0           = Color(hex: "182132")  // --text-0
    static let text1           = Color(hex: "2C3850")  // --text-1
    static let text2           = Color(hex: "60718A")  // --text-2
    static let text3           = Color(hex: "8FA0B8")  // --text-3

    // MARK: - 强调
    static let accent          = Color(hex: "4C7DFF")  // --accent
    static let accentDark      = Color(hex: "355FCE")  // --accent-dark
    static let accentBg        = Color(hex: "4C7DFF").opacity(0.1)

    // MARK: - 状态
    static let success         = Color(hex: "3F8A63")
    static let error           = Color(hex: "D24F66")
    static let info            = Color(hex: "3A73CC")
    static let warning         = Color(hex: "A67B2D")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
```

### 6.2 字体映射

```swift
// Typography.swift
import SwiftUI

extension Font {
    static let display = Font.system(.title, design: .serif)       // Noto Serif SC 替代
    static let body    = Font.system(.body, design: .default)       // DM Sans 替代
    static let mono    = Font.system(.body, design: .monospaced)    // SF Mono
    static let displayLarge = Font.system(size: 26, weight: .bold, design: .serif)
    static let displayTitle = Font.system(size: 19, weight: .bold, design: .serif)
}
```

### 6.3 阴影

```swift
// Shadows.swift
import SwiftUI

extension ShapeStyle where Self == AnyShapeStyle {
    static var shadowXS: some ShadowStyle { .shadow(color: .black.opacity(0.05), radius: 1, y: 1) }
    static var shadowSM: some ShadowStyle { .shadow(color: .black.opacity(0.08), radius: 3, y: 1) }
    static var shadowMD: some ShadowStyle { .shadow(color: .black.opacity(0.1), radius: 8, y: 2) }
    static var shadowLG: some ShadowStyle { .shadow(color: .black.opacity(0.13), radius: 14, y: 4) }
}

// 使用方式
// .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
```

### 6.4 间距与圆角

```swift
// Spacing.swift
// 直接使用 SwiftUI 的 .padding() 系统
// 4/8/12/16/20/24/32/40/48

// DesignTokens.swift
enum DesignTokens {
    static let radiusSmall: CGFloat = 4
    static let radiusDefault: CGFloat = 8
    static let radiusLarge: CGFloat = 14
    static let radiusXL: CGFloat = 20

    static let sidebarWidth: CGFloat = 220
    static let topbarHeight: CGFloat = 56

    static let animationEaseOut: Animation = .easeOut(duration: 0.22)
}
```

---

## 7. 原生增强功能

以下功能是 macOS 客户端相对 Web 更适合承载的增强能力：

### 7.1 连接诊断与环境切换

- 显示当前 backend base URL
- 测试 `/api/v1/health` 连通性
- 支持快速切换本机/远端后端地址
- 记录最近成功连接地址

### 7.2 文件导出

```swift
@MainActor
final class DownloadExportService {
    func exportResource(path: String, suggestedName: String) async throws {
        let tempURL = try await APIClient.shared.download(path: path)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try FileManager.default.copyItem(at: tempURL, to: destination)
    }
}
```

### 7.3 系统级集成

```swift
// AppDelegate.swift — 菜单栏、连接诊断入口
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
    }

    private func setupMainMenu() {
        let menu = NSMenu()

        let fileMenu = NSMenuItem()
        fileMenu.submenu = NSMenu(title: "文件")
        fileMenu.submenu?.addItem(NSMenuItem(title: "新建项目", action: nil, keyEquivalent: "n"))
        fileMenu.submenu?.addItem(NSMenuItem(title: "设置", action: nil, keyEquivalent: ","))

        let toolMenu = NSMenuItem()
        toolMenu.submenu = NSMenu(title: "工具")
        toolMenu.submenu?.addItem(NSMenuItem(title: "连接诊断", action: nil, keyEquivalent: ""))

        menu.items = [fileMenu, toolMenu]
        NSApp.mainMenu = menu
    }
}
```

---

## 8. Agent 分工方案

以下将整个迁移工作拆分为独立的 Agent 任务，每个任务有明确的输入/输出边界。

### 8.1 任务总览

| Agent | 任务名 | 涉及文件 | 依赖 | 预估规模 |
|-------|--------|----------|------|----------|
| A | 基础框架 + 数据模型 + API层 | App/, Models/, Services/ | 无 | ~1500行 |
| B | 设计系统 + 公共组件 | DesignSystem/, Views/Common/ | 无 | ~800行 |
| C | 项目列表 + 剧集详情 | Views/DramaList/, Views/DramaDetail/, VMs | A, B | ~600行 |
| D | 设置页 | Views/Settings/, VMs | A, B | ~800行 |
| E | 工作台框架 + 剧本面板 | Views/Studio/(框架), VMs | A, B | ~1200行 |
| F | 工作台-制作面板 | Views/Studio/(production) | A, B, E | ~1500行 |
| G | Grid宫格图工具 | GridToolSheet, GridToolVM | A, B, E | ~800行 |
| H | 原生增强 + 集成测试 | ConnectionSettings/Export/Tests | A | ~400行 |

### 8.2 各 Agent 详细任务

#### Agent A：基础框架 + 数据模型 + API层

**产出文件**:
```
HuobaoDrama/App/HuobaoDramaApp.swift
HuobaoDrama/App/Router.swift
HuobaoDrama/Models/*.swift         (全部模型)
HuobaoDrama/Services/APIClient.swift
HuobaoDrama/Services/APIEndpoints.swift
HuobaoDrama/Services/ConnectionSettingsStore.swift
HuobaoDrama/Services/PollingCoordinator.swift
HuobaoDrama/Services/DownloadExportService.swift
```

**规范**:
- 所有 Model 使用 `Codable`，CodingKeys 映射 snake_case ↔ camelCase
- APIClient 使用 `actor` 保证线程安全
- APIEndpoints 使用 `enum` 命名空间（无实例）
- 任务状态刷新统一通过轮询协调器，不假设 SSE

#### Agent B：设计系统 + 公共组件

**产出文件**:
```
HuobaoDrama/DesignSystem/Colors.swift
HuobaoDrama/DesignSystem/Typography.swift
HuobaoDrama/DesignSystem/Spacing.swift
HuobaoDrama/DesignSystem/Shadows.swift
HuobaoDrama/DesignSystem/DesignTokens.swift
HuobaoDrama/Views/Common/SearchablePicker.swift
HuobaoDrama/Views/Common/CardView.swift
HuobaoDrama/Views/Common/TagView.swift
HuobaoDrama/Views/Common/StatusDot.swift
HuobaoDrama/Views/Common/LoadingOverlay.swift
HuobaoDrama/Views/Common/EmptyStateView.swift
HuobaoDrama/Views/Common/ImageViewer.swift
HuobaoDrama/Views/Common/AudioPlayerView.swift
HuobaoDrama/Views/Common/VideoPlayerView.swift
HuobaoDrama/Views/Common/StepBubbleBar.swift
HuobaoDrama/Views/Common/ModalSheet.swift
```

**规范**:
- 颜色值严格映射自 `studio.css` 中的 CSS Variables
- SearchablePicker 对应 BaseSelect.vue 的全部功能（搜索、键盘导航、分组）
- 所有组件支持 Light/Dark 模式
- 统一使用 `@Binding` / 闭包 回调数据

#### Agent C：项目列表 + 剧集详情

**产出文件**:
```
HuobaoDrama/Views/DramaList/DramaListView.swift
HuobaoDrama/ViewModels/DramaListViewModel.swift
HuobaoDrama/Views/DramaDetail/DramaDetailView.swift
HuobaoDrama/Views/DramaDetail/AddEpisodeSheet.swift
HuobaoDrama/ViewModels/DramaDetailViewModel.swift
```

**功能清单**:
- DramaListView: 网格卡片、创建/删除项目、骨架屏、空状态
- DramaDetailView: 剧集列表、添加新集（配置锁定三选）
- 时间格式化（X分钟前/小时前/天前）

#### Agent D：设置页

**产出文件**:
```
HuobaoDrama/Views/Settings/SettingsView.swift
HuobaoDrama/Views/Settings/AIServiceConfigSection.swift
HuobaoDrama/Views/Settings/AIServiceConfigSheet.swift
HuobaoDrama/Views/Settings/HuobaoPresetSheet.swift
HuobaoDrama/Views/Settings/AgentConfigSection.swift
HuobaoDrama/Views/Settings/SkillsSection.swift
HuobaoDrama/Views/Settings/SkillEditSheet.swift
HuobaoDrama/ViewModels/SettingsViewModel.swift
```

**功能清单**:
- SettingsView: 左侧导航 + 右侧内容
- AI 服务配置: 4类列表、创建/编辑/删除/启用/禁用、测试、火宝预设
- Agent 配置: 5个Agent折叠卡片、模型选择、参数编辑、提示词编辑
- Skills: Agent列表切换、Skill CRUD、Markdown编辑

#### Agent E：工作台框架 + 剧本面板

**产出文件**:
```
HuobaoDrama/Views/Studio/StudioView.swift
HuobaoDrama/Views/Studio/StudioTopbar.swift
HuobaoDrama/Views/Studio/PipelineSidebar.swift
HuobaoDrama/Views/Studio/ScriptPanel.swift
HuobaoDrama/Views/Studio/RawContentStep.swift
HuobaoDrama/Views/Studio/ScriptRewriteStep.swift
HuobaoDrama/Views/Studio/ExtractStep.swift
HuobaoDrama/Views/Studio/VoiceAssignStep.swift
HuobaoDrama/Views/Studio/StoryboardStep.swift
HuobaoDrama/Views/Studio/StoryboardDetailPanel.swift
HuobaoDrama/Views/Studio/StepNavigationView.swift
HuobaoDrama/ViewModels/StudioViewModel.swift
HuobaoDrama/ViewModels/ScriptPanelViewModel.swift
```

**功能清单**:
- StudioView: HSplitView 布局（侧边栏 + 主内容）
- PipelineSidebar: 三段式（剧本/制作/导出）+ 进度条
- ScriptPanel: 5步子视图切换
- RawContentStep: TextEditor + 保存 + 字数统计
- ScriptRewriteStep: Agent调用 + 跳过 + 重写
- ExtractStep: Agent调用 + 角色/场景结果面板
- VoiceAssignStep: Agent调用 + 音色选择 + 试听生成
- StoryboardStep: 镜头列表 + 详情编辑面板（14+ 字段）
- StepBubbleBar: 底部步骤导航

#### Agent F：工作台-制作面板

**产出文件**:
```
HuobaoDrama/Views/Studio/ProductionPanel.swift
HuobaoDrama/Views/Studio/CharactersSubpanel.swift
HuobaoDrama/Views/Studio/ScenesSubpanel.swift
HuobaoDrama/Views/Studio/DubbingSubpanel.swift
HuobaoDrama/Views/Studio/ShotsSubpanel.swift
HuobaoDrama/Views/Studio/VideosSubpanel.swift
HuobaoDrama/Views/Studio/ComposeSubpanel.swift
HuobaoDrama/Views/Studio/ExportPanel.swift
HuobaoDrama/ViewModels/ProductionPanelViewModel.swift
```

**功能清单**:
- 6个子面板Tab切换
- CharactersSubpanel: 角色图网格、单张/批量生成、pending 态
- ScenesSubpanel: 场景图网格、单张/批量生成
- DubbingSubpanel: TTS列表、单条/批量生成、audio 播放
- ShotsSubpanel: 帧图网格（首帧/尾帧）、单帧生成、Grid入口
- VideosSubpanel: 视频网格、视频播放、批量生成、失败信息
- ComposeSubpanel: 合成列表、单条/批量合成、状态轮询
- ExportPanel: 全集拼接、视频播放、下载
- 异步任务 pending 管理（5个 pending 列表）

#### Agent G：Grid宫格图工具

**产出文件**:
```
HuobaoDrama/Views/Studio/GridToolSheet.swift
HuobaoDrama/ViewModels/GridToolViewModel.swift
```

**功能清单**:
- 5步流程（配置→提示词→生成→切分→完成）
- Grid模式选择（首帧/首尾帧/多参考）
- 宫格布局选择（2x2~5x5）
- 镜头选择列表（全选/取消全选）
- AI提示词生成 + 预览
- 宫格图生成 + 状态轮询
- 格子→镜头分配映射（分页管理）
- 切分执行
- 历史宫格图管理
- GridAssignment 分页

#### Agent H：原生增强 + 集成测试

**产出文件**:
```
HuobaoDrama/Services/DownloadExportService.swift
HuobaoDrama/Views/Settings/ConnectionDiagnosticsSection.swift
HuobaoDrama/App/AppDelegate.swift
HuobaoDramaTests/Services/APIClientTests.swift
HuobaoDramaTests/Services/ConnectionSettingsStoreTests.swift
HuobaoDramaTests/ViewModels/DramaListViewModelTests.swift
```

**功能清单**:
- 下载导出图片/音频/视频
- 后端连接诊断
- 菜单栏集成
- base URL 持久化
- APIClient 单元测试
- ConnectionSettingsStore 单元测试

### 8.3 Agent 执行顺序

```
Phase 1（并行）:
  Agent A ─── 基础框架 + Models + Services
  Agent B ─── 设计系统 + 公共组件

Phase 2（并行，依赖 Phase 1 完成）:
  Agent C ─── 项目列表 + 剧集详情
  Agent D ─── 设置页
  Agent E ─── 工作台框架 + 剧本面板

Phase 3（并行，依赖 Phase 2 完成）:
  Agent F ─── 制作面板
  Agent G ─── Grid宫格图工具
  Agent H ─── 原生增强 + 测试
```

### 8.4 Agent 间接口约定

所有 Agent 必须遵守以下接口约定：

1. **Model 层**：Agent A 定义全部 Model，其他 Agent 直接引用
2. **API 层**：Agent A 定义全部 APIEndpoints，其他 Agent 直接调用
3. **ViewModel**：每个 Agent 负责自己的 VM，通过 `@Observable` 暴露状态
4. **公共组件**：Agent B 定义全部通用组件，其他 Agent 引用
5. **资源 URL**：通过 `APIClient.shared.resourceURL(path)` 统一生成
6. **错误提示**：使用 SwiftUI `.alert()` 绑定 ViewModel 的 `errorMessage`
7. **异步状态**：统一使用 `@Observable` 的 `isAgentRunning` + `runningAgentType` 模式

---

## 9. 关键技术决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 为什么不用 AppKit | SwiftUI | macOS 14+ 的 SwiftUI 已经足够成熟，声明式开发效率更高 |
| 为什么不用 Tauri/Electron | 原生 Swift | 面向 macOS 专用客户端，原生分发、窗口与媒体体验更直接 |
| 为什么用 actor 而不是 class | APIClient | 保证网络请求的线程安全，避免 data race |
| 为什么不用 Alamofire | URLSession | 依赖极少，原生足够，减少第三方依赖 |
| 为什么用 HSplitView 而非 NavigationSplitView | Studio 布局 | 工作台需要精确控制侧边栏宽度，HSplitView 更灵活 |
| 为什么 macOS 14+ | @Observable | `@Observable` 宏需要 macOS 14，是 SwiftUI 最优雅的观察模式 |

---

## 10. 迁移风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| SwiftUI 自定义下拉组件复杂 | SearchablePicker 开发成本高 | macOS 14 原生 `.searchable()` + `Menu` 组合可覆盖大部分场景 |
| Grid 工具格子覆盖交互 | overlay + drag手势 | 用 SwiftUI `ZStack` + `GeometryReader` + `LazyVGrid` 实现 |
| 音频播放器定制 | AVPlayer 样式有限 | 用 `AVAudioPlayer` + 自定义 UI，不依赖系统播放器 |
| 视频播放器定制 | 同上 | 用 `AVPlayerView` + `AVPlayerLayer`，NSViewRepresentable 桥接 |
| 字体差异 | Noto Serif SC / DM Sans 不一定安装 | 使用系统字体 `.serif` / `.default` 降级方案，或打包字体资源 |
| 后端 API 字段名不确定 | Model 解析失败 | 根据 `useApi.ts` 中的 snake_case 使用推断，配合 CodingKeys |
