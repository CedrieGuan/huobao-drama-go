# Backend Go Migration Plan

> **Goal**: Rewrite the TypeScript (Hono + Drizzle + Mastra) backend to Go (Gin + GORM + PostgreSQL).
>
> **Principles**:
> - Front-end zero changes — API paths, request params, response format must be 100% identical
> - Data compatible — existing SQLite data migrates to PostgreSQL
> - Feature parity — all TS features must exist in Go
> - Progressive replacement — SQLite → PostgreSQL import & shadow validation before traffic switch
>
> **Status Convention**: `[ ]` Not started · `[~]` In progress · `[x]` Completed · `[-]` Skipped/Deferred

---

## Phase 1 — Project Skeleton + Database + Basic CRUD

> **Est. 3–4 days** · **Doc ref**: `01-database-and-crud.md`
>
> **Deliverables**: Go module, Gin server, PostgreSQL connection, 17 data models, migrations, basic CRUD routes, middleware, utilities.

### 1.1 Project Initialization & Configuration

- [ ] **1.1.1** Initialize Go module (`go mod init github.com/user/huobao-drama-go`)
  - `cmd/server/main.go` entry point
  - `internal/` package layout
- [ ] **1.1.2** Configuration system (`internal/config/config.go`)
  - `Config` struct: App, Server, Database, Storage, AI sections
  - Viper-based `Load()` with `configs/config.yaml` + env var override (`HUOBAO_` prefix)
  - `PORT`, `DB_PATH`, `STORAGE_PATH` env bindings
- [ ] **1.1.3** Makefile with targets: `build`, `dev`, `run`, `clean`, `test`, `lint`, `fmt`, `tidy`, `docker`, `tools`

### 1.2 Database Layer

- [ ] **1.2.1** PostgreSQL connection (`internal/database/db.go`)
  - `gorm.io/driver/postgres` + `gorm.io/gorm`
  - Connection with configurable pool (max_idle, max_open)
  - `Init()` function with graceful error handling
- [ ] **1.2.2** Migration system (`internal/database/migrations/`)
  - `golang-migrate` setup with versioned SQL files
  - Initial migration: 17 `CREATE TABLE` statements
  - 6 indexes for join tables (`episode_characters`, `episode_scenes`, `storyboard_characters`, etc.)
- [ ] **1.2.3** Data models (`internal/database/models.go`)
  - Custom `NullString`, `NullInt64`, `NullFloat64`, `NullBool` with JSON serialization
  - [ ] `Drama` (14 fields + relations: Episodes, Characters, Scenes, Props)
  - [ ] `Episode` (16 fields)
  - [ ] `Character` (16 fields)
  - [ ] `Scene` (12 fields)
  - [ ] `Storyboard` (30 fields + runtime: CharacterIDs, Characters)
  - [ ] `EpisodeCharacter` (4 fields)
  - [ ] `EpisodeScene` (4 fields)
  - [ ] `StoryboardCharacter` (join table)
  - [ ] `AIServiceConfig` (14 fields)
  - [ ] `AIServiceProvider` (10 fields)
  - [ ] `AIVoice` (7 fields)
  - [ ] `AgentConfig` (12 fields)
  - [ ] `ImageGeneration` (27 fields)
  - [ ] `VideoGeneration` (31 fields)
  - [ ] `VideoMerge` (14 fields)
  - [ ] `Prop` (10 fields)
  - [ ] `Asset` (20 fields)
- [ ] **1.2.4** Query helpers (`internal/database/queries.go`)
  - [ ] `GetDramaByID`, `ListDramas` (with `ListDramasOpts` for pagination/filtering)
  - [ ] `GetEpisodesByDramaID`, `GetCharactersByDramaID`, `GetScenesByDramaID`
  - [ ] `GetStoryboardsByEpisodeID`, `GetStoryboardCharacterIDs`
  - [ ] `GetEpisodeCharacterIDs`, `GetEpisodeSceneIDs`
  - [ ] Scanner helpers: `scanDrama`, `scanEpisode`, `scanCharacter`, `scanScene`, `scanStoryboard`

### 1.3 Handler / Route Layer — Basic CRUD

- [ ] **1.3.1** Handler foundation (`internal/handler/handler.go`)
  - `Handler` struct with `DB *gorm.DB`
  - `New()` constructor with dependency injection
- [ ] **1.3.2** Drama CRUD (`internal/handler/drama.go`)
  - [ ] `GET /api/v1/dramas` — `ListDramas` (pagination, filtering, stats)
  - [ ] `POST /api/v1/dramas` — `CreateDrama`
  - [ ] `GET /api/v1/dramas/stats` — `DramaStats`
  - [ ] `GET /api/v1/dramas/:id` — `GetDrama` (with `enrichDrama`)
  - [ ] `PUT /api/v1/dramas/:id` — `UpdateDrama`
  - [ ] `DELETE /api/v1/dramas/:id` — `DeleteDrama`
  - [ ] `PUT /api/v1/dramas/:id/characters` — `UpsertDramaCharacters`
  - [ ] `PUT /api/v1/dramas/:id/episodes` — `UpsertDramaEpisodes`
- [ ] **1.3.3** Episode handlers (`internal/handler/episode.go`)
  - [ ] `POST /api/v1/episodes` — `CreateEpisode`
  - [ ] `PUT /api/v1/episodes/:id` — `UpdateEpisode`
  - [ ] `GET /api/v1/episodes/:id/characters` — `GetEpisodeCharacters`
  - [ ] `GET /api/v1/episodes/:id/scenes` — `GetEpisodeScenes`
  - [ ] `GET /api/v1/episodes/:episode_id/storyboards` — `GetEpisodeStoryboards`
  - [ ] `GET /api/v1/episodes/:id/pipeline-status` — `GetEpisodePipelineStatus`
- [ ] **1.3.4** Scene handlers (`internal/handler/scene.go`)
  - [ ] `POST /api/v1/scenes` — `CreateScene`
  - [ ] `PUT /api/v1/scenes/:id` — `UpdateScene`
  - [ ] `DELETE /api/v1/scenes/:id` — `DeleteScene`
- [ ] **1.3.5** Character handlers (`internal/handler/character.go`)
  - [ ] `PUT /api/v1/characters/:id` — `UpdateCharacter`
  - [ ] `DELETE /api/v1/characters/:id` — `DeleteCharacter`
- [ ] **1.3.6** Storyboard handlers (`internal/handler/storyboard.go`)
  - [ ] `POST /api/v1/storyboards` — `CreateStoryboard`
  - [ ] `PUT /api/v1/storyboards/:id` — `UpdateStoryboard`
  - [ ] `DELETE /api/v1/storyboards/:id` — `DeleteStoryboard`

### 1.4 Middleware

- [ ] **1.4.1** Request logger (`internal/middleware/logger.go`)
  - Per-request logging with method/path/status/latency
  - Zerolog structured output
- [ ] **1.4.2** Error handler (`internal/middleware/logger.go`)
  - Panic recovery + error response
- [ ] **1.4.3** CORS middleware (`internal/middleware/cors.go`)
  - Configurable allowed origins

### 1.5 Utilities

- [ ] **1.5.1** Response helpers (`internal/util/response.go`)
  - `Success`, `Created`, `BadRequest`, `NotFound`, `ServerError`
  - Unified `{code, data, message}` format
- [ ] **1.5.2** Transform utility (`internal/util/transform.go`)
  - `ToSnakeCase`, `ToSnakeCaseMap` (camelCase → snake_case using regex)
- [ ] **1.5.3** Task logger (`internal/util/task_logger.go`)
  - Structured logging with sensitive data redaction
  - `RedactURL`, `LogTask`, `LogTaskStart`, `LogTaskSuccess`, `LogTaskError`, `LogTaskProgress`, `LogTaskWarn`, `LogTaskPayload`
- [ ] **1.5.4** HTTP utility (`internal/util/http.go`)
  - `httpDoRequest(req, timeout)` — executes `ProviderRequest` with timeout

### 1.6 Router & Server Setup

- [ ] **1.6.1** Router setup (`cmd/server/main.go` or `internal/router/router.go`)
  - Register all Phase 1 routes under `/api/v1/`
  - `/api/v1/health` health check endpoint
  - Static file serving `/static/*`
  - SPA frontend fallback (no-route → `index.html`)
- [ ] **1.6.2** Graceful shutdown
  - SIGINT/SIGTERM handling
  - `http.Server.Shutdown(ctx)` with 30s timeout
  - Close DB

### Phase 1 Acceptance Criteria

- [ ] Go module compiles and starts
- [ ] PostgreSQL connection + migrations work
- [ ] All basic CRUD endpoints return correct JSON responses
- [ ] Unified response format `{code, data, message}` matches TS version
- [ ] Middleware (logging, CORS, error handler) active
- [ ] Health check endpoint returns 200
- [ ] Static file serving works
- [ ] SPA fallback works

---

## Phase 2 — AI Provider Adapter Layer

> **Est. 3–4 days** · **Doc ref**: `02-adapters.md`
>
> **Deliverables**: 3 adapter interfaces, URL builder, registry, 10 provider adapters, helper functions.
>
> **Parallelizable**: Each adapter implementation is independent.

### 2.1 Interface Definitions & Core

- [ ] **2.1.1** Adapter types (`internal/adapter/types.go`)
  - [ ] Request/Response structs: `ProviderRequest`, `AIConfig`, `ImageGenRecord`, `VideoGenRecord`, `ImageGenResponse`, `ImagePollResponse`, `VideoGenResponse`, `VideoPollResponse`, `Base64Image`, `TTSResponse`
  - [ ] `ImageProviderAdapter` interface: `Provider()`, `BuildGenerateRequest()`, `ParseGenerateResponse()`, `BuildPollRequest()`, `ParsePollResponse()`, `ExtractImageBase64()`
  - [ ] `VideoProviderAdapter` interface: `Provider()`, `BuildGenerateRequest()`, `ParseGenerateResponse()`, `BuildPollRequest()`, `ParsePollResponse()`
  - [ ] `TTSProviderAdapter` interface: `Provider()`, `BuildGenerateRequest()`, `ParseResponse()`
- [ ] **2.1.2** URL builder (`internal/adapter/url_builder.go`)
  - `JoinProviderURL(baseURL, requiredPrefix, path)` with helpers
  - Edge cases: trailing slashes, embedded prefixes, empty segments
- [ ] **2.1.3** Registry (`internal/adapter/registry.go`)
  - Maps: `imageAdapters` (6), `videoAdapters` (4), `ttsAdapters` (1)
  - `GetImageAdapter`, `GetVideoAdapter`, `GetTTSAdapter` — with MiniMax fallback
  - `GetProviderList()` — returns all registered providers
- [ ] **2.1.4** Helper functions (`internal/adapter/helpers.go`)
  - `parseSize()` — "WxH" string → width/height with defaults
  - `simplifyRatio()` — reduces aspect ratio using GCD
  - `parseJSONStringArray()` — safely parses JSON string arrays

### 2.2 Image Adapters (parallelizable)

- [ ] **2.2.1** MiniMax Image (`internal/adapter/minimax_image.go`)
  - POST `/v1/image_generation`, sync/async, poll via GET
- [ ] **2.2.2** OpenAI Image (`internal/adapter/openai_image.go`)
  - POST `/v1/images/generations`, DALL-E 3, URL/b64_json
- [ ] **2.2.3** Gemini Image (`internal/adapter/gemini_image.go`)
  - Google REST API, base64 via `inlineData.data`, aspect ratio + image size mapping
- [ ] **2.2.4** VolcEngine Image (`internal/adapter/volcengine_image.go`)
  - Async generation, poll response
- [ ] **2.2.5** Ali Image (`internal/adapter/ali_image.go`)
  - DashScope async, `convertToAliSize()` helper
- [ ] **2.2.6** Chatfire Image (`internal/adapter/chatfire_image.go`)
  - Reuses OpenAI-compatible format

### 2.3 Video Adapters (parallelizable)

- [ ] **2.3.1** MiniMax Video (`internal/adapter/minimax_video.go`)
  - OpenAI Chat Completions format, `--ratio`/`--dur` prompt tags, 3 ref modes
- [ ] **2.3.2** VolcEngine Video (`internal/adapter/volcengine_video.go`)
  - Async 4–12s video, `normalizeDuration()` helper
- [ ] **2.3.3** Vidu Video (`internal/adapter/vidu_video.go`)
  - Webhook-only (no polling), `ParseCallbackState()`
- [ ] **2.3.4** Ali Video (`internal/adapter/ali_video.go`)
  - DashScope async

### 2.4 TTS Adapters

- [ ] **2.4.1** MiniMax TTS (`internal/adapter/minimax_tts.go`)
  - POST `/v1/t2a_v2`, hex-encoded audio, speed/volume/pitch/emotion params

### Phase 2 Acceptance Criteria

- [ ] All 10 adapters compile and register in the registry
- [ ] `JoinProviderURL` handles all edge cases
- [ ] Each adapter implements its respective interface correctly
- [ ] Round-trip test stubs for each adapter with mock HTTP server

---

## Phase 3 — Image / Video / TTS Generation Services

> **Est. 3–4 days** · **Doc ref**: `03-generation-services.md`
>
> **Deliverables**: Generation services, async task lifecycle, webhook handling, file storage, voice management, task recovery.
>
> **Dependencies**: Phase 1 (DB, models, queries), Phase 2 (adapters).

### 3.1 AI Config Query Service

- [ ] **3.1.1** AI config service (`internal/service/ai_config.go`)
  - `ServiceType` enum: text, image, video, audio
  - `GetActiveConfig(db, serviceType)` — active=1, ordered by priority DESC
  - `GetConfigByID(db, id)`
  - `GetAudioConfigByID(db, id)` — tries ID first, falls back to default audio
  - `GetTextProviderBaseURL(cfg)` — routes to correct URL prefix per provider

### 3.2 Task Recovery

- [ ] **3.2.1** Startup recovery (`internal/service/task_recovery.go`)
  - `ResumePendingTasks(db)` — on startup
  - Image tasks: with task_id → resume polling; stale >2min without task_id → failed
  - Video tasks: same logic, but Vidu webhook-only tasks left as-is

### 3.3 Image Generation Service

- [ ] **3.3.1** Image generation service (`internal/service/image_gen.go`)
  - `ImageGenParams` struct
  - `GenerateImage()` — gets config → inserts record (status=processing) → launches goroutine
  - `processImageGeneration()` — reads record → normalizes refs → calls adapter → handles 3 cases:
    - sync + URL → download
    - sync + base64 → save
    - async → start poller
  - `pollImageTask()` — 5s ticker, 10-min deadline
  - `handleImageComplete()` — updates image_generations + related storyboard/character/scene
  - `normalizeReferenceImages()` — local → DataURL (compressed 768×768@68), remote unchanged, max 6 refs, dedup

### 3.4 Video Generation Service

- [ ] **3.4.1** Video generation service (`internal/service/video_gen.go`)
  - `VideoGenParams` struct, defaults: duration=5, aspect_ratio=16:9
  - `GenerateVideo()` — same pattern as image
  - `processVideoGeneration()` — Vidu: no poll; others: start poller
  - `pollVideoTask()` — 10s ticker, max 300 iterations (50min)
  - `normalizeVideoReferenceURL()`, `normalizeVideoReferenceURLs()`

### 3.5 TTS Service

- [ ] **3.5.1** TTS generation service (`internal/service/tts_gen.go`)
  - `TTSParams`, `TTSResult` structs
  - `GenerateTTS()` — gets config → calls adapter → hex-decodes → saves to file
  - `GenerateVoiceSample()` — simplified TTS for character voice samples
  - `parseDialogueForTTS()` — parses "speaker: text" format, identifies ignorable speakers/text
  - `GenerateStoryboardTTS()` — route handler: parses storyboard dialogue → generates TTS

### 3.6 File Storage & Upload

- [ ] **3.6.1** File storage (`internal/util/storage.go`)
  - `InitStorage()`, `GetAbsolutePath()`
  - `DownloadFile()` — remote URL → local
  - `SaveBase64Image()`
  - `ReadImageAsCompressedDataURL()` — compress local image to data URL
  - `ParseDataURL()`, `extractExtFromURL()`, `mimeToExt()`

### 3.7 Generation Route Handlers

- [ ] **3.7.1** Image routes (`internal/handler/image.go`)
  - [ ] `POST /api/v1/images` — `CreateImage` (auto-resolves config_id from episode)
  - [ ] `GET /api/v1/images/:id` — `GetImage`
  - [ ] `GET /api/v1/images` — `ListImages` (filter by storyboard_id/drama_id)
  - [ ] `DELETE /api/v1/images/:id` — `DeleteImage`
- [ ] **3.7.2** Video routes (`internal/handler/video.go`)
  - [ ] `POST /api/v1/videos` — `CreateVideo`
  - [ ] `GET /api/v1/videos/:id` — `GetVideo`
  - [ ] `GET /api/v1/videos` — `ListVideos`
  - [ ] `DELETE /api/v1/videos/:id` — `DeleteVideo`
- [ ] **3.7.3** Upload route (`internal/handler/upload.go`)
  - [ ] `POST /api/v1/upload/image` — multipart form upload, saves to static dir
- [ ] **3.7.4** Webhook handler (`internal/handler/webhook.go`)
  - [ ] `POST /webhooks/vidu` — receives callback, finds video_generations by task_id, downloads video / marks failed
- [ ] **3.7.5** Scene image generation route (in `scene.go`)
  - [ ] `POST /api/v1/scenes/:id/generate-image`
- [ ] **3.7.6** Character voice/image generation routes (in `character.go`)
  - [ ] `POST /api/v1/characters/:id/generate-voice-sample`
  - [ ] `POST /api/v1/characters/:id/generate-image`
  - [ ] `POST /api/v1/characters/batch-generate-images`
- [ ] **3.7.7** Storyboard TTS route (in `storyboard.go`)
  - [ ] `POST /api/v1/storyboards/:id/generate-tts`
  - [ ] Storyboard character binding support

### 3.8 Voice Management

- [ ] **3.8.1** Voice routes (`internal/handler/ai_voice.go`)
  - [ ] `GET /api/v1/ai-voices` — `ListAIVoices` (by provider, default minimax)
  - [ ] `POST /api/v1/ai-voices/sync` — `SyncAIVoices` (calls MiniMax, upserts DB)

### Phase 3 Acceptance Criteria

- [ ] Image generation works end-to-end with at least 1 provider
- [ ] Video generation works end-to-end with at least 1 provider
- [ ] TTS generation works with MiniMax
- [ ] Async polling lifecycle works (created → processing → completed/failed)
- [ ] Task recovery works on server restart
- [ ] File upload/download works
- [ ] Vidu webhook callback processes correctly
- [ ] Voice sync works

---

## Phase 4 — FFmpeg Compose + Merge + Grid

> **Est. 2 days** · **Doc ref**: `04-ffmpeg-and-grid.md`
>
> **Deliverables**: FFmpeg single-shot compose, episode merge, grid image split, route handlers.
>
> **Dependencies**: Phase 1 (DB), Phase 3 (TTS, image gen).

### 4.1 FFmpeg Single-Shot Compose

- [ ] **4.1.1** FFmpeg compose service (`internal/service/ffmpeg_compose.go`)
  - Dialogue parsing: `ignoreTTSSpeakers`, `ignoreTTSText` regex patterns
  - `DialogueParseResult`: Speaker, PureText, Ignorable
  - `generateSRTFile()` — creates SRT subtitle file
  - `buildComposeArgs()` — constructs FFmpeg args (`libx264`, `aac`, `subtitles` filter)
  - `supportsSubtitleFilter()` — caches FFmpeg capability detection
  - `ComposeStoryboard(db, storyboardID)` — full orchestration pipeline
  - Voice ID resolution: match dialogue speaker → character VoiceStyle → default "alloy"

### 4.2 FFmpeg Episode Merge

- [ ] **4.2.1** FFmpeg merge service (`internal/service/ffmpeg_merge.go`)
  - `generateConcatList()` — temp file with `file '/path'` entries
  - `doMerge()` — `ffmpeg -f concat -safe 0 -i list.txt` with libx264/aac/faststart
  - `getVideoDuration()` — ffprobe duration
  - `MergeEpisodeVideos()` — async goroutine entry point

### 4.3 Grid Image Split

- [ ] **4.3.1** Grid split service (`internal/service/grid_split.go`)
  - `SplitGridImage(imagePath, rows, cols)` — uses `disintegration/imaging`
  - Returns `[]SplitResult{Index, LocalPath}`

### 4.4 Route Handlers

- [ ] **4.4.1** Compose routes (`internal/handler/compose.go`)
  - [ ] `POST /api/v1/compose/storyboards/:id/compose` — `ComposeShot`
  - [ ] `POST /api/v1/compose/episodes/:id/compose-all` — `ComposeAll` (async batch)
  - [ ] `GET /api/v1/compose/episodes/:id/compose-status` — `ComposeStatus`
- [ ] **4.4.2** Merge routes (`internal/handler/merge.go`)
  - [ ] `POST /api/v1/merge/episodes/:id/merge` — `MergeEpisode` (async)
  - [ ] `GET /api/v1/merge/episodes/:id/merge` — `MergeStatus`
- [ ] **4.4.3** Grid routes (`internal/handler/grid.go`)
  - [ ] `POST /api/v1/grid/generate-prompt` — `GridPrompt` (Agent-first with rule fallback)
  - [ ] `POST /api/v1/grid/generate-image` — `GridGenerate` (960×cols × 540×rows canvas)
  - [ ] `POST /api/v1/grid/split-and-assign` — `GridSplit` (split + assign cells to storyboards)
  - [ ] `GET /api/v1/grid/cell/:id` — `GridStatus`

### 4.5 DB Query Supplements

- [ ] **4.5.1** Additional queries
  - [ ] `GetStoryboardByID`, `ListStoryboardsByEpisodeID`
  - [ ] `UpdateStoryboardStatus`, `UpdateStoryboardTTS`, `UpdateStoryboardSubtitle`
  - [ ] `UpdateStoryboardComposed`, `UpdateStoryboardFrameImage`
  - [ ] `UpdateStoryboardsStatusByEpisode`
  - [ ] `GetEpisodeByID`, `UpdateEpisodeVideoURL`
  - [ ] `InsertVideoMerge`, `UpdateMergeCompleted`, `UpdateMergeFailed`
  - [ ] `GetLatestVideoMergeByEpisodeID`, `GetImageGenerationByID`

### Phase 4 Acceptance Criteria

- [ ] Single-shot compose works (video + TTS + subtitles)
- [ ] Batch compose-all works with status tracking
- [ ] Episode merge produces concatenated video
- [ ] Grid image split produces correct cells
- [ ] Grid cells assign to storyboards correctly

---

## Phase 5 — AI Agent System

> **Est. 4–5 days** · **Doc ref**: `05-agent-system.md`
>
> **Deliverables**: Agent core with Function Calling loop, 5 agent types with tool sets, SKILL.md loader, SSE streaming.
>
> **Parallelizable**: Each tool set is independent once the agent core is complete.

### 5.1 Agent Core

- [ ] **5.1.1** Agent types & loop (`internal/agent/agent.go`)
  - `Agent` struct: ID, Name, Instructions, Model, BaseURL, APIKey, Tools, MaxSteps
  - `ToolDef`, `ToolHandler` type definitions
  - OpenAI-format types: `ChatMessage`, `ToolCall`, `ChatRequest`, `ToolSchema`, `FuncSchema`, `ChatResponse`
  - `AgentResult`: Text, ToolCalls, ToolResults
  - `Run()` method — Function Calling loop:
    1. Build messages (system + user)
    2. Build tool schemas
    3. Loop (maxSteps, default 20): call LLM → no tool_calls = return → else execute tools → append results → continue
    4. Exceeds maxSteps → error
- [ ] **5.1.2** HTTP helpers (`internal/agent/agent_http.go`)
  - Thin wrappers for testability: `httpDefaultClient`, `httpNewRequestWithContext`, etc.

### 5.2 Prompts & Skills

- [ ] **5.2.1** Default prompts (`internal/agent/prompts.go`)
  - `DefaultPrompts` map for all 5 agents with detailed instructions
  - `ValidAgentTypes()`, `IsValidAgentType()` helpers
- [ ] **5.2.2** SKILL.md loader (`internal/agent/skills.go`)
  - `agentSkillMap` — maps agent type → skill directory
  - `SetSkillsDir()` — sets root skills directory
  - `LoadAgentSkills()` — reads SKILL.md, strips YAML frontmatter, prepends header
  - `stripFrontmatter()` — removes `---` blocks

### 5.3 Agent Factory

- [ ] **5.3.1** Factory (`internal/agent/factory.go`)
  - `CreateAgent(db, agentType, episodeID, dramaID)`
  - Gets default prompts → reads DB config → gets active text AI config
  - Resolves base URL with `GetTextProviderBaseURL()` + `/chat/completions`
  - Merges DB config (model, system_prompt, name) over defaults
  - Appends SKILL.md to instructions
  - Creates tools based on agent type

### 5.4 Tool Implementations (parallelizable)

- [ ] **5.4.1** Script tools (`internal/agent/tool/script_tools.go`)
  - `read_episode_script`, `save_script`
- [ ] **5.4.2** Extract tools (`internal/agent/tool/extract_tools.go`)
  - `read_script_for_extraction`
  - `read_existing_characters` (with `linked_to_current_episode` flag)
  - `read_existing_scenes` (with link status)
  - `save_dedup_characters` (name-based dedup + episode link)
  - `save_dedup_scenes` (location+time dedup + episode link)
- [ ] **5.4.3** Storyboard tools (`internal/agent/tool/storyboard_tools.go`)
  - `read_storyboard_context` (script + characters + scenes + existing storyboards)
  - `save_storyboards` (batch insert with all fields)
  - `update_storyboard` (partial update)
  - `generate_grid_prompt` (grid layout with mode/rows/cols)
- [ ] **5.4.4** Voice tools (`internal/agent/tool/voice_tools.go`)
  - `list_voices` — queries ai_voices
  - `get_characters` — gets characters with voice info
  - `assign_voice` — sets voice_id and voice_provider
- [ ] **5.4.5** Grid prompt tools (`internal/agent/tool/grid_prompt_tools.go`)
  - `read_characters_for_grid`, `read_scenes_for_grid`, `read_shots_for_grid`
  - `generate_grid_prompt` — builds grid prompt with mode/rows/cols/reference legend

### 5.5 Agent Routes

- [ ] **5.5.1** Agent handler (`internal/handler/agent.go`)
  - [ ] `POST /api/v1/agent/:type/chat` — `AgentChat`: creates agent, runs, returns SSE stream with text + tool_calls + tool_results
  - [ ] `GET /api/v1/agent/:type/debug` — `AgentDebug`: returns agent config info

### Phase 5 Acceptance Criteria

- [ ] Agent Function Calling loop works with OpenAI-compatible LLM
- [ ] All 5 agent types create successfully with correct tools
- [ ] SKILL.md files load and prepend to instructions
- [ ] SSE streaming works for agent chat
- [ ] Tool execution captures and returns results correctly
- [ ] Agent debug endpoint returns config info

---

## Phase 6 — Config Management + Remaining Routes

> **Est. 2 days** · **Doc ref**: `06-config-and-remaining.md`
>
> **Deliverables**: AI config CRUD, Agent config CRUD, Skills file management, preset, test endpoint.
>
> **Dependencies**: Phase 1 (DB/models), Phase 2 (adapters for test/preset), Phase 5 (agent prompts for preset).

### 6.1 AI Service Config

- [ ] **6.1.1** AI config handler (`internal/handler/ai_config.go`)
  - [ ] `GET /api/v1/ai-configs` — `ListAIConfigs` (service_type filter, model JSON parse, int→bool conversion)
  - [ ] `GET /api/v1/ai-configs/:id` — `GetAIConfig`
  - [ ] `POST /api/v1/ai-configs` — `CreateAIConfig` (auto-name, model JSON serialize)
  - [ ] `PUT /api/v1/ai-configs/:id` — `UpdateAIConfig` (partial update)
  - [ ] `DELETE /api/v1/ai-configs/:id` — `DeleteAIConfig`
  - [ ] `POST /api/v1/ai-configs/test` — `TestAIConfig` (provider-specific probe, 10s timeout)
    - openai → GET /v1/models
    - gemini → GET with ?key=
    - minimax → POST chatcompletion
    - Returns: {reachable, status, url, preview}
  - [ ] `POST /api/v1/ai-configs/huobao-preset` — `HuobaoPreset` (1-click setup: 4 AI configs + 5 agent configs)
  - [ ] `GET /api/v1/ai-providers` — `ListAIProviders` (DB first, adapter fallback)

### 6.2 Agent Config

- [ ] **6.2.1** Agent config handler (`internal/handler/agent_config.go`)
  - [ ] `GET /api/v1/agent-configs` — list non-deleted, ordered by agent_type
  - [ ] `GET /api/v1/agent-configs/:id` — single config
  - [ ] `POST /api/v1/agent-configs` — upsert by agent_type (validate type, undelete if exists)
  - [ ] `PUT /api/v1/agent-configs/:id` — partial update
  - [ ] `DELETE /api/v1/agent-configs/:id` — soft delete

### 6.3 Skills Management

- [ ] **6.3.1** Skills handler (`internal/handler/skill.go`)
  - [ ] `GET /api/v1/skills` — scans directories, parses YAML frontmatter
  - [ ] `GET /api/v1/skills/*id` — returns raw SKILL.md content
  - [ ] `POST /api/v1/skills` — creates directory + SKILL.md with frontmatter template
  - [ ] `PUT /api/v1/skills/*id` — overwrites SKILL.md
  - [ ] `DELETE /api/v1/skills/*id` — removes entire skill directory
  - [ ] Frontmatter parsing: regex + line-by-line YAML (no yaml dependency)

### 6.4 Complete Route Registration

- [ ] **6.4.1** Register all remaining routes in router setup
  - Verify all ~60 endpoints match TS version exactly

### Phase 6 Acceptance Criteria

- [ ] AI config CRUD works with model JSON serialization
- [ ] AI config test endpoint probes providers correctly
- [ ] Huobao preset creates 4 AI configs + 5 agent configs
- [ ] Agent config upsert by agent_type works
- [ ] Skills file system CRUD works
- [ ] All ~60 API endpoints registered and accessible

---

## Phase 7 — Testing + Docker + Deployment

> **Est. 2 days** · **Doc ref**: `07-testing-and-deployment.md`
>
> **Deliverables**: Tests (unit + integration + compatibility), Docker, Makefile, Air hot-reload, deployment docs.

### 7.1 Unit Tests

- [ ] **7.1.1** Util tests (`internal/util/*_test.go`)
  - [ ] `ToSnakeCase` / `ToSnakeCaseMap` — table-driven tests
  - [ ] `JoinProviderURL` — edge case tests
  - [ ] Response helpers
- [ ] **7.1.2** Adapter tests (`internal/adapter/*_test.go`)
  - [ ] Each adapter: `httptest.Server` mock, test Build/Parse round-trip
  - [ ] MiniMax Image (sync + async), OpenAI Image, Gemini Image
  - [ ] MiniMax Video, VolcEngine Video, Vidu Video
  - [ ] MiniMax TTS

### 7.2 Integration Tests

- [ ] **7.2.1** Test infrastructure (`tests/integration/`)
  - `setupTestDB(t)` — connects to test PostgreSQL, runs migrations
  - `setupTestRouter(db)` — creates handler + router
- [ ] **7.2.2** CRUD tests
  - [ ] `TestDramaCRUD` — Create → Get → List → Delete flow
  - [ ] `TestEpisodeCRUD`
  - [ ] `TestCharacterCRUD`
  - [ ] `TestSceneCRUD`
  - [ ] `TestStoryboardCRUD`

### 7.3 Compatibility Tests

- [ ] **7.3.1** Test infrastructure (`tests/compatibility/`)
  - `endpoints.json` — list of 15+ endpoints to test
  - `TestResponseCompatibility` — compares TS and Go responses
- [ ] **7.3.2** Three-layer compatibility verification
  - [ ] Schema comparison (field names, types)
  - [ ] Golden file comparison (response snapshots)
  - [ ] Workflow smoke test (full pipeline)

### 7.4 Docker & DevOps

- [ ] **7.4.1** Multi-stage Dockerfile
  - Stage 1: Frontend build (Node 20)
  - Stage 2: Backend build (Go 1.23, CGO_ENABLED=1)
  - Stage 3: Production image (Node 20 slim + ffmpeg + ca-certs)
  - Target: ~200MB image
- [ ] **7.4.2** Docker Compose
  - [ ] `docker-compose.yml` — production (health check, volumes for data/config/skills)
  - [ ] `docker-compose.dev.yml` — dev mode (TS port 5679 + Go port 5680 for compatibility testing)
- [ ] **7.4.3** Air hot-reload (`.air.toml`)
  - CGO_ENABLED=1, watches .go/.yaml/.yml, excludes test/data/skills/frontend

### 7.5 Performance & Profiling

- [ ] **7.5.1** Benchmark tests
  - `BenchmarkListDramas` (target ≥3000 QPS)
  - `BenchmarkGetDrama` (target ≥5000 QPS)
  - Memory target: ≤50MB resident, ≤100 goroutines idle
- [ ] **7.5.2** pprof integration
  - Debug mode exposes `:6060` for profiling

### 7.6 Deployment

- [ ] **7.6.1** Data migration tool (`scripts/migrate_sqlite_to_pg/`)
  - SQLite → PostgreSQL data import
- [ ] **7.6.2** Grayscale switch procedure documented
  1. Setup PostgreSQL + run migrations
  2. Full SQLite → PostgreSQL import
  3. Go backend on port 5680 for compatibility testing
  4. Frontend proxy to 5680 for manual walkthrough
  5. Switch window: pause TS writes → final incremental import → switch traffic
  6. Monitor 1–2 days → remove TS code
- [ ] **7.6.3** Rollback plan documented
  - Rollback = switch traffic back to TS
  - Pre-switch: SQLite read-only backup + PostgreSQL dump
  - Record Go-written task ranges for reconciliation

### Phase 7 Acceptance Criteria

- [ ] All unit tests pass
- [ ] Integration tests pass against PostgreSQL
- [ ] Compatibility tests show 100% API parity with TS backend
- [ ] Docker builds successfully (~200MB)
- [ ] `docker-compose up` works
- [ ] Air hot-reload works for development
- [ ] Performance benchmarks meet targets
- [ ] Deployment and rollback procedures documented

---

## Delivery Checklist

### Functional Completeness

- [ ] All 17 route files implemented
- [ ] All 17 database tables with migrations
- [ ] All 10 AI provider adapters
- [ ] All 5 agent types with tools
- [ ] FFmpeg compose + merge
- [ ] Grid image workflow
- [ ] Vidu webhook handling
- [ ] Skills file management
- [ ] Huobao preset
- [ ] Task recovery on restart
- [ ] Graceful shutdown

### Compatibility

- [ ] API response format: `{code, data, message}`
- [ ] snake_case response fields
- [ ] All frontend pages functional (list, detail, workbench, settings)
- [ ] File upload / download works
- [ ] Error format matches TS version
- [ ] Static resource serving + SPA fallback
- [ ] Task state machine: created → processing → completed/failed

### Operations

- [ ] Docker build works
- [ ] docker-compose up works (dev + prod)
- [ ] Health check endpoint (`/api/v1/health`)
- [ ] Zerolog JSON structured output
- [ ] Config from YAML + env var override
- [ ] Graceful shutdown with 30s timeout
- [ ] `ResumePendingTasks` on startup
- [ ] Grayscale deployment SOP documented
- [ ] Rollback plan documented
- [ ] 24hr observation completed with no anomalies

---

## Parallelization Map

The following tasks can be worked on simultaneously by different agents/threads:

| Track | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 | Phase 6 | Phase 7 |
|-------|---------|---------|---------|---------|---------|---------|---------|
| **A: Core** | Config + DB + Models + Router | Adapters interfaces + Registry + URL builder | AI config service + Task recovery | FFmpeg compose | Agent core + Factory + Prompts | AI config CRUD | Docker + Makefile |
| **B: CRUD** | Drama + Episode + Scene + Character + Storyboard handlers | — | — | FFmpeg merge | — | Agent config CRUD | Unit tests |
| **C: Services** | Middleware + Utilities | Image adapters (6×) | Image gen service + routes | Grid split + routes | Script tools + Extract tools | Skills CRUD | Integration tests |
| **D: Services** | Response + Transform + Task logger | Video adapters (4×) + TTS adapter (1×) | Video gen + TTS + File storage + Upload + Webhook | Grid routes | Storyboard tools + Voice tools + Grid prompt tools | Huobao preset + AI providers | Compatibility tests |

**Note**: Tracks C and D within Phase 2 can spawn one agent per adapter for maximum parallelism.

---

## Progress Log

| Date | Phase | Task ID | Status | Notes |
|------|-------|---------|--------|-------|
| _auto_ | — | — | — | Plan created |