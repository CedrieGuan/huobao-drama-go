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
- 当前 Go 迁移状态：`已启动基础骨架`
- 当前 TypeScript 后端状态：`功能基线基本完整`
- 当前判断依据：
  - 当前后端仍是 TypeScript 实现，入口为 `backend/src/index.ts`。
  - `backend-go/` 已创建，已具备最小可运行 Gin 工程。
  - 当前 Go 落地仅限初始化骨架：`go.mod`、`cmd/server/main.go`、基础 `internal/` 目录、`Makefile`。
  - `MIGRATION-PLAN.md` 中除初始化骨架外，其余 Phase 1-7 交付物仍未落地。

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

### 尚不存在的 Go 落地资产

- `internal/database/*`
- `internal/handler/*` 的业务 handler
- `internal/service/*`
- `internal/adapter/*`
- `internal/agent/*`
- `tests/integration/*`
- `tests/compatibility/*`

## 3. 阶段总览

| Phase | 名称 | TypeScript 基线 | Go 迁移进度 | 状态 | 说明 |
|---|---|---|---:|---|---|
| 1 | Project Skeleton + DB + CRUD | 已存在 | 9% | 进行中 | 已创建 `backend-go/`、`go.mod`、Gin 入口、基础配置与 Makefile |
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

### 第一批应启动的任务

1. 建立 Go 工程骨架：`go.mod`、`cmd/server/main.go`、`internal/`
2. 落地配置系统与 PostgreSQL 连接
3. 迁移数据库模型与 migration 体系
4. 先完成 Phase 1 的健康检查、静态资源、基础 CRUD，再进入上层业务

## 5. 执行清单

### Phase 1 — Project Skeleton + Database + Basic CRUD

- [x] Go module 初始化
- [x] `cmd/server/main.go`
- [ ] `internal/config/config.go`
- [x] Makefile
- [ ] PostgreSQL 连接
- [ ] migration 系统
- [ ] 17 个数据模型
- [ ] query helpers
- [ ] handler foundation
- [ ] drama CRUD
- [ ] episode handlers
- [ ] scene handlers
- [ ] character handlers
- [ ] storyboard handlers
- [ ] request logger
- [ ] error handler
- [ ] CORS middleware
- [ ] response helpers
- [ ] transform utility
- [ ] task logger
- [ ] HTTP utility
- [ ] router setup
- [ ] graceful shutdown

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

## 6. 当前备注

- 当前可以把 `backend/src` 视为功能基线，不应视为 Go 迁移进度。
- `backend-go/` 已经建立，当前已完成最小工程初始化与编译验证。
- `cmd/server/main.go`、`internal/config/config.go`、`router setup` 目前是基础版本，距离计划中的完整实现还有差距，因此暂不勾选。
- 当前建议继续补齐 PostgreSQL、migration、models、基础 CRUD，再推进上层业务迁移。
