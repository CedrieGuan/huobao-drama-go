# Backend Go 迁移状态

> 本文件用于跟踪 [MIGRATION-PLAN.md](./MIGRATION-PLAN.md) 的实际执行进度。
>
> 重要区分：
> - `TypeScript 基线已存在`：表示当前 `backend/src` 中已有对应功能，可作为 Go 重写参考。
> - `Go 迁移已完成`：表示对应能力已经在 Go 工程中真正落地。
>
> 后续更新规则：
> - 只有 Go 代码、测试、配置、部署资产已落地并满足 `MIGRATION-PLAN.md` 的验收标准时，才把对应项标记为 `已完成`。
> - 不能因为 TypeScript 后端已有该功能，就把 Go 迁移项提前勾选完成。

## 1. 当前结论

- 更新日期：2026-04-18
- 当前 Go 迁移状态：`Phase 1 基本完成，准备进入 Phase 2`
- 当前 TypeScript 后端状态：`功能基线基本完整`
- 当前判断依据：
  - 当前后端仍是 TypeScript 实现，入口为 `backend/src/index.ts`。
  - `backend-go/` 已完成 Phase 1 全部核心 CRUD 和基础设施。
  - Go 后端使用 SQLite（兼容现有 `data/huobao_drama.db`）+ GORM v2 + Gin。
  - 所有基础 CRUD 端点已验证通过 smoke test。

## 2. 当前仓库基线

### 已确认存在的 TypeScript 基线

- 路由与服务入口：`backend/src/index.ts`
- 数据库与模型：`backend/src/db/index.ts`、`backend/src/db/schema.ts`
- 基础 CRUD 路由：`backend/src/routes/*.ts`
- 中间件与工具：`backend/src/middleware/logger.ts`、`backend/src/utils/*.ts`
- AI Adapter：`backend/src/services/adapters/*`
- 图片/视频/TTS：`backend/src/services/image-generation.ts`、`video-generation.ts`、`tts-generation.ts`
- FFmpeg / Grid：`backend/src/services/ffmpeg-compose.ts`、`ffmpeg-merge.ts`、`grid-split.ts`
- Agent 系统：`backend/src/agents/*`、`backend/src/routes/agent.ts`
- 配置与 Skills：`backend/src/routes/aiConfigs.ts`、`agentConfigs.ts`、`skills.ts`

### 已落地的 Go 资产

- **入口**：`backend-go/cmd/server/main.go` — 配置加载、DB 初始化、优雅关闭
- **配置**：`backend-go/internal/config/config.go` — Viper + `configs/config.yaml` + `HUOBAO_` 环境变量
- **数据库**：
  - `backend-go/internal/database/db.go` — GORM + SQLite（WAL 模式）
  - `backend-go/internal/database/models.go` — 17 个 GORM 模型，匹配现有 SQLite schema
- **Handler**：
  - `backend-go/internal/handler/handler.go` — Handler 结构体 + DB 依赖注入
  - `backend-go/internal/handler/drama.go` — Drama 完整 CRUD（8 个端点）
  - `backend-go/internal/handler/episode.go` — Episode 端点（6 个端点，含 pipeline-status）
  - `backend-go/internal/handler/scene.go` — Scene CRUD（3 个端点）
  - `backend-go/internal/handler/character.go` — Character 更新/删除（2 个端点）
  - `backend-go/internal/handler/storyboard.go` — Storyboard CRUD（3 个端点 + 绑定校验）
  - `backend-go/internal/handler/errors.go` — 哨兵错误定义
  - `backend-go/internal/handler/health.go` — 健康检查
- **中间件**：`backend-go/internal/middleware/cors.go` — CORS 中间件
- **工具**：
  - `backend-go/internal/util/response.go` — 统一响应 `{code, data, message}`
  - `backend-go/internal/util/transform.go` — camelCase → snake_case 转换
  - `backend-go/internal/util/task_logger.go` — 结构化任务日志 + 敏感数据脱敏
- **路由**：`backend-go/internal/server/router.go` — 路由注册 + 优雅关闭
- **构建**：`backend-go/Makefile`、`backend-go/go.mod`

### 尚不存在的 Go 落地资产

- `internal/database/queries.go` — 独立查询辅助（当前查询内联在 handler 中）
- `internal/util/http.go` — HTTP 请求工具
- `internal/adapter/*` — AI Provider 适配器（Phase 2）
- `internal/service/*` — 生成服务（Phase 3）
- `internal/agent/*` — AI Agent 系统（Phase 5）
- `tests/integration/*`、`tests/compatibility/*`（Phase 7）

## 3. 阶段总览

| Phase | 名称 | TypeScript 基线 | Go 迁移进度 | 状态 | 说明 |
|---|---|---|---|---|---|
| 1 | Project Skeleton + DB + CRUD | 已存在 | 85% | 基本完成 | 核心 CRUD + 中间件 + 工具已落地；query helpers 和 HTTP util 待补齐 |
| 2 | AI Provider Adapter Layer | 已存在 | 0% | 未开始 | TS adapters 已齐全，Go adapters 未落地 |
| 3 | Generation Services | 已存在 | 0% | 未开始 | TS 生成链路已存在，Go service/handler 尚无 |
| 4 | FFmpeg + Merge + Grid | 已存在 | 0% | 未开始 | TS compose/merge/grid 已存在，Go 版本未开始 |
| 5 | AI Agent System | 已存在 | 0% | 未开始 | TS agents 已存在，Go agent core/tools 未开始 |
| 6 | Config Mgmt + Remaining Routes | 已存在 | 0% | 未开始 | TS 配置与 skills 路由存在，Go 侧未实现 |
| 7 | Testing + Docker + Deployment | 部分存在 | 0% | 未开始 | TS 有部分运行资产，但 Go 测试/部署未开始 |

## 4. 建议执行方式

### 原则

- `MIGRATION-PLAN.md` 继续作为迁移路线图，不直接改写为状态表。
- 本文件作为唯一的后端迁移状态入口。
- 每完成一个 Go 任务，同步更新：
  - 本文件阶段状态
  - 对应 Go 落地文件
  - 如有需要，再回填 `MIGRATION-PLAN.md` 的勾选状态

### 下一步执行顺序

**第一步：收尾 Phase 1 遗留（建议先做，为 Phase 2 打底）**

1. `internal/util/http.go` — HTTP 请求工具（Phase 2 adapter 必须依赖）
2. `internal/database/queries.go` — 抽取公共查询逻辑（减少 handler 内联重复）
3. 自定义 request logger 中间件（替换 gin.Logger()）

**第二步：启动 Phase 2 — AI Provider Adapter Layer**

1. AI Provider adapter 类型定义和核心接口（`internal/adapter/types.go`）
2. URL builder 和 registry（`internal/adapter/url_builder.go`、`registry.go`）
3. 按 provider 并行实现 image adapter（MiniMax、OpenAI、Gemini、VolcEngine、Ali、Chatfire）
4. 按 provider 并行实现 video adapter（MiniMax、VolcEngine、Vidu、Ali）
5. 实现 MiniMax TTS adapter

## 5. 执行清单

### Phase 1 — Project Skeleton + Database + Basic CRUD

- [x] Go module 初始化
- [x] `cmd/server/main.go`
- [x] `internal/config/config.go`
- [x] Makefile
- [x] SQLite 连接（GORM + WAL 模式 + busy_timeout）
- [x] auto-migration 系统（GORM AutoMigrate 17 个表）
- [x] 17 个数据模型（`internal/database/models.go`）
- [ ] query helpers（`internal/database/queries.go`）— 查询逻辑当前内联在 handler 中
- [x] handler foundation（`internal/handler/handler.go`）
- [x] drama CRUD（List、Create、Stats、Get、Update、Delete、UpsertCharacters、UpsertEpisodes）
- [x] episode handlers（Create、Update、GetCharacters、GetScenes、GetStoryboards、GetPipelineStatus）
- [x] scene handlers（Create、Update、Delete）
- [x] character handlers（Update、Delete）
- [x] storyboard handlers（Create、Update、Delete + 绑定校验 + 角色同步）
- [ ] request logger（当前使用 gin.Logger()，自定义版本待实现）
- [x] error handler（使用 gin.Recovery()，满足基本需求）
- [x] CORS middleware
- [x] response helpers（Success、Created、BadRequest、NotFound、ServerError）
- [x] transform utility（ToSnakeCase、ToSnakeCaseMap、ToSnakeCaseSlice）
- [x] task logger（LogTaskStart/Success/Error/Warn/Progress/Payload + 敏感数据脱敏）
- [ ] HTTP utility（`internal/util/http.go`）— 为 Phase 2 准备
- [x] router setup（路由注册 + SPA fallback + 静态文件）
- [x] graceful shutdown（SIGINT/SIGTERM + 30s timeout + DB close）

### Phase 2 — AI Provider Adapter Layer

- [ ] adapter types
- [ ] URL builder
- [ ] registry
- [ ] helper functions
- [ ] MiniMax image
- [ ] OpenAI image
- [ ] Gemini image
- [ ] VolcEngine image
- [ ] Ali image
- [ ] Chatfire image
- [ ] MiniMax video
- [ ] VolcEngine video
- [ ] Vidu video
- [ ] Ali video
- [ ] MiniMax TTS

### Phase 3 — Image / Video / TTS Generation Services

- [ ] AI config query service
- [ ] task recovery
- [ ] image generation service
- [ ] video generation service
- [ ] TTS service
- [ ] file storage
- [ ] image routes
- [ ] video routes
- [ ] upload route
- [ ] webhook handler
- [ ] scene image generation route
- [ ] character voice/image generation routes
- [ ] storyboard TTS route
- [ ] voice management routes

### Phase 4 — FFmpeg Compose + Merge + Grid

- [ ] FFmpeg compose service
- [ ] FFmpeg merge service
- [ ] grid split service
- [ ] compose routes
- [ ] merge routes
- [ ] grid routes
- [ ] DB query supplements

### Phase 5 — AI Agent System

- [ ] agent core
- [ ] agent HTTP helpers
- [ ] default prompts
- [ ] SKILL.md loader
- [ ] agent factory
- [ ] script tools
- [ ] extract tools
- [ ] storyboard tools
- [ ] voice tools
- [ ] grid prompt tools
- [ ] agent routes

### Phase 6 — Config Management + Remaining Routes

- [ ] AI config CRUD
- [ ] agent config CRUD
- [ ] skills management
- [ ] complete route registration

### Phase 7 — Testing + Docker + Deployment

- [ ] util tests
- [ ] adapter tests
- [ ] integration tests
- [ ] compatibility tests
- [ ] Dockerfile
- [ ] docker-compose
- [ ] Air hot-reload
- [ ] benchmark tests
- [ ] pprof integration
- [ ] SQLite -> PostgreSQL migration tool
- [ ] grayscale switch procedure
- [ ] rollback plan

## 6. Phase 1 验收自检

| 验收标准 | 状态 | 说明 |
|---|---|---|
| Go module compiles and starts | ✅ | `go build ./...` 和 `go vet ./...` 均通过 |
| SQLite connection + migrations work | ✅ | WAL 模式 + busy_timeout + AutoMigrate 17 表 |
| All basic CRUD endpoints return correct JSON | ✅ | Smoke test 验证全部端点 |
| Unified response format `{code, data, message}` matches TS | ✅ | 与 TypeScript 后端响应格式一致 |
| Middleware (CORS, error handler) active | ✅ | CORS + gin.Recovery() + gin.Logger() |
| Health check endpoint returns 200 | ✅ | `GET /api/v1/health` → `{"status":"ok",...}` |
| Static file serving works | ✅ | `/static/*` 映射到 `data/storage/` |
| Graceful shutdown works | ✅ | SIGINT/SIGTERM → 30s timeout → DB close |

## 7. 当前备注

- Phase 1 核心功能已落地，Go 后端可独立运行并与现有 SQLite 数据库兼容。
- 当前使用 SQLite（与 TS 后端共享 `data/huobao_drama.db`），后续迁移到 PostgreSQL 时需数据迁移工具。
- `internal/database/queries.go` 待补齐：当前查询逻辑内联在各 handler 中，可抽取公共查询以减少重复。
- Phase 2（AI Provider Adapter Layer）是下一步重点，需要先补齐 `internal/util/http.go` 工具。
- 响应格式严格匹配 TypeScript 后端的 `{code, data, message}` 信封格式，前端无需任何修改。
- 软删除逻辑（dramas、characters）和硬删除逻辑（scenes、storyboards）与 TS 后端行为一致。
- Storyboard 绑定校验（scene_id 和 character_ids 必须属于当前 episode）已实现。
- Episode pipeline-status 10 步进度计算已实现。