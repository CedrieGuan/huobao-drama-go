# API 端点文档

> 本文档基于 `APIEndpoints.swift` 自动整理，涵盖 HuobaoDrama 后端全部 API 端点。

---

## 1. 概述

### Base URL 配置

Base URL 通过 `ConnectionSettingsStore` 单例管理，存储在 `UserDefaults` 中。

- **默认值**: `http://localhost:5679`
- **实际 API 前缀**: `{baseURL}/api/v1`
- **配置方式**: 在设置页面修改后端地址，自动去掉末尾斜杠并拼接 `/api/v1`

```swift
// ConnectionSettingsStore.swift
var apiBaseURL: String { baseURL.trimmingCharacters(in: .init(charactersIn: "/")) + "/api/v1" }
```

### 认证方式

当前版本（v1）**无额外认证机制**。所有请求均不携带 `Authorization` 头。

### 通用请求头

| 请求头 | 值 | 说明 |
|--------|----|------|
| `Content-Type` | `application/json` | 所有带请求体的调用自动设置 |

### HTTP 客户端

- 超时时间: **30 秒** (`URLSessionConfiguration.timeoutIntervalForRequest`)
- 并发模型: 所有 API 调用标记为 `@MainActor`
- 单例模式: `APIClient.shared`

---

## 2. 按模块列出 API 端点

### 2.1 Drama（剧本管理）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `list` | GET | `/dramas?page={page}&page_size={pageSize}` | `page: Int = 1`, `pageSize: Int = 20` | `PaginatedResponse<Drama>` | 获取剧本分页列表 |
| `get` | GET | `/dramas/{id}` | `id: Int` (路径参数) | `Drama` | 获取单个剧本详情（含 episodes、characters、scenes） |
| `create` | POST | `/dramas` | `CreateDramaRequest` | `Drama` | 创建新剧本 |
| `update` | PUT | `/dramas/{id}` | `UpdateDramaRequest` | `EmptyData` | 更新剧本信息 |
| `delete` | DELETE | `/dramas/{id}` | `id: Int` (路径参数) | `EmptyData` | 删除剧本 |
| `saveCharacters` | PUT | `/dramas/{dramaId}/characters` | `{ characters: [Character] }` | `EmptyData` | 批量保存剧本角色 |

### 2.2 Episode（集数管理）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `create` | POST | `/episodes` | `CreateEpisodeRequest` | `Episode` | 创建新集数 |
| `update` | PUT | `/episodes/{id}` | `UpdateEpisodeRequest` | `EmptyData` | 更新集数信息 |
| `storyboards` | GET | `/episodes/{episodeId}/storyboards` | `episodeId: Int` (路径参数) | `[Storyboard]` | 获取该集的所有分镜 |
| `characters` | GET | `/episodes/{episodeId}/characters` | `episodeId: Int` (路径参数) | `[Character]` | 获取该集的所有角色 |
| `scenes` | GET | `/episodes/{episodeId}/scenes` | `episodeId: Int` (路径参数) | `[Scene]` | 获取该集的所有场景 |
| `pipelineStatus` | GET | `/episodes/{episodeId}/pipeline-status` | `episodeId: Int` (路径参数) | `PipelineStatus` | 获取制作管线进度 |

### 2.3 Agent（AI 代理）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `chat` | POST (SSE) | `/agent/{agentType}/chat` | `AgentChatRequest` | `AsyncThrowingStream<String, Error>` | 与 AI 代理对话（流式响应） |
| `run` | POST (SSE) | `/agent/{agentType}/run` | `{ episode_id: Int }` | `AsyncThrowingStream<String, Error>` | 运行 AI 代理任务（流式响应） |

**支持的 Agent 类型** (`agentType` 路径参数):

| 枚举值 | 字符串 | 说明 |
|--------|--------|------|
| `scriptRewriter` | `script_rewriter` | 剧本改写 |
| `extractor` | `extractor` | 角色/场景提取 |
| `storyboardBreaker` | `storyboard_breaker` | 分镜拆解 |
| `voiceAssigner` | `voice_assigner` | 音色分配 |
| `gridPromptGenerator` | `grid_prompt_generator` | 图片提示词生成 |

### 2.4 Storyboard（分镜管理）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `create` | POST | `/storyboards` | `CreateStoryboardRequest` | `Storyboard` | 创建分镜 |
| `update` | PUT | `/storyboards/{id}` | `UpdateStoryboardRequest` | `EmptyData` | 更新分镜 |
| `delete` | DELETE | `/storyboards/{id}` | `id: Int` (路径参数) | `EmptyData` | 删除分镜 |

### 2.5 AIConfig（AI 服务配置）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `list` | GET | `/ai-configs` | 无 | `[AIServiceConfig]` | 获取所有 AI 服务配置 |
| `create` | POST | `/ai-configs` | `CreateAIServiceConfigRequest` | `AIServiceConfig` | 创建 AI 服务配置 |
| `update` | PUT | `/ai-configs/{id}` | `UpdateAIServiceConfigRequest` | `EmptyData` | 更新 AI 服务配置 |
| `delete` | DELETE | `/ai-configs/{id}` | `id: Int` (路径参数) | `EmptyData` | 删除 AI 服务配置 |
| `test` | POST | `/ai-configs/test` | `{ service_type, provider, base_url, api_key?, model? }` | `EmptyData` | 测试 AI 服务连通性 |
| `providers` | GET | `/ai-providers` | 无 | `[AIServiceProvider]` | 获取可用的 AI 服务提供商列表 |
| `setupHuobaoPreset` | POST | `/ai-configs/huobao-preset` | `HuobaoPresetRequest` | `EmptyData` | 快速配置火宝预设 AI 服务 |

### 2.6 AgentConfig（代理配置）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `list` | GET | `/agent-configs` | 无 | `[AgentConfig]` | 获取所有代理配置 |
| `upsert` | POST | `/agent-configs` | `UpsertAgentConfigRequest` | `AgentConfig` | 新建或替换代理配置 |
| `update` | PUT | `/agent-configs/{id}` | `UpsertAgentConfigRequest` | `EmptyData` | 更新代理配置 |

### 2.7 Skills（技能管理）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `list` | GET | `/skills` | 无 | `[Skill]` | 获取所有技能 |
| `create` | POST | `/skills` | `{ id, name, description }` | `EmptyData` | 创建技能 |
| `get` | GET | `/skills/{id}` | `id: String` (路径参数) | `Skill` | 获取单个技能详情 |
| `update` | PUT | `/skills/{id}` | `{ content: String }` | `EmptyData` | 更新技能内容 |
| `delete` | DELETE | `/skills/{id}` | `id: String` (路径参数) | `EmptyData` | 删除技能 |

### 2.8 Voices（AI 音色）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `list` | GET | `/ai-voices` | 无 | `[VoiceProfile]` | 获取所有可用音色 |

### 2.9 Images（图片生成）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `generateCharacter` | POST | `/images/character` | `GenerateCharacterImageRequest` | `EmptyData` | 触发生成角色图片 |
| `generateStoryboard` | POST | `/images/storyboard` | `GenerateStoryboardImageRequest` | `EmptyData` | 触发生成分镜图片 |
| `generateScene` | POST | `/images/scene` | `{ scene_id: Int }` | `EmptyData` | 触发生成场景图片 |

> 图片生成为异步操作，调用后返回 `EmptyData`，需要通过轮询 `PipelineStatus` 或检查对应资源的 `status` 字段来获取结果。

### 2.10 Videos（视频生成）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `generate` | POST | `/videos/generate` | `{ storyboard_id: Int }` | `EmptyData` | 触发生成分镜视频 |

> 同图片生成，为异步操作。

### 2.11 Compose（合成）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `shot` | POST | `/compose/shot` | `{ storyboard_id: Int }` | `EmptyData` | 合成分镜（图片 + TTS 拼接） |
| `tts` | POST | `/compose/tts` | `{ storyboard_id: Int }` | `EmptyData` | 为分镜生成 TTS 语音 |

### 2.12 Merge（合并）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `episode` | POST | `/merge/episode` | `{ episode_id: Int }` | `EmptyData` | 合并整集所有分镜视频 |

### 2.13 Grid（宫格图生成）

| 方法名 | HTTP 方法 | 路径 | 请求体/参数 | 响应类型 | 用途 |
|--------|-----------|------|-------------|----------|------|
| `generate` | POST | `/grid/generate` | `{ episode_id: Int, character_id: Int }` | `EmptyData` | 触发生成角色宫格参考图 |

---

## 3. 通用数据结构

### 3.1 APIResponse\<T\> — 标准响应包装

所有 API 响应均被 `APIResponse<T>` 包装：

```swift
struct APIResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let code: Int          // 状态码
    let message: String?   // 可选消息
    let data: T?           // 实际数据
}
```

**JSON 示例**:

```json
{
    "code": 0,
    "message": "success",
    "data": { ... }
}
```

### 3.2 PaginatedResponse\<T\> — 分页响应

用于返回分页列表数据，直接包含 `items` 和 `pagination`，不嵌套在 `APIResponse` 内：

```swift
struct PaginatedResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
    let pagination: Pagination
}

struct Pagination: Decodable, Sendable {
    let page: Int           // 当前页码
    let pageSize: Int       // 每页数量 (JSON: page_size)
    let total: Int          // 总记录数
    let totalPages: Int     // 总页数 (JSON: total_pages)
}
```

**JSON 示例**:

```json
{
    "items": [ ... ],
    "pagination": {
        "page": 1,
        "page_size": 20,
        "total": 100,
        "total_pages": 5
    }
}
```

### 3.3 EmptyData — 空数据响应

用于无返回数据的操作（如删除、更新、触发异步任务）：

```swift
struct EmptyData: Decodable, Sendable {}
```

---

## 4. 错误处理约定

### 4.1 APIError 类型

`APIClient` 将所有错误统一为 `APIError` 枚举：

```swift
enum APIError: Error, LocalizedError {
    case invalidURL                       // URL 构建失败
    case networkError(Error)              // 网络层错误（超时、无连接等）
    case serverError(Int, String?)        // HTTP 状态码非 2xx，附带响应体
    case decodingError(Error)             // JSON 解码失败
    case unknown                          // 未知错误
}
```

**中文错误描述**:

| 错误类型 | 描述格式 |
|----------|----------|
| `invalidURL` | "无效 URL" |
| `networkError` | "网络错误: {原始错误信息}" |
| `serverError` | "服务器错误 {状态码}: {响应体或\"未知\"}" |
| `decodingError` | "解析错误: {原始错误信息}" |
| `unknown` | "未知错误" |

### 4.2 HTTP 状态码判断

```swift
if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
    let msg = String(data: data, encoding: .utf8)
    throw APIError.serverError(http.statusCode, msg)
}
```

- **200-299**: 视为成功
- **其他状态码**: 抛出 `APIError.serverError`，将 HTTP 状态码和响应体文本传入

### 4.3 解码优先级

响应数据先尝试按 `APIResponse<T>` 解码提取 `data` 字段；若 `data` 为 `nil`（如 `EmptyData`），则直接按 `T` 类型解码原始 JSON。

---

## 5. SSE 流式端点

### 5.1 概述

Agent 的 `chat` 和 `run` 接口使用 **Server-Sent Events (SSE)** 返回流式数据。

- 返回类型: `AsyncThrowingStream<String, Error>`
- 协议: 标准 SSE，每行以 `data: ` 开头
- 结束标记: `data: [DONE]`

### 5.2 流式数据解析逻辑

```swift
func streamSSE(path: String, body: some Encodable) -> AsyncThrowingStream<String, Error> {
    // ...
    let (bytes, _) = try await URLSession.shared.bytes(for: req)
    for try await line in bytes.lines {
        if line.hasPrefix("data: ") {
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            continuation.yield(payload)
        }
    }
    continuation.finish()
}
```

### 5.3 SSE 数据格式

```
data: {"content": "这是第一段文本"}
data: {"content": "这是第二段文本"}
data: [DONE]
```

每条 `data:` 后的 `payload` 为纯文本字符串（通常是 JSON 片段），通过 `continuation.yield(payload)` 逐条推送给调用方。

### 5.4 使用示例

```swift
// 与剧本改写 Agent 对话
let stream = APIEndpoints.AgentAPI.chat(
    agentType: "script_rewriter",
    episodeId: episodeId,
    message: "请改写这段剧本，使对白更紧凑"
)

for try await chunk in stream {
    // chunk 为每段 SSE data 内容（String）
    print("收到: \(chunk)")
}
```

```swift
// 运行角色提取 Agent
let stream = APIEndpoints.AgentAPI.run(
    agentType: "extractor",
    episodeId: episodeId
)

for try await chunk in stream {
    print("处理进度: \(chunk)")
}
```

---

## 6. 轮询模式

### 6.1 PipelineStatus 结构

异步任务（图片生成、视频生成、合并等）触发后，通过轮询 `PipelineStatus` 获取进度：

```swift
struct PipelineStatus: Decodable {
    var episodeId: Int      // JSON: episode_id
    var steps: PipelineSteps
}

struct PipelineSteps: Decodable {
    var scriptRewrite: StepInfo          // script_rewrite
    var extractCharacters: StepInfo      // extract_characters
    var extractScenes: StepInfo          // extract_scenes
    var assignVoices: StepInfo           // assign_voices
    var generateVoiceSamples: StepInfo   // generate_voice_samples
    var extractStoryboards: StepInfo     // extract_storyboards
    var generateImages: StepInfo         // generate_images
    var generateVideos: StepInfo         // generate_videos
    var composeShots: StepInfo           // compose_shots
    var mergeEpisode: StepInfo           // merge_episode
}

struct StepInfo: Decodable {
    var status: String       // pending | ready | partial | done | failed
    var count: Int?          // 总数量
    var completed: Int?      // 已完成数量
    var total: Int?          // 总数
    var assigned: Int?       // 已分配数量
    var mergedUrl: String?   // 合并后的视频 URL (JSON: merged_url)
}
```

### 6.2 步骤状态值

| 状态 | 说明 |
|------|------|
| `pending` | 未开始 |
| `ready` | 数据已就绪，等待执行 |
| `partial` | 部分完成 |
| `done` | 已完成 |
| `failed` | 失败 |

### 6.3 典型轮询场景

**图片生成轮询**:

```
1. 调用 POST /images/character 触发生成
2. 定时调用 GET /episodes/{episodeId}/pipeline-status
3. 检查 steps.generateImages.status 是否变为 "done" 或 "failed"
4. 完成后从对应 Character 的 imageUrl 获取结果
```

**视频生成轮询**:

```
1. 调用 POST /videos/generate 触发生成
2. 定时调用 GET /episodes/{episodeId}/pipeline-status
3. 检查 steps.generateVideos.status 是否变为 "done" 或 "failed"
4. 完成后从对应 Storyboard 的 videoUrl 获取结果
```

**合并视频轮询**:

```
1. 调用 POST /merge/episode 触发合并
2. 定时调用 GET /episodes/{episodeId}/pipeline-status
3. 检查 steps.mergeEpisode.status 是否变为 "done"
4. 完成后从 steps.mergeEpisode.mergedUrl 获取结果
```

### 6.4 轮询代码示例

```swift
func pollPipelineStatus(episodeId: Int) async throws {
    var done = false
    while !done {
        let status = try await APIEndpoints.EpisodeAPI.pipelineStatus(episodeId: episodeId)
        let step = status.steps.generateImages
        print("图片生成: \(step.completed ?? 0)/\(step.total ?? 0) [\(step.status)]")

        if step.status == "done" || step.status == "failed" {
            done = true
        } else {
            try await Task.sleep(for: .seconds(3))
        }
    }
}
```

---

## 7. 调用示例

### 7.1 获取剧本列表

```swift
let page = try await APIEndpoints.DramaAPI.list(page: 1, pageSize: 10)
for drama in page.items {
    print("[\(drama.id)] \(drama.title) — \(drama.status)")
}
print("共 \(page.pagination.total) 部剧本")
```

### 7.2 创建剧本

```swift
let newDrama = try await APIEndpoints.DramaAPI.create(CreateDramaRequest(
    title: "都市传说",
    description: "一部都市悬疑短剧",
    genre: "悬疑",
    style: "写实",
    totalEpisodes: 10,
    tags: ["都市", "悬疑"]
))
print("创建成功，ID: \(newDrama.id)")
```

### 7.3 触发 AI 改写

```swift
// 流式获取改写结果
let stream = APIEndpoints.AgentAPI.chat(
    agentType: "script_rewriter",
    episodeId: episodeId,
    message: "请将这段剧本改写为更具张力的版本"
)

var fullText = ""
for try await chunk in stream {
    fullText += chunk
    // 实时更新 UI...
}
print("改写完成: \(fullText)")
```

### 7.4 生成角色图片

```swift
// 触发生成（异步）
try await APIEndpoints.ImagesAPI.generateCharacter(GenerateCharacterImageRequest(
    characterId: characterId,
    prompt: "一个穿着黑色风衣的中年男性，表情严肃",
    referenceImages: []
))

// 轮询等待完成
let status = try await APIEndpoints.EpisodeAPI.pipelineStatus(episodeId: episodeId)
// 检查 status.steps.generateImages.status ...
```

### 7.5 合并视频

```swift
// 触发合并
try await APIEndpoints.MergeAPI.episode(episodeId: episodeId)

// 轮询等待
var mergedUrl: String?
while true {
    let status = try await APIEndpoints.EpisodeAPI.pipelineStatus(episodeId: episodeId)
    if status.steps.mergeEpisode.status == "done" {
        mergedUrl = status.steps.mergeEpisode.mergedUrl
        break
    }
    if status.steps.mergeEpisode.status == "failed" {
        print("合并失败")
        break
    }
    try await Task.sleep(for: .seconds(5))
}

if let url = mergedUrl {
    print("合并完成: \(url)")
}
```

---

## 附录: 核心模型字段参考

### Drama

| 字段 | 类型 | JSON 键 | 说明 |
|------|------|---------|------|
| id | Int | id | 剧本 ID |
| title | String | title | 标题 |
| description | String? | description | 描述 |
| genre | String? | genre | 类型 |
| style | String? | style | 风格 |
| totalEpisodes | Int | total_episodes | 总集数 |
| status | String | status | 状态: draft / in_production / completed / archived |
| thumbnail | String? | thumbnail | 封面图 URL |
| tags | [String] | tags | 标签 |
| episodes | [Episode] | episodes | 集数列表 |
| characters | [Character] | characters | 角色列表 |
| scenes | [Scene] | scenes | 场景列表 |
| createdAt | String | created_at | 创建时间 |
| updatedAt | String | updated_at | 更新时间 |

### Episode

| 字段 | 类型 | JSON 键 | 说明 |
|------|------|---------|------|
| id | Int | id | 集 ID |
| dramaId | Int | drama_id | 所属剧本 ID |
| episodeNumber | Int | episode_number | 集序号 |
| title | String | title | 标题 |
| content | String? | content | 原始内容 |
| scriptContent | String? | script_content | 改写后的剧本内容 |
| description | String? | description | 描述 |
| duration | Int | duration | 时长(秒) |
| status | String | status | 状态: draft / script_ready / in_production / completed |
| videoUrl | String? | video_url | 合并后视频 URL |
| imageConfigId | Int? | image_config_id | 图片服务配置 ID |
| videoConfigId | Int? | video_config_id | 视频服务配置 ID |
| audioConfigId | Int? | audio_config_id | 音频服务配置 ID |

### Character

| 字段 | 类型 | JSON 键 | 说明 |
|------|------|---------|------|
| id | Int | id | 角色 ID |
| dramaId | Int | drama_id | 所属剧本 ID |
| name | String | name | 角色名 |
| role | String? | role | 角色定位 |
| description | String? | description | 描述 |
| appearance | String? | appearance | 外貌描述 |
| personality | String? | personality | 性格描述 |
| voiceStyle | String? | voice_style | 声音风格 |
| imageUrl | String? | image_url | 角色图片 URL |
| referenceImages | [String] | reference_images | 参考图 URL 列表 |
| seedValue | String? | seed_value | 图片种子值 |
| voiceSampleUrl | String? | voice_sample_url | 音色样本 URL |
| voiceProvider | String? | voice_provider | 音色供应商 |

### Storyboard

| 字段 | 类型 | JSON 键 | 说明 |
|------|------|---------|------|
| id | Int | id | 分镜 ID |
| episodeId | Int | episode_id | 所属集 ID |
| sceneId | Int? | scene_id | 所属场景 ID |
| storyboardNumber | Int | storyboard_number | 分镜序号 |
| title | String? | title | 标题 |
| location | String? | location | 地点 |
| time | String? | time | 时间 |
| shotType | String? | shot_type | 景别: extreme_wide / wide / medium / close_up / extreme_close |
| angle | String? | angle | 角度 |
| movement | String? | movement | 运动 |
| action | String? | action | 动作描述 |
| dialogue | String? | dialogue | 对白 |
| imagePrompt | String? | image_prompt | 图片提示词 |
| videoPrompt | String? | video_prompt | 视频提示词 |
| duration | Int | duration | 时长(秒) |
| composedImage | String? | composed_image | 合成图片 URL |
| videoUrl | String? | video_url | 视频 URL |
| ttsAudioUrl | String? | tts_audio_url | TTS 音频 URL |
| composedVideoUrl | String? | composed_video_url | 合成视频 URL |
| status | String | status | 状态: pending / processing / completed / failed |
| characterIds | [Int] | character_ids | 出场角色 ID 列表 |

### AIServiceConfig

| 字段 | 类型 | JSON 键 | 说明 |
|------|------|---------|------|
| id | Int | id | 配置 ID |
| serviceType | String | service_type | 服务类型: text / image / video / audio |
| provider | String? | provider | 供应商 |
| name | String | name | 配置名称 |
| baseUrl | String | base_url | API 基础 URL |
| apiKey | String | api_key | API 密钥 |
| model | [String] | model | 模型列表 |
| priority | Int | priority | 优先级 |
| isDefault | Bool | is_default | 是否默认 |
| isActive | Bool | is_active | 是否启用 |

### AgentConfig

| 字段 | 类型 | JSON 键 | 说明 |
|------|------|---------|------|
| id | Int | id | 配置 ID |
| agentType | String | agent_type | 代理类型 |
| name | String | name | 名称 |
| model | String? | model | 使用的模型 |
| systemPrompt | String? | system_prompt | 系统提示词 |
| temperature | Double? | temperature | 温度参数 |
| maxTokens | Int? | max_tokens | 最大 token 数 |
| maxIterations | Int? | max_iterations | 最大迭代次数 |
| isActive | Bool | is_active | 是否启用 |

### Skill

| 字段 | 类型 | 说明 |
|------|------|------|
| id | String | 技能 ID |
| name | String | 名称 |
| description | String | 描述 |
| content | String? | 技能内容/Prompt |

### VoiceProfile

| 字段 | 类型 | JSON 键 | 说明 |
|------|------|---------|------|
| id | Int | id | 音色 ID |
| voiceId | String | voice_id | 音色标识 |
| voiceName | String | voice_name | 音色名称 |
| description | [String] | description | 描述标签 |
| language | String? | language | 语言 |
| provider | String | provider | 供应商 |

### Scene

| 字段 | 类型 | JSON 键 | 说明 |
|------|------|---------|------|
| id | Int | id | 场景 ID |
| dramaId | Int | drama_id | 剧本 ID |
| episodeId | Int? | episode_id | 集 ID |
| location | String | location | 地点 |
| time | String | time | 时间 |
| prompt | String | prompt | 图片提示词 |
| storyboardCount | Int | storyboard_count | 关联分镜数 |
| imageUrl | String? | image_url | 场景图片 URL |
| status | String | status | 状态 |
