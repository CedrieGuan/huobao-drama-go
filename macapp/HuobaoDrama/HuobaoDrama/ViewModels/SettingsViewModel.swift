import Foundation

enum SettingsTab: String, CaseIterable {
    case ai
    case agents
    case skills
}

struct ServiceTypeMeta {
    let type: String
    let label: String
    let description: String
}

struct AgentDef {
    let type: String
    let label: String
    let icon: String
}

struct PresetCard {
    let serviceType: String
    let label: String
    let provider: String
    let baseUrl: String
    let model: String
}

/// A lightweight template used to pre-fill provider / base URL / model in the edit sheet.
struct ProviderPreset {
    let provider: String
    let label: String
    let baseUrl: String
    let models: [String]
}

/// Toast notification for preset creation results.
struct PresetToast: Equatable {
    enum Kind { case success, error }
    let kind: Kind
    let message: String
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedTab: SettingsTab = .ai
    @Published var showAdvanced = false
    @Published var isLoading = false
    @Published var error: String?

    // Toast state for preset sheet results
    @Published var presetToast: PresetToast?

    // AI Service Configs
    @Published var aiConfigs: [AIServiceConfig] = []
    @Published var aiProviders: [AIServiceProvider] = []
    @Published var testingConfigId: Int?
    @Published var deletingConfigId: Int?

    // Agent Configs
    @Published var agentConfigs: [AgentConfig] = []
    @Published var expandedAgentType: String?

    // Skills
    @Published var skills: [Skill] = []
    @Published var selectedAgentType: String?

    static let agentDefs: [AgentDef] = [
        .init(type: "script_rewriter", label: "剧本改写", icon: "doc.text.fill"),
        .init(type: "extractor", label: "角色场景提取", icon: "magnifyingglass"),
        .init(type: "storyboard_breaker", label: "分镜拆解", icon: "film"),
        .init(type: "voice_assigner", label: "音色分配", icon: "mic"),
        .init(type: "grid_prompt_generator", label: "图片提示词生成", icon: "photo"),
    ]

    static let serviceTypes: [ServiceTypeMeta] = [
        .init(type: "text", label: "文本", description: "剧本改写、角色场景提取、分镜拆解等 Agent 文本能力"),
        .init(type: "image", label: "图片", description: "角色图、场景图、镜头图与首尾帧等静态图像生成"),
        .init(type: "video", label: "视频", description: "镜头视频生成，支持单图、多图和首尾帧模式"),
        .init(type: "audio", label: "音频", description: "角色试听、旁白与对白语音生成"),
    ]

    static let huobaoPresetCards: [PresetCard] = [
        .init(serviceType: "text", label: "文本", provider: "chatfire", baseUrl: "https://api.chatfire.site", model: "gemini-3-pro-preview"),
        .init(serviceType: "image", label: "图片", provider: "gemini", baseUrl: "https://api.chatfire.site", model: "gemini-3-pro-image-preview"),
        .init(serviceType: "video", label: "视频", provider: "volcengine", baseUrl: "https://api.chatfire.site/volcengine", model: "doubao-seedance-1-5-pro-251215"),
        .init(serviceType: "audio", label: "音频", provider: "minimax", baseUrl: "https://api.chatfire.site/minimax", model: "speech-2.8-hd"),
    ]

    // MARK: - Provider Presets (mirrors Nuxt providerPresets)

    static let providerPresets: [String: [String: ProviderPreset]] = [
        "text": [
            "chatfire":   .init(provider: "chatfire",   label: "ChatFire 推荐",   baseUrl: "https://api.chatfire.site",          models: ["gemini-3-pro-preview"]),
            "openrouter": .init(provider: "openrouter",  label: "OpenRouter 推荐", baseUrl: "https://openrouter.ai/api",         models: ["google/gemini-3-flash-preview"]),
            "openai":     .init(provider: "openai",      label: "OpenAI 推荐",     baseUrl: "https://api.openai.com",            models: ["gpt-4.1-mini"]),
        ],
        "image": [
            "chatfire":   .init(provider: "chatfire",   label: "ChatFire 推荐",   baseUrl: "https://api.chatfire.site",          models: ["doubao-seedream-4-5-251128"]),
            "gemini":     .init(provider: "gemini",      label: "Gemini 推荐",     baseUrl: "https://api.chatfire.site",          models: ["gemini-3-pro-image-preview"]),
            "volcengine": .init(provider: "volcengine",  label: "火山推荐",        baseUrl: "https://ark.cn-beijing.volces.com",  models: ["doubao-seedream-4-0-250828"]),
        ],
        "video": [
            "volcengine": .init(provider: "volcengine",  label: "火宝视频",  baseUrl: "https://api.chatfire.site/volcengine", models: ["doubao-seedance-1-5-pro-251215"]),
            "vidu":       .init(provider: "vidu",        label: "Vidu 推荐", baseUrl: "https://api.vidu.com",                 models: ["viduq3-turbo"]),
            "ali":        .init(provider: "ali",         label: "阿里推荐",  baseUrl: "https://dashscope.aliyuncs.com",       models: ["wan2.6-i2v-flash"]),
        ],
        "audio": [
            "minimax":    .init(provider: "minimax",     label: "火宝音频",  baseUrl: "https://api.chatfire.site/minimax",    models: ["speech-2.8-hd"]),
        ],
    ]

    static let endpointPrefixes: [String: String] = [
        "chatfire":   "/v1",
        "openai":     "/v1",
        "openrouter": "/v1",
        "minimax":    "/v1",
        "gemini":     "/v1beta",
        "volcengine": "/api/v3",
        "ali":        "/api/v1",
        "vidu":       "/ent/v2",
    ]

    static let apiKeyHints: [String: String] = [
        "openai":     "以 sk- 开头",
        "chatfire":   "ChatFire 平台 API Key",
        "openrouter": "OpenRouter API Key，以 sk-or- 开头",
        "gemini":     "Google AI API Key",
        "volcengine": "火山引擎 AccessKey",
        "minimax":    "MiniMax API Key",
        "ali":        "阿里云 DashScope API Key",
        "vidu":       "Vidu 平台 API Key",
    ]

    // MARK: - Helpers

    static func presetsForType(_ serviceType: String) -> [ProviderPreset] {
        (providerPresets[serviceType] ?? [:]).values.sorted { $0.provider < $1.provider }
    }

    static func endpointHint(provider: String, baseUrl: String) -> String {
        let base = baseUrl.isEmpty ? "https://..." : baseUrl
        let prefix = endpointPrefixes[provider] ?? ""
        if provider.isEmpty { return "选择服务商后显示推荐端点前缀" }
        return "\(base)\(prefix)"
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            async let configs = APIEndpoints.AIConfigAPI.list()
            async let providers = APIEndpoints.AIConfigAPI.providers()
            async let agents = APIEndpoints.AgentConfigAPI.list()
            async let skillList = APIEndpoints.SkillsAPI.list()
            let (c, p, a, s) = try await (configs, providers, agents, skillList)
            aiConfigs = c
            aiProviders = p
            agentConfigs = a
            skills = s
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func configsByType(_ type: String) -> [AIServiceConfig] {
        aiConfigs.filter { $0.serviceType == type }
    }

    func agentConfig(forType type: String) -> AgentConfig? {
        agentConfigs.first { $0.agentType == type }
    }

    func toggleAgentExpand(_ type: String) {
        withAnimation(Animation.normal) {
            expandedAgentType = expandedAgentType == type ? nil : type
        }
    }

    // MARK: - Text Model Options (for agent model picker)

    /// Flat list of model picker options sourced from active text AI service configs.
    var textModelOptions: [PickerOption] {
        aiConfigs
            .filter { $0.serviceType == "text" && $0.isActive && !$0.apiKey.isEmpty }
            .flatMap { cfg in
                cfg.model.map { m in
                    PickerOption(
                        id: "\(cfg.id)-\(m)",
                        label: "\(cfg.provider ?? cfg.name) — \(m)",
                        value: m
                    )
                }
            }
    }

    // MARK: - Default Prompts

    private static let defaultPrompts: [String: String] = [
        "script_rewriter": """
你是专业编剧，擅长将小说改编为短剧剧本。

工作流程：
1. 调用 read_episode_script 读取原始内容
2. 根据读取到的内容，自己进行改写（输出格式化剧本格式）
3. 调用 save_script 保存改写后的完整剧本

格式化剧本格式：
- 场景头：## S编号 | 内景/外景 · 地点 | 时间段
- 动作描写：自然段落，不包含镜头语言
- 对白：角色名：（状态/表情）台词内容
- 每个场景 30-60 秒内容
""",
        "extractor": """
你是制片助理，擅长从剧本中提取角色和场景信息，并在提取时与项目已有数据进行智能去重。

工作流程：
1. 调用 read_script_for_extraction 读取格式化剧本
2. 调用 read_existing_characters 读取项目中已存在的角色列表（用于去重）
3. 调用 read_existing_scenes 读取项目中已存在的场景列表（用于去重）
4. 分析剧本内容，提取所有角色信息
5. 对每个角色：若同名已存在则合并更新，若不存在则新增
6. 调用 save_dedup_characters 保存角色（去重合并，自动处理新增和更新）
7. 分析剧本内容，提取所有场景信息
8. 对每个场景：若同地点+时间段已存在则复用，若不存在则新增
9. 调用 save_dedup_scenes 保存场景（去重合并，自动处理新增和复用）

去重规则：
- 角色：按名字精确匹配，同名保留现有（合并信息）
- 场景：按【地点+时间段】精确匹配；同地点不同时段视为新场景

提取要求：
- 角色要包含完整的外貌特征描述（发型、服装、体态等）
- 场景要包含光线、色调、氛围等视觉信息
- 不要遗漏任何有台词或重要动作的角色
""",
        "storyboard_breaker": """
你是资深影视分镜师，擅长将剧本拆解为分镜方案。

工作流程：
1. 调用 read_storyboard_context 读取剧本、角色列表、场景列表
2. 将剧本拆解为镜头序列（每个镜头 10-15 秒）
3. 为每个镜头生成视频提示词（video_prompt）
4. 调用 save_storyboards 保存所有分镜
""",
        "voice_assigner": """
你是配音导演，擅长为角色选择合适的音色。

工作流程：
1. 调用 list_voices 获取可用音色列表
2. 调用 get_characters 获取所有角色信息
3. 根据每个角色的性别、性格、年龄、角色定位，选择最匹配的音色
4. 对每个角色调用 assign_voice 分配音色，并说明选择理由

注意：每个角色都必须分配音色，不要遗漏。
""",
        "grid_prompt_generator": """
你是专业的 AI 图像提示词工程师，擅长为角色、场景和宫格图生成高质量的英文提示词。

你将收到用户的请求，告知要生成哪种类型的提示词：
- "角色" → 生成角色图片提示词
- "场景" → 生成场景图片提示词
- "宫格" → 生成宫格图提示词

提示词规范：
- 使用英文提示词
- 必须包含 "consistent art style" 保持风格统一
- 必须包含 "cinematic quality"
- 避免出现文字或水印
"""
    ]

    static func defaultPrompt(forAgent type: String) -> String {
        defaultPrompts[type] ?? ""
    }

    // MARK: - Save Agent Config

    func saveAgentConfig(
        agentType: String,
        model: String?,
        temperature: Double,
        maxTokens: Int,
        systemPrompt: String
    ) async throws {
        let label = agentDefs.first { $0.type == agentType }?.label ?? agentType
        let req = UpsertAgentConfigRequest(
            agentType: agentType,
            name: label,
            model: model,
            systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
            temperature: temperature,
            maxTokens: maxTokens,
            isActive: true
        )

        let existing = agentConfig(forType: agentType)
        if let existing = existing {
            _ = try await APIEndpoints.AgentConfigAPI.update(id: existing.id, req)
        } else {
            _ = try await APIEndpoints.AgentConfigAPI.upsert(req)
        }

        // Reload configs to reflect changes
        agentConfigs = try await APIEndpoints.AgentConfigAPI.list()
    }

    func countActive(_ type: String) -> Int {
        configsByType(type).filter { $0.isActive }.count
    }

    func toggleConfig(_ config: AIServiceConfig) async {
        do {
            let req = UpdateAIServiceConfigRequest(
                name: nil, baseUrl: nil, apiKey: nil, model: nil,
                priority: nil, isActive: !config.isActive, isDefault: nil
            )
            try await APIEndpoints.AIConfigAPI.update(id: config.id, req)
            await reloadConfigs()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteConfig(_ config: AIServiceConfig) async {
        deletingConfigId = config.id
        do {
            try await APIEndpoints.AIConfigAPI.delete(id: config.id)
            aiConfigs.removeAll { $0.id == config.id }
        } catch {
            self.error = error.localizedDescription
        }
        deletingConfigId = nil
    }

    func testConfig(_ config: AIServiceConfig) async -> Bool {
        testingConfigId = config.id
        do {
            try await APIEndpoints.AIConfigAPI.test(
                serviceType: config.serviceType,
                provider: config.provider ?? "",
                baseUrl: config.baseUrl,
                apiKey: config.apiKey,
                model: config.model
            )
            testingConfigId = nil
            return true
        } catch {
            self.error = error.localizedDescription
            testingConfigId = nil
            return false
        }
    }

    private func reloadConfigs() async {
        do {
            aiConfigs = try await APIEndpoints.AIConfigAPI.list()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Huobao Preset

    /// Creates the 4 preset AI service configs + initializes Agent defaults via backend.
    /// Returns `true` on success (caller should dismiss sheet), `false` on failure (keep sheet open).
    func createHuobaoPresets(apiKey: String) async -> Bool {
        do {
            try await APIEndpoints.AIConfigAPI.setupHuobaoPreset(apiKey: apiKey)
            await reloadConfigs()
            presetToast = PresetToast(kind: .success, message: "火宝推荐配置与默认 Agent LLM 已写入")
            return true
        } catch {
            presetToast = PresetToast(kind: .error, message: error.localizedDescription)
            return false
        }
    }

    var baseTabs: [SettingsTab] {
        [.ai]
    }

    var advancedTabs: [SettingsTab] {
        [.agents, .skills]
    }
}
