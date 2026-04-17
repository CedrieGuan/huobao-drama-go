# 后端 Go 重写 — 总览设计文档

> 项目：火宝短剧 (Huobao Drama)  
> 目标：将 TypeScript (Hono + Drizzle + Mastra) 后端完全重写为 Go  
> 文档版本：v1.0  
> 日期：2025-07

> 修订说明（2026-04）：
> 旧版文档默认 Go 重写后继续共享 SQLite，并在启动时执行 Auto-DDL。
> 该方案不再作为推荐路径。当前建议改为：
> - 生产主库使用 PostgreSQL 16+
> - Go 版数据访问层使用 GORM，复杂查询允许混用 Raw SQL
> - Schema 变更使用版本化 migration 工具管理，禁止生产依赖 `AutoMigrate`
> - SQLite 仅保留为历史数据导出源或本地临时开发用途

---

## 1. 背景

当前后端基于 Node.js 技术栈：

- **HTTP 框架**：Hono
- **ORM**：Drizzle ORM + better-sqlite3
- **AI Agent**：Mastra Core + AI SDK (@ai-sdk/openai, @ai-sdk/google)
- **媒体处理**：fluent-ffmpeg, sharp
- **运行时**：tsx (TypeScript 直接执行)

### 1.1 为什么要用 Go 重写

| 维度 | TS 现状 | Go 预期 |
|------|---------|---------|
| 内存占用 | ~150-300MB | ~20-50MB |
| 并发模型 | 单线程事件循环 | 原生多核 goroutine 并行 |
| SQLite 访问 | better-sqlite3 同步调用阻塞事件循环 | database/sql 原生连接池 |
| 冷启动 | tsx 加载大量 JS 模块 | 编译后二进制毫秒级启动 |
| Docker 镜像 | ~500MB (node_modules) | ~50MB (静态二进制 + ffmpeg) |
| FFmpeg 调用 | fluent-ffmpeg 封装层开销 | os/exec 直接调用 |
| 长时任务轮询 | setTimeout/Promise 链 | goroutine + ticker，天然适合 |
| 部署依赖 | Node.js 运行时 + npm | 单个静态编译二进制 |

### 1.2 重写约束

1. **前端零改动**：API 路径、请求参数、响应格式保持 100% 一致
2. **数据兼容**：保留现有 SQLite 数据内容，迁移至 PostgreSQL 后继续提供同等业务语义
3. **功能等价**：所有 TS 版功能必须在 Go 版中等价实现
4. **渐进替换**：先完成 SQLite → PostgreSQL 导入与影子验证，再切流到 Go 版

---

## 2. 现有系统分析

### 2.1 后端文件清单

```
backend/src/
├── index.ts                    # 入口，注册所有路由，启动 HTTP 服务
├── agents/
│   ├── index.ts                # Agent 工厂（5 种 Agent 类型）
│   ├── skills.ts               # SKILL.md 加载器
│   └── tools/
│       ├── script-tools.ts     # 剧本改写工具（read/save）
│       ├── extract-tools.ts    # 角色/场景提取工具（去重合并）
│       ├── storyboard-tools.ts # 分镜拆解工具（CRUD + 宫格提示词）
│       ├── voice-tools.ts      # 音色分配工具（列表 + 分配）
│       └── grid-prompt-tools.ts # 宫格提示词工具
├── db/
│   ├── index.ts                # SQLite 初始化 + Auto-DDL + ensureColumn
│   └── schema.ts               # 17 张表的 Drizzle schema 定义
├── middleware/
│   └── logger.ts               # 请求日志 + 全局错误恢复
├── routes/                     # 17 个路由文件，共 ~60 个 API 端点
│   ├── dramas.ts
│   ├── episodes.ts
│   ├── storyboards.ts
│   ├── scenes.ts
│   ├── characters.ts
│   ├── images.ts
│   ├── videos.ts
│   ├── upload.ts
│   ├── aiConfigs.ts
│   ├── agentConfigs.ts
│   ├── agent.ts
│   ├── compose.ts
│   ├── merge.ts
│   ├── grid.ts
│   ├── skills.ts
│   ├── aiVoices.ts
│   └── webhooks.ts
├── services/
│   ├── ai.ts                   # AI 配置查询（按 serviceType + priority）
│   ├── image-generation.ts     # 图片生成（同步/异步 + 轮询 + base64）
│   ├── video-generation.ts     # 视频生成（同步/异步 + 轮询 + Webhook）
│   ├── tts-generation.ts       # TTS 语音合成
│   ├── ffmpeg-compose.ts       # FFmpeg 单镜头合成（视频+音频+字幕）
│   ├── ffmpeg-merge.ts         # FFmpeg 多镜头拼接
│   ├── grid-split.ts           # 宫格图切割（sharp）
│   └── adapters/               # AI Provider 适配器（Adapter 模式）
│       ├── types.ts            # 接口定义
│       ├── registry.ts         # 注册表
│       ├── url.ts              # URL 构建工具
│       ├── minimax-image.ts
│       ├── minimax-video.ts
│       ├── minimax-tts.ts
│       ├── openai-image.ts
│       ├── gemini-image.ts
│       ├── volcengine-image.ts
│       ├── volcengine-video.ts
│       ├── vidu-video.ts
│       ├── ali-image.ts
│       └── ali-video.ts
└── utils/
    ├── response.ts             # 统一 JSON 响应 {code, data, message}
    ├── storage.ts              # 文件下载/上传/base64/图片压缩
    ├── transform.ts            # camelCase → snake_case
    └── task-logger.ts          # 结构化任务日志 + 敏感信息脱敏
```

### 2.2 数据库表清单（17 张）

| 表名 | 用途 |
|------|------|
| `dramas` | 剧集主表 |
| `episodes` | 分集 |
| `characters` | 角色 |
| `scenes` | 场景 |
| `storyboards` | 分镜 |
| `episode_characters` | 集-角色多对多 |
| `episode_scenes` | 集-场景多对多 |
| `storyboard_characters` | 分镜-角色多对多 |
| `ai_service_configs` | AI 服务配置（text/image/video/audio） |
| `ai_service_providers` | AI 服务商预设 |
| `ai_voices` | TTS 音色库 |
| `agent_configs` | Agent 配置 |
| `image_generations` | 图片生成记录 |
| `video_generations` | 视频生成记录 |
| `video_merges` | 视频合并记录 |
| `props` | 道具 |
| `assets` | 资产 |

### 2.3 API 端点清单

| 方法 | 路径 | 功能 |
|------|------|------|
| GET | `/api/v1/health` | 健康检查 |
| **Dramas** | | |
| GET | `/api/v1/dramas` | 剧集列表（分页/过滤） |
| POST | `/api/v1/dramas` | 创建剧集 |
| GET | `/api/v1/dramas/stats` | 剧集统计 |
| GET | `/api/v1/dramas/:id` | 剧集详情 |
| PUT | `/api/v1/dramas/:id` | 更新剧集 |
| DELETE | `/api/v1/dramas/:id` | 软删除剧集 |
| PUT | `/api/v1/dramas/:id/characters` | 批量更新角色 |
| PUT | `/api/v1/dramas/:id/episodes` | 批量更新集数 |
| **Episodes** | | |
| POST | `/api/v1/episodes` | 创建分集 |
| PUT | `/api/v1/episodes/:id` | 更新分集 |
| GET | `/api/v1/episodes/:id/characters` | 获取集关联角色 |
| GET | `/api/v1/episodes/:id/scenes` | 获取集关联场景 |
| GET | `/api/v1/episodes/:episode_id/storyboards` | 获取集分镜列表 |
| GET | `/api/v1/episodes/:id/pipeline-status` | 流水线进度 |
| **Storyboards** | | |
| POST | `/api/v1/storyboards` | 创建分镜 |
| PUT | `/api/v1/storyboards/:id` | 更新分镜 |
| DELETE | `/api/v1/storyboards/:id` | 删除分镜 |
| POST | `/api/v1/storyboards/:id/generate-tts` | 生成分镜 TTS |
| **Scenes** | | |
| POST | `/api/v1/scenes` | 创建场景 |
| PUT | `/api/v1/scenes/:id` | 更新场景 |
| DELETE | `/api/v1/scenes/:id` | 删除场景 |
| POST | `/api/v1/scenes/:id/generate-image` | 生成场景图 |
| **Characters** | | |
| PUT | `/api/v1/characters/:id` | 更新角色 |
| DELETE | `/api/v1/characters/:id` | 软删除角色 |
| POST | `/api/v1/characters/:id/generate-voice-sample` | 生成试听音频 |
| POST | `/api/v1/characters/:id/generate-image` | 生成角色图 |
| POST | `/api/v1/characters/batch-generate-images` | 批量生成角色图 |
| **Images** | | |
| POST | `/api/v1/images` | 提交图片生成任务 |
| GET | `/api/v1/images/:id` | 查询图片生成状态 |
| GET | `/api/v1/images` | 图片生成列表 |
| DELETE | `/api/v1/images/:id` | 删除图片记录 |
| **Videos** | | |
| POST | `/api/v1/videos` | 提交视频生成任务 |
| GET | `/api/v1/videos/:id` | 查询视频生成状态 |
| GET | `/api/v1/videos` | 视频生成列表 |
| DELETE | `/api/v1/videos/:id` | 删除视频记录 |
| **Upload** | | |
| POST | `/api/v1/upload/image` | 上传图片文件 |
| **AI Configs** | | |
| GET | `/api/v1/ai-configs` | AI 配置列表 |
| POST | `/api/v1/ai-configs` | 创建 AI 配置 |
| POST | `/api/v1/ai-configs/huobao-preset` | 一键预设配置 |
| POST | `/api/v1/ai-configs/test` | 测试 AI 连通性 |
| GET | `/api/v1/ai-configs/:id` | 获取单个配置 |
| PUT | `/api/v1/ai-configs/:id` | 更新配置 |
| DELETE | `/api/v1/ai-configs/:id` | 删除配置 |
| GET | `/api/v1/ai-providers` | AI 服务商列表 |
| **Agent Configs** | | |
| GET | `/api/v1/agent-configs` | Agent 配置列表 |
| GET | `/api/v1/agent-configs/:id` | 获取单个配置 |
| POST | `/api/v1/agent-configs` | 创建/更新配置 |
| PUT | `/api/v1/agent-configs/:id` | 更新配置 |
| DELETE | `/api/v1/agent-configs/:id` | 软删除配置 |
| **Agent** | | |
| POST | `/api/v1/agent/:type/chat` | Agent 对话 |
| GET | `/api/v1/agent/:type/debug` | Agent 调试 |
| **Compose** | | |
| POST | `/api/v1/compose/storyboards/:id/compose` | 单镜头合成 |
| POST | `/api/v1/compose/episodes/:id/compose-all` | 批量合成 |
| GET | `/api/v1/compose/episodes/:id/compose-status` | 合成进度 |
| **Merge** | | |
| POST | `/api/v1/merge/episodes/:id/merge` | 视频拼接 |
| GET | `/api/v1/merge/episodes/:id/merge` | 拼接状态 |
| **Grid** | | |
| POST | `/api/v1/grid/prompt` | 宫格提示词生成 |
| POST | `/api/v1/grid/generate` | 宫格图生成 |
| POST | `/api/v1/grid/split` | 宫格图切割 |
| GET | `/api/v1/grid/status/:id` | 宫格生成状态 |
| **Skills** | | |
| GET | `/api/v1/skills` | 技能列表 |
| GET | `/api/v1/skills/*` | 获取技能内容 |
| POST | `/api/v1/skills` | 创建技能 |
| PUT | `/api/v1/skills/*` | 更新技能 |
| DELETE | `/api/v1/skills/*` | 删除技能 |
| **AI Voices** | | |
| GET | `/api/v1/ai-voices` | 音色列表 |
| POST | `/api/v1/ai-voices/sync` | 同步音色库 |
| **Webhooks** | | |
| POST | `/webhooks/vidu` | Vidu 视频回调 |
| **Static** | | |
| GET | `/static/*` | 静态文件服务 |

### 2.4 AI Provider 适配器清单

| Provider | 图片 | 视频 | TTS |
|----------|------|------|-----|
| MiniMax | ✅ (sync/async) | ✅ (async poll) | ✅ (sync hex) |
| OpenAI | ✅ (DALL-E, url/base64) | — | — |
| Gemini | ✅ (base64) | — | — |
| VolcEngine | ✅ (async) | ✅ (async, 4-12s) | — |
| Vidu | — | ✅ (webhook only) | — |
| Ali (通义万相) | ✅ (DashScope async) | ✅ (DashScope async) | — |
| Chatfire | ✅ (复用 OpenAI) | — | — |

---

## 3. Go 版架构设计

### 3.1 项目目录结构

```
backend-go/
├── cmd/
│   └── server/
│       └── main.go                 # 程序入口
│
├── internal/
│   ├── config/
│   │   └── config.go               # 配置加载（YAML + 环境变量）
│   │
│   ├── database/
│   │   ├── db.go                   # PostgreSQL / GORM 初始化
│   │   ├── models.go               # GORM 模型（17 张表映射）
│   │   ├── queries.go              # 复杂查询与通用查询辅助函数
│   │   └── migrate/                # 版本化 SQL migrations
│   │
│   ├── handler/                    # HTTP Handler（对应 routes/）
│   │   ├── handler.go              # Handler 聚合结构体（持有 db 等依赖）
│   │   ├── drama.go
│   │   ├── episode.go
│   │   ├── storyboard.go
│   │   ├── scene.go
│   │   ├── character.go
│   │   ├── image.go
│   │   ├── video.go
│   │   ├── upload.go
│   │   ├── ai_config.go
│   │   ├── agent_config.go
│   │   ├── agent.go
│   │   ├── compose.go
│   │   ├── merge.go
│   │   ├── grid.go
│   │   ├── skill.go
│   │   ├── ai_voice.go
│   │   └── webhook.go
│   │
│   ├── service/                    # 业务逻辑层（对应 services/）
│   │   ├── ai_config.go            # AI 配置查询（按类型 + 优先级）
│   │   ├── image_gen.go            # 图片生成 + 异步轮询
│   │   ├── video_gen.go            # 视频生成 + 异步轮询 + Webhook
│   │   ├── tts_gen.go              # TTS 语音合成
│   │   ├── ffmpeg_compose.go       # FFmpeg 单镜头合成
│   │   ├── ffmpeg_merge.go         # FFmpeg 多镜头拼接
│   │   └── grid_split.go           # 宫格图切割
│   │
│   ├── adapter/                    # AI Provider 适配器
│   │   ├── types.go                # 接口定义
│   │   ├── registry.go             # 注册表
│   │   ├── url_builder.go          # URL 安全拼接
│   │   ├── minimax_image.go
│   │   ├── minimax_video.go
│   │   ├── minimax_tts.go
│   │   ├── openai_image.go
│   │   ├── gemini_image.go
│   │   ├── volcengine_image.go
│   │   ├── volcengine_video.go
│   │   ├── vidu_video.go
│   │   ├── ali_image.go
│   │   └── ali_video.go
│   │
│   ├── agent/                      # AI Agent 系统
│   │   ├── agent.go                # Agent 核心循环（Function Calling）
│   │   ├── prompts.go              # 5 种 Agent 的默认 Prompt
│   │   ├── skills.go               # SKILL.md 文件加载
│   │   └── tool/
│   │       ├── script_tools.go
│   │       ├── extract_tools.go
│   │       ├── storyboard_tools.go
│   │       ├── voice_tools.go
│   │       └── grid_prompt_tools.go
│   │
│   ├── middleware/
│   │   ├── logger.go               # 请求日志 + 全局错误恢复
│   │   └── cors.go                 # CORS 中间件
│   │
│   └── util/
│       ├── response.go             # 统一响应 {code, data, message}
│       ├── storage.go              # 文件下载/上传/base64/图片压缩
│       ├── transform.go            # camelCase → snake_case
│       └── task_logger.go          # 结构化日志 + 敏感信息脱敏
│
├── go.mod
├── go.sum
├── Makefile
└── Dockerfile
```

### 3.2 Go 技术栈选型

| 层面 | 选型 | 包路径 | 理由 |
|------|------|--------|------|
| HTTP 框架 | Gin | `github.com/gin-gonic/gin` | 最成熟，性能高，中间件生态丰富 |
| ORM | GORM | `gorm.io/gorm` | 团队熟悉、CRUD 和关联建模效率高 |
| PostgreSQL 驱动 | pgx / gorm postgres driver | `gorm.io/driver/postgres` | 生态成熟，连接池与生产能力稳定 |
| Migration | golang-migrate | `github.com/golang-migrate/migrate/v4` | 显式版本管理，可审计、可回滚 |
| 配置管理 | Viper | `github.com/spf13/viper` | 支持 YAML + 环境变量 + 热重载 |
| 结构化日志 | Zerolog | `github.com/rs/zerolog` | 高性能零分配 JSON 日志 |
| 图片处理 | Imaging | `github.com/disintegration/imaging` | 纯 Go，轻量，替代 sharp |
| UUID | Google UUID | `github.com/google/uuid` | 标准 UUID v4 |
| CORS | gin-contrib/cors | `github.com/gin-contrib/cors` | Gin 官方 CORS 中间件 |
| FFmpeg | os/exec | 标准库 | 直接调用 ffmpeg 命令行 |
| JSON Schema | gojsonschema | `github.com/xeipuuv/gojsonschema` | Agent 工具参数校验 |

### 3.3 核心设计模式

#### 3.3.1 依赖注入

```go
// Handler 聚合结构体，持有所有依赖
type Handler struct {
    DB  *sql.DB
}
```

每个 handler 文件定义接收者方法，如 `func (h *Handler) ListDramas(c *gin.Context)`。

#### 3.3.2 Adapter 模式（与 TS 版一致）

```
ImageProviderAdapter  (interface)
  ├── MiniMaxImageAdapter
  ├── OpenAIImageAdapter
  ├── GeminiImageAdapter
  ├── VolcEngineImageAdapter
  └── AliImageAdapter

VideoProviderAdapter  (interface)
  ├── MiniMaxVideoAdapter
  ├── VolcEngineVideoAdapter
  ├── ViduVideoAdapter
  └── AliVideoAdapter

TTSProviderAdapter    (interface)
  └── MiniMaxTTSAdapter
```

#### 3.3.3 Agent Function Calling 循环

Go 版手动实现 Mastra 的 `Agent.generate()` 逻辑：

```
User Message → LLM → tool_calls?
  ├── No  → 返回最终文本
  └── Yes → 执行每个 tool → 拼入 messages → 再次调用 LLM → (循环)
```

#### 3.3.4 异步任务处理

```go
// 提交任务后立即返回，goroutine 后台执行
func GenerateImage(params) (int64, error) {
    id := insertRecord(...)
    go processImageGeneration(id, config)
    return id, nil
}

// 轮询用 goroutine + ticker
func pollImageTask(id, config, taskID) {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()
    deadline := time.After(10 * time.Minute)
    for {
        select {
        case <-ticker.C: /* poll */
        case <-deadline: /* timeout */
        }
    }
}
```

---

## 4. 分阶段实施计划

### Phase 1 — 项目骨架 + 数据库 + 基础 CRUD

**范围：**
- Go module 初始化 + 目录结构搭建
- 配置加载（config.yaml）
- PostgreSQL 初始化（连接池、超时、健康检查）
- GORM 模型定义（17 张表）
- 首版版本化 migration
- SQLite → PostgreSQL 导入脚本
- 基础 CRUD 路由：dramas、episodes、characters、scenes、storyboards
- 统一响应格式 + 中间件（日志/CORS）
- 静态文件服务

**预计工时：** 3-4 天

**详细设计：** 参见 `docs/01-database-and-crud.md`

---

### Phase 2 — AI Provider Adapter 层

**范围：**
- 接口定义（ImageProviderAdapter、VideoProviderAdapter、TTSProviderAdapter）
- URL 构建工具
- 10 个 Provider 适配器实现
- 注册表

**预计工时：** 3-4 天

**详细设计：** 参见 `docs/02-adapters.md`

---

### Phase 3 — 图片/视频/TTS 生成服务

**范围：**
- AI 配置查询服务
- 图片生成服务（同步/异步 + 轮询 + base64 下载）
- 视频生成服务（同步/异步 + 轮询）
- TTS 语音合成服务
- Vidu Webhook 回调处理
- 相关路由（images、videos、upload、aiVoices、webhooks）
- 文件存储工具（下载/上传/base64 保存）

**预计工时：** 3-4 天

**详细设计：** 参见 `docs/03-generation-services.md`

---

### Phase 4 — FFmpeg 合成 + 拼接 + 宫格图

**范围：**
- FFmpeg 单镜头合成（视频 + TTS 音频 + SRT 字幕烧录）
- FFmpeg 多镜头拼接（concat demuxer）
- 宫格图切割
- 相关路由（compose、merge、grid）

**预计工时：** 2 天

**详细设计：** 参见 `docs/04-ffmpeg-and-grid.md`

---

### Phase 5 — AI Agent 系统

**范围：**
- Agent 核心循环（OpenAI Function Calling）
- 5 种 Agent 类型定义 + 默认 Prompt
- SKILL.md 文件加载器
- 5 组工具实现（script/extract/storyboard/voice/grid-prompt）
- Agent 路由
- Agent 配置 CRUD 路由

**预计工时：** 4-5 天

**详细设计：** 参见 `docs/05-agent-system.md`

---

### Phase 6 — 配置管理 + 剩余路由

**范围：**
- AI 配置 CRUD + 测试连通性 + 一键预设
- Agent 配置 CRUD
- 技能管理（文件系统 CRUD）
- 音色管理（列表 + 同步）
- 宫格图提示词路由

**预计工时：** 2 天

**详细设计：** 参见 `docs/06-config-and-remaining.md`

---

### Phase 7 — 集成测试 + Docker + 上线

**范围：**
- Dockerfile 重写（多阶段构建）
- Makefile（build/dev/test 命令）
- 更新 docker-compose.yml
- API 兼容性验证
- 性能基准测试

**预计工时：** 2 天

**详细设计：** 参见 `docs/07-testing-and-deployment.md`

---

## 5. 风险与注意事项

### 5.1 数据迁移切换

SQLite 与 PostgreSQL 不再共享同一份主数据。上线前必须准备：

- SQLite 全量导入脚本
- 切换窗口内的增量补录方案
- SQLite 备份与 PostgreSQL dump

### 5.2 GORM 使用边界

GORM 负责模型映射、事务和常规 CRUD，但以下场景建议直接写 SQL：

- 批量回填与导入
- 聚合统计
- 多表批处理
- 对性能敏感且 SQL 形态稳定的查询

### 5.3 前端兼容性验证

每个路由实现后需与 TS 版进行请求/响应对比测试。关键字段名必须保持 snake_case。

### 5.4 Migration 治理

禁止在生产启动流程里自动改表。所有 schema 变更必须通过 migration 文件进入版本控制。

### 5.5 Agent 工具参数

Agent 工具的 JSON Schema 定义必须与 TS 版 Zod Schema 完全一致，否则 LLM 生成的参数可能不匹配。

---

## 6. 文档索引

| 文档 | 内容 |
|------|------|
| `00-overview.md` | 本文档 — 总览 |
| `01-database-and-crud.md` | 数据库初始化 + 数据模型 + 基础 CRUD |
| `02-adapters.md` | AI Provider 适配器接口与实现 |
| `03-generation-services.md` | 图片/视频/TTS 生成服务 |
| `04-ffmpeg-and-grid.md` | FFmpeg 合成/拼接 + 宫格图 |
| `05-agent-system.md` | AI Agent 系统 |
| `06-config-and-remaining.md` | 配置管理 + 剩余路由 |
| `07-testing-and-deployment.md` | 测试与部署 |
