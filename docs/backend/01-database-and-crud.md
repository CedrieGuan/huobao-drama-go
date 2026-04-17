# Phase 1 — 项目骨架 + 数据库 + 基础 CRUD

> 对应 TS 文件：
> - `backend/src/index.ts` — 入口
> - `backend/src/db/index.ts` — 数据库初始化
> - `backend/src/db/schema.ts` — 表结构定义
> - `backend/src/routes/dramas.ts` — 剧集 CRUD
> - `backend/src/routes/episodes.ts` — 分集 CRUD
> - `backend/src/routes/characters.ts` — 角色操作
> - `backend/src/routes/scenes.ts` — 场景操作
> - `backend/src/routes/storyboards.ts` — 分镜 CRUD
> - `backend/src/middleware/logger.ts` — 日志中间件
> - `backend/src/utils/response.ts` — 统一响应
> - `backend/src/utils/transform.ts` — 字段名转换
> - `backend/src/utils/task-logger.ts` — 任务日志

> 修订说明（2026-04）：
> 本文档中原有“继续使用 SQLite + 启动时 Auto-DDL”的方案已废弃。
> 针对当前项目，推荐改为：
> - PostgreSQL 16+ 作为生产主库
> - GORM 作为主要数据访问层
> - `golang-migrate` 管理版本化 schema 变更
> - SQLite 仅作为历史数据源，通过一次性导入脚本迁移到 PostgreSQL
>
> 下文若仍出现 SQLite / Auto-DDL 示例，均视为历史草案；数据库迁移方案以本节新增内容为准。

---

## 0. 修订后的数据库迁移结论

### 0.1 推荐结论

我建议这次 Go 重写不要继续把 SQLite 当生产主库，而是直接切到 PostgreSQL，并把 GORM 作为 Go 侧 ORM。

原因很直接：

1. 当前后端已经不是单纯 CRUD 应用，而是有图片/视频生成、轮询、Webhook、任务恢复、FFmpeg 合成等长任务流程。
2. 这些流程会放大 SQLite 的单写入瓶颈，也会让“共享一个 DB 文件做灰度”的方案越来越脆弱。
3. 你已经熟悉 GORM，而现有库表本身也带明显的 GORM 风格命名痕迹，切回 GORM 的迁移成本可控。
4. 现在的 TS 版并没有严肃的版本化 migration 体系，`backend/src/db/index.ts` 直接执行 `CREATE TABLE IF NOT EXISTS`。如果本轮不把 schema 治理方式一起改掉，后面只会更难收拾。

### 0.2 目标方案

- 主库：PostgreSQL 16+
- ORM：GORM
- Migration：`golang-migrate`
- 启动策略：应用启动只做连接检查，不做生产自动改表
- SQLite 定位：旧数据导出源、本地临时调试，不再作为生产主库

### 0.3 为什么是 GORM，而不是继续手写 SQL 或继续类 Drizzle 方案

这个项目的核心数据层特征是：

- 表不少，但查询形态以业务 CRUD、关联加载、状态更新为主
- 真正复杂的地方在任务编排和外部服务适配，不在 SQL 本身
- 需要较多“按表建模 + 事务 + 软删除 + 时间戳”的稳定套路

在这种场景下，GORM 是合理选择，但要加两个边界：

1. 不依赖 `AutoMigrate` 做生产 schema 管理
2. 聚合统计、批量导入、性能敏感查询直接写 Raw SQL

### 0.4 建议的落地步骤

1. 用 GORM 定义 17 张核心表模型，字段名继续对齐现有 snake_case 列名。
2. 用 `golang-migrate` 生成 PostgreSQL 初始 schema，而不是让应用在启动时建表。
3. 写一个一次性导入工具，把当前 SQLite 中的数据迁移到 PostgreSQL。
4. 在 Go 版上做影子验证和接口兼容验证。
5. 切换窗口暂停 TS 写流量，执行最后一次增量补录，再切流。

### 0.5 建议的依赖替换

```go
require (
    github.com/gin-contrib/cors v1.7.3
    github.com/gin-gonic/gin v1.10.0
    github.com/golang-migrate/migrate/v4 v4.18.3
    github.com/google/uuid v1.6.0
    github.com/rs/zerolog v1.3.0
    github.com/spf13/viper v1.19.0
    gorm.io/driver/postgres v1.6.0
    gorm.io/gorm v1.31.0
)
```

### 0.6 建议的目录调整

```text
internal/database/
├── db.go               # GORM / PostgreSQL 初始化
├── models.go           # GORM 模型
├── queries.go          # Raw SQL / 辅助查询
└── migrate/            # 版本化 SQL migrations

cmd/
└── import-sqlite/      # 一次性 SQLite -> PostgreSQL 导入工具
```

### 0.7 数据切换原则

- 不做“双主库长期并行”
- 不让 TS 版和 Go 版长期分别写 SQLite / PostgreSQL 两套真数据
- 正式切换前必须保留 SQLite 原始备份和 PostgreSQL 导入校验结果
- 如果要回滚，优先回滚流量，不在事故处理中手工改库

---

## 1. Go Module 初始化

### 1.1 go.mod

```
module github.com/huobao-drama/backend-go

go 1.23

require (
    github.com/gin-contrib/cors v1.7.3
    github.com/gin-gonic/gin v1.10.0
    github.com/google/uuid v1.6.0
    github.com/mattn/go-sqlite3 v1.14.24
    github.com/Masterminds/squirrel v1.5.4
    github.com/rs/zerolog v1.3.0
    github.com/spf13/viper v1.19.0
    github.com/disintegration/imaging v1.6.2
)
```

### 1.2 Makefile

```makefile
.PHONY: dev build clean test

DB_PATH ?= ../data/huobao_drama.db
PORT ?= 5679

dev:
	CGO_ENABLED=1 go run ./cmd/server -db=$(DB_PATH) -port=$(PORT)

build:
	CGO_ENABLED=1 go build -o bin/server ./cmd/server

clean:
	rm -rf bin/

test:
	go test ./...
```

---

## 2. 程序入口

### 2.1 cmd/server/main.go

```go
package main

import (
    "context"
    "flag"
    "fmt"
    "net/http"
    "os"
    "os/signal"
    "syscall"
    "time"

    "github.com/huobao-drama/backend-go/internal/config"
    "github.com/huobao-drama/backend-go/internal/database"
    "github.com/huobao-drama/backend-go/internal/handler"
    "github.com/huobao-drama/backend-go/internal/middleware"
    "github.com/huobao-drama/backend-go/internal/service"
    "github.com/rs/zerolog/log"
)

func main() {
    dbPath := flag.String("db", "./data/huobao_drama.db", "SQLite database path")
    port := flag.Int("port", 5679, "HTTP server port")
    staticDir := flag.String("static", "./data", "Static files directory")
    flag.Parse()

    // 1. 加载配置
    cfg := config.Load()
    _ = cfg

    // 2. 初始化数据库
    db, err := database.Init(*dbPath)
    if err != nil {
        log.Fatal().Err(err).Msg("Failed to initialize database")
    }
    defer db.Close()

    // 3. 创建 Handler（依赖注入）
    h := handler.New(db)

    // 4. 恢复需要继续处理的异步任务
    if err := service.ResumePendingTasks(db); err != nil {
        log.Warn().Err(err).Msg("Resume pending tasks failed")
    }

    // 5. 设置路由
    r := setupRouter(h, *staticDir)

    // 6. 启动服务
    addr := fmt.Sprintf(":%d", *port)
    srv := &http.Server{Addr: addr, Handler: r}

    go func() {
        log.Info().Str("addr", addr).Msg("🚀 Huobao Drama Go server starting")
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatal().Err(err).Msg("Server failed")
        }
    }()

    // 7. 优雅关闭
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit
    log.Info().Msg("Shutting down server...")

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()
    if err := srv.Shutdown(ctx); err != nil {
        log.Warn().Err(err).Msg("Graceful shutdown timed out")
    }
}
```

### 2.2 路由注册

```go
func setupRouter(h *handler.Handler, staticDir string) *gin.Engine {
    r := gin.New()

    // 全局中间件
    r.Use(middleware.RequestLogger())
    r.Use(middleware.ErrorHandler())
    r.Use(middleware.CORS())
    r.Use(gin.Recovery())

    // 健康检查
    r.GET("/api/v1/health", h.Health)

    // API v1 路由组
    v1 := r.Group("/api/v1")
    {
        // Dramas
        v1.GET("/dramas", h.ListDramas)
        v1.POST("/dramas", h.CreateDrama)
        v1.GET("/dramas/stats", h.DramaStats)
        v1.GET("/dramas/:id", h.GetDrama)
        v1.PUT("/dramas/:id", h.UpdateDrama)
        v1.DELETE("/dramas/:id", h.DeleteDrama)
        v1.PUT("/dramas/:id/characters", h.UpsertDramaCharacters)
        v1.PUT("/dramas/:id/episodes", h.UpsertDramaEpisodes)

        // Episodes
        v1.POST("/episodes", h.CreateEpisode)
        v1.PUT("/episodes/:id", h.UpdateEpisode)
        v1.GET("/episodes/:id/characters", h.GetEpisodeCharacters)
        v1.GET("/episodes/:id/scenes", h.GetEpisodeScenes)
        v1.GET("/episodes/:episode_id/storyboards", h.GetEpisodeStoryboards)
        v1.GET("/episodes/:id/pipeline-status", h.GetEpisodePipelineStatus)

        // Storyboards
        v1.POST("/storyboards", h.CreateStoryboard)
        v1.PUT("/storyboards/:id", h.UpdateStoryboard)
        v1.DELETE("/storyboards/:id", h.DeleteStoryboard)
        v1.POST("/storyboards/:id/generate-tts", h.GenerateStoryboardTTS)

        // Scenes
        v1.POST("/scenes", h.CreateScene)
        v1.PUT("/scenes/:id", h.UpdateScene)
        v1.DELETE("/scenes/:id", h.DeleteScene)
        v1.POST("/scenes/:id/generate-image", h.GenerateSceneImage)

        // Characters
        v1.PUT("/characters/:id", h.UpdateCharacter)
        v1.DELETE("/characters/:id", h.DeleteCharacter)
        v1.POST("/characters/:id/generate-voice-sample", h.GenerateCharacterVoiceSample)
        v1.POST("/characters/:id/generate-image", h.GenerateCharacterImage)
        v1.POST("/characters/batch-generate-images", h.BatchGenerateCharacterImages)

        // Images
        v1.POST("/images", h.GenerateImage)
        v1.GET("/images/:id", h.GetImage)
        v1.GET("/images", h.ListImages)
        v1.DELETE("/images/:id", h.DeleteImage)

        // Videos
        v1.POST("/videos", h.GenerateVideo)
        v1.GET("/videos/:id", h.GetVideo)
        v1.GET("/videos", h.ListVideos)
        v1.DELETE("/videos/:id", h.DeleteVideo)

        // Upload
        v1.POST("/upload/image", h.UploadImage)

        // AI Configs
        v1.GET("/ai-configs", h.ListAIConfigs)
        v1.POST("/ai-configs", h.CreateAIConfig)
        v1.POST("/ai-configs/huobao-preset", h.HuobaoPreset)
        v1.POST("/ai-configs/test", h.TestAIConfig)
        v1.GET("/ai-configs/:id", h.GetAIConfig)
        v1.PUT("/ai-configs/:id", h.UpdateAIConfig)
        v1.DELETE("/ai-configs/:id", h.DeleteAIConfig)
        v1.GET("/ai-providers", h.ListAIProviders)

        // Agent Configs
        v1.GET("/agent-configs", h.ListAgentConfigs)
        v1.GET("/agent-configs/:id", h.GetAgentConfig)
        v1.POST("/agent-configs", h.CreateAgentConfig)
        v1.PUT("/agent-configs/:id", h.UpdateAgentConfig)
        v1.DELETE("/agent-configs/:id", h.DeleteAgentConfig)

        // Agent Chat
        v1.POST("/agent/:type/chat", h.AgentChat)
        v1.GET("/agent/:type/debug", h.AgentDebug)

        // Compose
        v1.POST("/compose/storyboards/:id/compose", h.ComposeStoryboard)
        v1.POST("/compose/episodes/:id/compose-all", h.ComposeAll)
        v1.GET("/compose/episodes/:id/compose-status", h.ComposeStatus)

        // Merge
        v1.POST("/merge/episodes/:id/merge", h.MergeEpisode)
        v1.GET("/merge/episodes/:id/merge", h.MergeStatus)

        // Grid
        v1.POST("/grid/prompt", h.GridPrompt)
        v1.POST("/grid/generate", h.GridGenerate)
        v1.POST("/grid/split", h.GridSplit)
        v1.GET("/grid/status/:id", h.GridStatus)

        // Skills
        v1.GET("/skills", h.ListSkills)
        v1.GET("/skills/*id", h.GetSkill)
        v1.POST("/skills", h.CreateSkill)
        v1.PUT("/skills/*id", h.UpdateSkill)
        v1.DELETE("/skills/*id", h.DeleteSkill)

        // AI Voices
        v1.GET("/ai-voices", h.ListAIVoices)
        v1.POST("/ai-voices/sync", h.SyncAIVoices)
    }

    // Webhooks（不在 /api/v1 下）
    r.POST("/webhooks/vidu", h.ViduWebhook)

    // 静态文件
    r.Static("/static", staticDir)

    // 托管前端生产构建，与 TS 版保持一致
    frontendDist := filepath.Join(projectRoot, "frontend", "dist")
    r.StaticFS("/", gin.Dir(frontendDist, false))
    r.NoRoute(func(c *gin.Context) {
        if strings.HasPrefix(c.Request.URL.Path, "/api/") || strings.HasPrefix(c.Request.URL.Path, "/webhooks/") {
            util.NotFound(c, "route not found")
            return
        }
        c.File(filepath.Join(frontendDist, "index.html"))
    })

    return r
}
```

---

## 3. 数据库初始化

### 3.1 internal/database/db.go

与 TS 版 `backend/src/db/index.ts` 完全对齐。

**关键逻辑：**
1. 打开 SQLite 文件，启用 WAL + busy_timeout
2. 执行 `CREATE TABLE IF NOT EXISTS` 创建全部 17 张表
3. 执行 `ensureColumn` 检查并补充缺失的列
4. 执行 `CREATE INDEX IF NOT EXISTS` 补齐现有 TS 版依赖的索引

```go
package database

import (
    "database/sql"
    "fmt"
    "time"

    _ "github.com/mattn/go-sqlite3"
    "github.com/rs/zerolog/log"
)

func Init(dbPath string) (*sql.DB, error) {
    db, err := sql.Open("sqlite3", dbPath+"?_journal_mode=WAL&_busy_timeout=30000")
    if err != nil {
        return nil, fmt.Errorf("open db: %w", err)
    }

    // SQLite 优化
    db.SetMaxOpenConns(1) // 写入串行
    db.SetMaxIdleConns(10)

    // PRAGMA
    db.Exec("PRAGMA journal_mode=WAL")
    db.Exec("PRAGMA busy_timeout=30000")
    db.Exec("PRAGMA foreign_keys=ON")

    // 建表
    if err := createTables(db); err != nil {
        return nil, fmt.Errorf("create tables: %w", err)
    }

    // 建索引
    if err := createIndexes(db); err != nil {
        return nil, fmt.Errorf("create indexes: %w", err)
    }

    // 补列
    ensureColumns(db)

    log.Info().Str("path", dbPath).Msg("Database initialized")
    return db, nil
}

func createTables(db *sql.DB) error {
    stmts := []string{
        `CREATE TABLE IF NOT EXISTS dramas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            genre TEXT,
            style TEXT DEFAULT 'realistic',
            total_episodes INTEGER DEFAULT 1,
            total_duration INTEGER DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'draft',
            thumbnail TEXT,
            tags TEXT,
            metadata TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS episodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drama_id INTEGER NOT NULL,
            episode_number INTEGER NOT NULL,
            title TEXT NOT NULL,
            content TEXT,
            script_content TEXT,
            description TEXT,
            duration INTEGER DEFAULT 0,
            status TEXT DEFAULT 'draft',
            video_url TEXT,
            thumbnail TEXT,
            image_config_id INTEGER,
            video_config_id INTEGER,
            audio_config_id INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS characters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drama_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            role TEXT,
            description TEXT,
            appearance TEXT,
            personality TEXT,
            voice_style TEXT,
            image_url TEXT,
            reference_images TEXT,
            seed_value TEXT,
            sort_order INTEGER,
            local_path TEXT,
            voice_sample_url TEXT,
            voice_provider TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS episode_characters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            episode_id INTEGER NOT NULL,
            character_id INTEGER NOT NULL,
            created_at TEXT NOT NULL
        )`,

        `CREATE TABLE IF NOT EXISTS scenes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drama_id INTEGER NOT NULL,
            episode_id INTEGER,
            location TEXT NOT NULL,
            time TEXT NOT NULL,
            prompt TEXT NOT NULL,
            storyboard_count INTEGER DEFAULT 1,
            image_url TEXT,
            status TEXT DEFAULT 'pending',
            local_path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS episode_scenes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            episode_id INTEGER NOT NULL,
            scene_id INTEGER NOT NULL,
            created_at TEXT NOT NULL
        )`,

        `CREATE TABLE IF NOT EXISTS storyboards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            episode_id INTEGER NOT NULL,
            scene_id INTEGER,
            storyboard_number INTEGER NOT NULL,
            title TEXT,
            location TEXT,
            time TEXT,
            shot_type TEXT,
            angle TEXT,
            movement TEXT,
            action TEXT,
            result TEXT,
            atmosphere TEXT,
            image_prompt TEXT,
            video_prompt TEXT,
            bgm_prompt TEXT,
            sound_effect TEXT,
            dialogue TEXT,
            description TEXT,
            duration INTEGER DEFAULT 0,
            composed_image TEXT,
            first_frame_image TEXT,
            last_frame_image TEXT,
            reference_images TEXT,
            video_url TEXT,
            tts_audio_url TEXT,
            subtitle_url TEXT,
            composed_video_url TEXT,
            status TEXT DEFAULT 'pending',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS storyboard_characters (
            storyboard_id INTEGER NOT NULL,
            character_id INTEGER NOT NULL,
            PRIMARY KEY (storyboard_id, character_id)
        )`,

        `CREATE TABLE IF NOT EXISTS ai_service_configs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            service_type TEXT NOT NULL,
            provider TEXT,
            name TEXT NOT NULL,
            base_url TEXT NOT NULL,
            api_key TEXT NOT NULL,
            model TEXT,
            endpoint TEXT,
            query_endpoint TEXT,
            priority INTEGER DEFAULT 0,
            is_default INTEGER DEFAULT 0,
            is_active INTEGER DEFAULT 1,
            settings TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )`,

        `CREATE TABLE IF NOT EXISTS ai_service_providers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            display_name TEXT,
            service_type TEXT NOT NULL,
            provider TEXT NOT NULL,
            default_url TEXT,
            preset_models TEXT,
            description TEXT,
            is_active INTEGER DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )`,

        `CREATE TABLE IF NOT EXISTS ai_voices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            voice_id TEXT NOT NULL UNIQUE,
            voice_name TEXT NOT NULL,
            description TEXT,
            language TEXT,
            provider TEXT NOT NULL,
            created_at TEXT NOT NULL
        )`,

        `CREATE TABLE IF NOT EXISTS agent_configs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            agent_type TEXT NOT NULL,
            name TEXT NOT NULL,
            description TEXT,
            model TEXT,
            system_prompt TEXT,
            temperature REAL,
            max_tokens INTEGER,
            max_iterations INTEGER,
            is_active INTEGER DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS image_generations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            storyboard_id INTEGER,
            drama_id INTEGER,
            scene_id INTEGER,
            character_id INTEGER,
            prop_id INTEGER,
            image_type TEXT,
            frame_type TEXT,
            provider TEXT,
            prompt TEXT,
            negative_prompt TEXT,
            model TEXT,
            size TEXT,
            quality TEXT,
            style TEXT,
            steps INTEGER,
            cfg_scale REAL,
            seed INTEGER,
            image_url TEXT,
            minio_url TEXT,
            local_path TEXT,
            status TEXT DEFAULT 'pending',
            task_id TEXT,
            error_msg TEXT,
            width INTEGER,
            height INTEGER,
            reference_images TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            completed_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS video_generations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            storyboard_id INTEGER,
            drama_id INTEGER,
            provider TEXT,
            prompt TEXT,
            model TEXT,
            image_gen_id INTEGER,
            reference_mode TEXT,
            image_url TEXT,
            first_frame_url TEXT,
            last_frame_url TEXT,
            reference_image_urls TEXT,
            duration INTEGER,
            fps INTEGER,
            resolution TEXT,
            aspect_ratio TEXT,
            style TEXT,
            motion_level INTEGER,
            camera_motion TEXT,
            seed INTEGER,
            video_url TEXT,
            minio_url TEXT,
            local_path TEXT,
            status TEXT DEFAULT 'pending',
            task_id TEXT,
            error_msg TEXT,
            width INTEGER,
            height INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            completed_at TEXT,
            deleted_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS video_merges (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            episode_id INTEGER,
            drama_id INTEGER,
            title TEXT,
            provider TEXT,
            model TEXT,
            status TEXT DEFAULT 'pending',
            scenes TEXT,
            merged_url TEXT,
            duration INTEGER,
            task_id TEXT,
            error_msg TEXT,
            created_at TEXT NOT NULL,
            completed_at TEXT,
            deleted_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS props (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drama_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            type TEXT,
            description TEXT,
            prompt TEXT,
            image_url TEXT,
            reference_images TEXT,
            local_path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        )`,

        `CREATE TABLE IF NOT EXISTS assets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            drama_id INTEGER,
            episode_id INTEGER,
            storyboard_id INTEGER,
            storyboard_num INTEGER,
            name TEXT,
            description TEXT,
            type TEXT,
            category TEXT,
            url TEXT,
            thumbnail_url TEXT,
            local_path TEXT,
            file_size INTEGER,
            mime_type TEXT,
            width INTEGER,
            height INTEGER,
            duration INTEGER,
            format TEXT,
            image_gen_id INTEGER,
            video_gen_id INTEGER,
            is_favorite INTEGER DEFAULT 0,
            view_count INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT
        )`,
    }

    for _, s := range stmts {
        if _, err := db.Exec(s); err != nil {
            return fmt.Errorf("create table: %w", err)
        }
    }
    return nil
}

// ensureColumn 检查表中是否存在某列，不存在则 ALTER TABLE 添加
func ensureColumn(db *sql.DB, table, column, colDef string) {
    var count int
    row := db.QueryRow(
        "SELECT COUNT(*) FROM pragma_table_info(?) WHERE name = ?",
        table, column,
    )
    if err := row.Scan(&count); err != nil {
        log.Warn().Err(err).Str("table", table).Str("column", column).Msg("check column failed")
        return
    }
    if count == 0 {
        sql := fmt.Sprintf("ALTER TABLE %s ADD COLUMN %s %s", table, column, colDef)
        if _, err := db.Exec(sql); err != nil {
            log.Warn().Err(err).Str("table", table).Str("column", column).Msg("add column failed")
        } else {
            log.Info().Str("table", table).Str("column", column).Msg("Column added")
        }
    }
}

func ensureColumns(db *sql.DB) {
    // 与 TS 版 ensureColumn 调用一一对应
    ensureColumn(db, "episodes", "image_config_id", "INTEGER")
    ensureColumn(db, "episodes", "video_config_id", "INTEGER")
    ensureColumn(db, "episodes", "audio_config_id", "INTEGER")
}

func createIndexes(db *sql.DB) error {
    stmts := []string{
        `CREATE INDEX IF NOT EXISTS idx_episode_characters_episode_id ON episode_characters (episode_id)`,
        `CREATE INDEX IF NOT EXISTS idx_episode_characters_character_id ON episode_characters (character_id)`,
        `CREATE INDEX IF NOT EXISTS idx_episode_scenes_episode_id ON episode_scenes (episode_id)`,
        `CREATE INDEX IF NOT EXISTS idx_episode_scenes_scene_id ON episode_scenes (scene_id)`,
        `CREATE INDEX IF NOT EXISTS idx_storyboard_characters_storyboard_id ON storyboard_characters (storyboard_id)`,
        `CREATE INDEX IF NOT EXISTS idx_storyboard_characters_character_id ON storyboard_characters (character_id)`,
    }
    for _, s := range stmts {
        if _, err := db.Exec(s); err != nil {
            return err
        }
    }
    return nil
}
```

---

## 4. 数据模型

### 4.1 internal/database/models.go

每个 Go struct 的字段名使用 PascalCase，数据库 tag 使用 snake_case 列名（与 TS 版 schema 精确对齐）。

```go
package database

import (
    "database/sql"
    "encoding/json"
    "time"
)

// ========== Null 辅助类型 ==========

// NullString 包装 sql.NullString，实现 JSON 序列化
type NullString struct {
    sql.NullString
}

func (ns NullString) MarshalJSON() ([]byte, error) {
    if !ns.Valid {
        return []byte("null"), nil
    }
    return json.Marshal(ns.String)
}

func (ns *NullString) UnmarshalJSON(data []byte) error {
    if string(data) == "null" {
        ns.Valid = false
        return nil
    }
    ns.Valid = true
    return json.Unmarshal(data, &ns.String)
}

// NullInt64 包装 sql.NullInt64
type NullInt64 struct {
    sql.NullInt64
}

func (ni NullInt64) MarshalJSON() ([]byte, error) {
    if !ni.Valid {
        return []byte("null"), nil
    }
    return json.Marshal(ni.Int64)
}

// NullFloat64 包装 sql.NullFloat64
type NullFloat64 struct {
    sql.NullFloat64
}

func (nf NullFloat64) MarshalJSON() ([]byte, error) {
    if !nf.Valid {
        return []byte("null"), nil
    }
    return json.Marshal(nf.Float64)
}

// NullBool 包装 sql.NullBool
type NullBool struct {
    sql.NullBool
}

func (nb NullBool) MarshalJSON() ([]byte, error) {
    if !nb.Valid {
        return []byte("null"), nil
    }
    return json.Marshal(nb.Bool)
}

// ========== 业务模型 ==========

// Drama 剧集
type Drama struct {
    ID            int64       `json:"id" db:"id"`
    Title         string      `json:"title" db:"title"`
    Description   NullString  `json:"description" db:"description"`
    Genre         NullString  `json:"genre" db:"genre"`
    Style         NullString  `json:"style" db:"style"`
    TotalEpisodes int         `json:"total_episodes" db:"total_episodes"`
    TotalDuration int         `json:"total_duration" db:"total_duration"`
    Status        string      `json:"status" db:"status"`
    Thumbnail     NullString  `json:"thumbnail" db:"thumbnail"`
    Tags          NullString  `json:"tags" db:"tags"`
    Metadata      NullString  `json:"metadata" db:"metadata"`
    CreatedAt     string      `json:"created_at" db:"created_at"`
    UpdatedAt     string      `json:"updated_at" db:"updated_at"`
    DeletedAt     NullString  `json:"deleted_at" db:"deleted_at"`
    // 关联数据（不映射 DB 列，运行时填充）
    Episodes  []Episode   `json:"episodes,omitempty" db:"-"`
    Characters []Character `json:"characters,omitempty" db:"-"`
    Scenes    []Scene     `json:"scenes,omitempty" db:"-"`
    Props     []Prop      `json:"props,omitempty" db:"-"`
}

// Episode 分集
type Episode struct {
    ID            int64      `json:"id" db:"id"`
    DramaID       int64      `json:"drama_id" db:"drama_id"`
    EpisodeNumber int        `json:"episode_number" db:"episode_number"`
    Title         string     `json:"title" db:"title"`
    Content       NullString `json:"content" db:"content"`
    ScriptContent NullString `json:"script_content" db:"script_content"`
    Description   NullString `json:"description" db:"description"`
    Duration      int        `json:"duration" db:"duration"`
    Status        NullString `json:"status" db:"status"`
    VideoURL      NullString `json:"video_url" db:"video_url"`
    Thumbnail     NullString `json:"thumbnail" db:"thumbnail"`
    ImageConfigID NullInt64  `json:"image_config_id" db:"image_config_id"`
    VideoConfigID NullInt64  `json:"video_config_id" db:"video_config_id"`
    AudioConfigID NullInt64  `json:"audio_config_id" db:"audio_config_id"`
    CreatedAt     string     `json:"created_at" db:"created_at"`
    UpdatedAt     string     `json:"updated_at" db:"updated_at"`
    DeletedAt     NullString `json:"deleted_at" db:"deleted_at"`
}

// Character 角色
type Character struct {
    ID              int64      `json:"id" db:"id"`
    DramaID         int64      `json:"drama_id" db:"drama_id"`
    Name            string     `json:"name" db:"name"`
    Role            NullString `json:"role" db:"role"`
    Description     NullString `json:"description" db:"description"`
    Appearance      NullString `json:"appearance" db:"appearance"`
    Personality     NullString `json:"personality" db:"personality"`
    VoiceStyle      NullString `json:"voice_style" db:"voice_style"`
    ImageURL        NullString `json:"image_url" db:"image_url"`
    ReferenceImages NullString `json:"reference_images" db:"reference_images"`
    SeedValue       NullString `json:"seed_value" db:"seed_value"`
    SortOrder       NullInt64  `json:"sort_order" db:"sort_order"`
    LocalPath       NullString `json:"local_path" db:"local_path"`
    VoiceSampleURL  NullString `json:"voice_sample_url" db:"voice_sample_url"`
    VoiceProvider   NullString `json:"voice_provider" db:"voice_provider"`
    CreatedAt       string     `json:"created_at" db:"created_at"`
    UpdatedAt       string     `json:"updated_at" db:"updated_at"`
    DeletedAt       NullString `json:"deleted_at" db:"deleted_at"`
}

// Scene 场景
type Scene struct {
    ID             int64      `json:"id" db:"id"`
    DramaID        int64      `json:"drama_id" db:"drama_id"`
    EpisodeID      NullInt64  `json:"episode_id" db:"episode_id"`
    Location       string     `json:"location" db:"location"`
    Time           string     `json:"time" db:"time"`
    Prompt         string     `json:"prompt" db:"prompt"`
    StoryboardCount int       `json:"storyboard_count" db:"storyboard_count"`
    ImageURL       NullString `json:"image_url" db:"image_url"`
    Status         NullString `json:"status" db:"status"`
    LocalPath      NullString `json:"local_path" db:"local_path"`
    CreatedAt      string     `json:"created_at" db:"created_at"`
    UpdatedAt      string     `json:"updated_at" db:"updated_at"`
    DeletedAt      NullString `json:"deleted_at" db:"deleted_at"`
}

// Storyboard 分镜
type Storyboard struct {
    ID               int64      `json:"id" db:"id"`
    EpisodeID        int64      `json:"episode_id" db:"episode_id"`
    SceneID          NullInt64  `json:"scene_id" db:"scene_id"`
    StoryboardNumber int        `json:"storyboard_number" db:"storyboard_number"`
    Title            NullString `json:"title" db:"title"`
    Location         NullString `json:"location" db:"location"`
    Time             NullString `json:"time" db:"time"`
    ShotType         NullString `json:"shot_type" db:"shot_type"`
    Angle            NullString `json:"angle" db:"angle"`
    Movement         NullString `json:"movement" db:"movement"`
    Action           NullString `json:"action" db:"action"`
    Result           NullString `json:"result" db:"result"`
    Atmosphere       NullString `json:"atmosphere" db:"atmosphere"`
    ImagePrompt      NullString `json:"image_prompt" db:"image_prompt"`
    VideoPrompt      NullString `json:"video_prompt" db:"video_prompt"`
    BGMPrompt        NullString `json:"bgm_prompt" db:"bgm_prompt"`
    SoundEffect      NullString `json:"sound_effect" db:"sound_effect"`
    Dialogue         NullString `json:"dialogue" db:"dialogue"`
    Description      NullString `json:"description" db:"description"`
    Duration         int        `json:"duration" db:"duration"`
    ComposedImage    NullString `json:"composed_image" db:"composed_image"`
    FirstFrameImage  NullString `json:"first_frame_image" db:"first_frame_image"`
    LastFrameImage   NullString `json:"last_frame_image" db:"last_frame_image"`
    ReferenceImages  NullString `json:"reference_images" db:"reference_images"`
    VideoURL         NullString `json:"video_url" db:"video_url"`
    TTSAudioURL      NullString `json:"tts_audio_url" db:"tts_audio_url"`
    SubtitleURL      NullString `json:"subtitle_url" db:"subtitle_url"`
    ComposedVideoURL NullString `json:"composed_video_url" db:"composed_video_url"`
    Status           NullString `json:"status" db:"status"`
    CreatedAt        string     `json:"created_at" db:"created_at"`
    UpdatedAt        string     `json:"updated_at" db:"updated_at"`
    DeletedAt        NullString `json:"deleted_at" db:"deleted_at"`
    // 运行时关联
    CharacterIDs []int64      `json:"character_ids,omitempty" db:"-"`
    Characters   []Character  `json:"characters,omitempty" db:"-"`
}

// EpisodeCharacter 集-角色关联
type EpisodeCharacter struct {
    ID          int64  `json:"id" db:"id"`
    EpisodeID   int64  `json:"episode_id" db:"episode_id"`
    CharacterID int64  `json:"character_id" db:"character_id"`
    CreatedAt   string `json:"created_at" db:"created_at"`
}

// EpisodeScene 集-场景关联
type EpisodeScene struct {
    ID        int64  `json:"id" db:"id"`
    EpisodeID int64  `json:"episode_id" db:"episode_id"`
    SceneID   int64  `json:"scene_id" db:"scene_id"`
    CreatedAt string `json:"created_at" db:"created_at"`
}

// AIServiceConfig AI 服务配置
type AIServiceConfig struct {
    ID            int64      `json:"id" db:"id"`
    ServiceType   string     `json:"service_type" db:"service_type"`
    Provider      NullString `json:"provider" db:"provider"`
    Name          string     `json:"name" db:"name"`
    BaseURL       string     `json:"base_url" db:"base_url"`
    APIKey        string     `json:"api_key" db:"api_key"`
    Model         NullString `json:"model" db:"model"`
    Endpoint      NullString `json:"endpoint" db:"endpoint"`
    QueryEndpoint NullString `json:"query_endpoint" db:"query_endpoint"`
    Priority      int        `json:"priority" db:"priority"`
    IsDefault     bool       `json:"is_default" db:"is_default"`
    IsActive      bool       `json:"is_active" db:"is_active"`
    Settings      NullString `json:"settings" db:"settings"`
    CreatedAt     string     `json:"created_at" db:"created_at"`
    UpdatedAt     string     `json:"updated_at" db:"updated_at"`
}

// AIServiceProvider AI 服务商预设
type AIServiceProvider struct {
    ID           int64      `json:"id" db:"id"`
    Name         string     `json:"name" db:"name"`
    DisplayName  NullString `json:"display_name" db:"display_name"`
    ServiceType  string     `json:"service_type" db:"service_type"`
    Provider     string     `json:"provider" db:"provider"`
    DefaultURL   NullString `json:"default_url" db:"default_url"`
    PresetModels NullString `json:"preset_models" db:"preset_models"`
    Description  NullString `json:"description" db:"description"`
    IsActive     bool       `json:"is_active" db:"is_active"`
    CreatedAt    string     `json:"created_at" db:"created_at"`
    UpdatedAt    string     `json:"updated_at" db:"updated_at"`
}

// AIVoice TTS 音色
type AIVoice struct {
    ID          int64      `json:"id" db:"id"`
    VoiceID     string     `json:"voice_id" db:"voice_id"`
    VoiceName   string     `json:"voice_name" db:"voice_name"`
    Description NullString `json:"description" db:"description"`
    Language    NullString `json:"language" db:"language"`
    Provider    string     `json:"provider" db:"provider"`
    CreatedAt   string     `json:"created_at" db:"created_at"`
}

// AgentConfig Agent 配置
type AgentConfig struct {
    ID            int64       `json:"id" db:"id"`
    AgentType     string      `json:"agent_type" db:"agent_type"`
    Name          string      `json:"name" db:"name"`
    Description   NullString  `json:"description" db:"description"`
    Model         NullString  `json:"model" db:"model"`
    SystemPrompt  NullString  `json:"system_prompt" db:"system_prompt"`
    Temperature   NullFloat64 `json:"temperature" db:"temperature"`
    MaxTokens     NullInt64   `json:"max_tokens" db:"max_tokens"`
    MaxIterations NullInt64   `json:"max_iterations" db:"max_iterations"`
    IsActive      bool        `json:"is_active" db:"is_active"`
    CreatedAt     string      `json:"created_at" db:"created_at"`
    UpdatedAt     string      `json:"updated_at" db:"updated_at"`
    DeletedAt     NullString  `json:"deleted_at" db:"deleted_at"`
}

// ImageGeneration 图片生成记录
type ImageGeneration struct {
    ID              int64      `json:"id" db:"id"`
    StoryboardID    NullInt64  `json:"storyboard_id" db:"storyboard_id"`
    DramaID         NullInt64  `json:"drama_id" db:"drama_id"`
    SceneID         NullInt64  `json:"scene_id" db:"scene_id"`
    CharacterID     NullInt64  `json:"character_id" db:"character_id"`
    PropID          NullInt64  `json:"prop_id" db:"prop_id"`
    ImageType       NullString `json:"image_type" db:"image_type"`
    FrameType       NullString `json:"frame_type" db:"frame_type"`
    Provider        NullString `json:"provider" db:"provider"`
    Prompt          NullString `json:"prompt" db:"prompt"`
    NegativePrompt  NullString `json:"negative_prompt" db:"negative_prompt"`
    Model           NullString `json:"model" db:"model"`
    Size            NullString `json:"size" db:"size"`
    Quality         NullString `json:"quality" db:"quality"`
    Style           NullString `json:"style" db:"style"`
    Steps           NullInt64  `json:"steps" db:"steps"`
    CFGScale        NullFloat64 `json:"cfg_scale" db:"cfg_scale"`
    Seed            NullInt64  `json:"seed" db:"seed"`
    ImageURL        NullString `json:"image_url" db:"image_url"`
    MinioURL        NullString `json:"minio_url" db:"minio_url"`
    LocalPath       NullString `json:"local_path" db:"local_path"`
    Status          string     `json:"status" db:"status"`
    TaskID          NullString `json:"task_id" db:"task_id"`
    ErrorMsg        NullString `json:"error_msg" db:"error_msg"`
    Width           NullInt64  `json:"width" db:"width"`
    Height          NullInt64  `json:"height" db:"height"`
    ReferenceImages NullString `json:"reference_images" db:"reference_images"`
    CreatedAt       string     `json:"created_at" db:"created_at"`
    UpdatedAt       string     `json:"updated_at" db:"updated_at"`
    CompletedAt     NullString `json:"completed_at" db:"completed_at"`
}

// VideoGeneration 视频生成记录
type VideoGeneration struct {
    ID                 int64      `json:"id" db:"id"`
    StoryboardID       NullInt64  `json:"storyboard_id" db:"storyboard_id"`
    DramaID            NullInt64  `json:"drama_id" db:"drama_id"`
    Provider           NullString `json:"provider" db:"provider"`
    Prompt             NullString `json:"prompt" db:"prompt"`
    Model              NullString `json:"model" db:"model"`
    ImageGenID         NullInt64  `json:"image_gen_id" db:"image_gen_id"`
    ReferenceMode      NullString `json:"reference_mode" db:"reference_mode"`
    ImageURL           NullString `json:"image_url" db:"image_url"`
    FirstFrameURL      NullString `json:"first_frame_url" db:"first_frame_url"`
    LastFrameURL       NullString `json:"last_frame_url" db:"last_frame_url"`
    ReferenceImageURLs NullString `json:"reference_image_urls" db:"reference_image_urls"`
    Duration           NullInt64  `json:"duration" db:"duration"`
    FPS                NullInt64  `json:"fps" db:"fps"`
    Resolution         NullString `json:"resolution" db:"resolution"`
    AspectRatio        NullString `json:"aspect_ratio" db:"aspect_ratio"`
    Style              NullString `json:"style" db:"style"`
    MotionLevel        NullInt64  `json:"motion_level" db:"motion_level"`
    CameraMotion       NullString `json:"camera_motion" db:"camera_motion"`
    Seed               NullInt64  `json:"seed" db:"seed"`
    VideoURL           NullString `json:"video_url" db:"video_url"`
    MinioURL           NullString `json:"minio_url" db:"minio_url"`
    LocalPath          NullString `json:"local_path" db:"local_path"`
    Status             string     `json:"status" db:"status"`
    TaskID             NullString `json:"task_id" db:"task_id"`
    ErrorMsg           NullString `json:"error_msg" db:"error_msg"`
    Width              NullInt64  `json:"width" db:"width"`
    Height             NullInt64  `json:"height" db:"height"`
    CreatedAt          string     `json:"created_at" db:"created_at"`
    UpdatedAt          string     `json:"updated_at" db:"updated_at"`
    CompletedAt        NullString `json:"completed_at" db:"completed_at"`
    DeletedAt          NullString `json:"deleted_at" db:"deleted_at"`
}

// VideoMerge 视频合并记录
type VideoMerge struct {
    ID          int64      `json:"id" db:"id"`
    EpisodeID   NullInt64  `json:"episode_id" db:"episode_id"`
    DramaID     NullInt64  `json:"drama_id" db:"drama_id"`
    Title       NullString `json:"title" db:"title"`
    Provider    NullString `json:"provider" db:"provider"`
    Model       NullString `json:"model" db:"model"`
    Status      string     `json:"status" db:"status"`
    Scenes      NullString `json:"scenes" db:"scenes"`
    MergedURL   NullString `json:"merged_url" db:"merged_url"`
    Duration    NullInt64  `json:"duration" db:"duration"`
    TaskID      NullString `json:"task_id" db:"task_id"`
    ErrorMsg    NullString `json:"error_msg" db:"error_msg"`
    CreatedAt   string     `json:"created_at" db:"created_at"`
    CompletedAt NullString `json:"completed_at" db:"completed_at"`
    DeletedAt   NullString `json:"deleted_at" db:"deleted_at"`
}

// Prop 道具
type Prop struct {
    ID              int64      `json:"id" db:"id"`
    DramaID         int64      `json:"drama_id" db:"drama_id"`
    Name            string     `json:"name" db:"name"`
    Type            NullString `json:"type" db:"type"`
    Description     NullString `json:"description" db:"description"`
    Prompt          NullString `json:"prompt" db:"prompt"`
    ImageURL        NullString `json:"image_url" db:"image_url"`
    ReferenceImages NullString `json:"reference_images" db:"reference_images"`
    LocalPath       NullString `json:"local_path" db:"local_path"`
    CreatedAt       string     `json:"created_at" db:"created_at"`
    UpdatedAt       string     `json:"updated_at" db:"updated_at"`
    DeletedAt       NullString `json:"deleted_at" db:"deleted_at"`
}

// Asset 资产
type Asset struct {
    ID            int64      `json:"id" db:"id"`
    DramaID       NullInt64  `json:"drama_id" db:"drama_id"`
    EpisodeID     NullInt64  `json:"episode_id" db:"episode_id"`
    StoryboardID  NullInt64  `json:"storyboard_id" db:"storyboard_id"`
    StoryboardNum NullInt64  `json:"storyboard_num" db:"storyboard_num"`
    Name          NullString `json:"name" db:"name"`
    Description   NullString `json:"description" db:"description"`
    Type          NullString `json:"type" db:"type"`
    Category      NullString `json:"category" db:"category"`
    URL           NullString `json:"url" db:"url"`
    ThumbnailURL  NullString `json:"thumbnail_url" db:"thumbnail_url"`
    LocalPath     NullString `json:"local_path" db:"local_path"`
    FileSize      NullInt64  `json:"file_size" db:"file_size"`
    MimeType      NullString `json:"mime_type" db:"mime_type"`
    Width         NullInt64  `json:"width" db:"width"`
    Height        NullInt64  `json:"height" db:"height"`
    Duration      NullInt64  `json:"duration" db:"duration"`
    Format        NullString `json:"format" db:"format"`
    ImageGenID    NullInt64  `json:"image_gen_id" db:"image_gen_id"`
    VideoGenID    NullInt64  `json:"video_gen_id" db:"video_gen_id"`
    IsFavorite    bool       `json:"is_favorite" db:"is_favorite"`
    ViewCount     int        `json:"view_count" db:"view_count"`
    CreatedAt     string     `json:"created_at" db:"created_at"`
    UpdatedAt     string     `json:"updated_at" db:"updated_at"`
    DeletedAt     NullString `json:"deleted_at" db:"deleted_at"`
}

// Now 返回 ISO 8601 时间戳字符串（与 TS 版 now() 一致）
func Now() string {
    return time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
}
```

---

## 5. 查询辅助函数

### 5.1 internal/database/queries.go

```go
package database

import (
    "database/sql"
    "fmt"
    "strings"

    sq "github.com/Masterminds/squirrel"
)

// sq 使用 SQLite placeholder 风格
var psql = sq.StatementBuilder.PlaceholderFormat(sq.Question)

// GetDramaByID 获取单个剧集
func GetDramaByID(db *sql.DB, id int64) (*Drama, error) {
    q := psql.Select("*").From("dramas").Where(sq.Eq{"id": id, "deleted_at": nil})
    rows, err := q.RunWith(db).Query()
    if err != nil {
        return nil, err
    }
    defer rows.Close()
    if rows.Next() {
        var d Drama
        if err := scanDrama(rows, &d); err != nil {
            return nil, err
        }
        return &d, nil
    }
    return nil, nil
}

// ListDramas 列出剧集（分页 + 过滤）
func ListDramas(db *sql.DB, opts ListDramasOpts) ([]Drama, error) {
    q := psql.Select("*").From("dramas").
        Where(sq.Eq{"deleted_at": nil}).
        OrderBy("created_at DESC")

    if opts.Status != "" {
        q = q.Where(sq.Eq{"status": opts.Status})
    }
    if opts.Keyword != "" {
        q = q.Where(sq.Or{
            sq.Like{"title": "%" + opts.Keyword + "%"},
            sq.Like{"description": "%" + opts.Keyword + "%"},
        })
    }
    if opts.PageSize > 0 {
        q = q.Limit(uint64(opts.PageSize)).Offset(uint64((opts.Page - 1) * opts.PageSize))
    }

    rows, err := q.RunWith(db).Query()
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var dramas []Drama
    for rows.Next() {
        var d Drama
        if err := scanDrama(rows, &d); err != nil {
            return nil, err
        }
        dramas = append(dramas, d)
    }
    return dramas, nil
}

// scanDrama 将 sql.Rows 的列扫描到 Drama struct
func scanDrama(rows *sql.Rows, d *Drama) error {
    return rows.Scan(
        &d.ID, &d.Title, &d.Description, &d.Genre, &d.Style,
        &d.TotalEpisodes, &d.TotalDuration, &d.Status, &d.Thumbnail,
        &d.Tags, &d.Metadata, &d.CreatedAt, &d.UpdatedAt, &d.DeletedAt,
    )
}

// 类似的 scan 函数为每个模型定义一次
func scanEpisode(rows *sql.Rows, e *Episode) error {
    return rows.Scan(
        &e.ID, &e.DramaID, &e.EpisodeNumber, &e.Title, &e.Content,
        &e.ScriptContent, &e.Description, &e.Duration, &e.Status,
        &e.VideoURL, &e.Thumbnail, &e.ImageConfigID, &e.VideoConfigID,
        &e.AudioConfigID, &e.CreatedAt, &e.UpdatedAt, &e.DeletedAt,
    )
}

func scanCharacter(rows *sql.Rows, c *Character) error {
    return rows.Scan(
        &c.ID, &c.DramaID, &c.Name, &c.Role, &c.Description,
        &c.Appearance, &c.Personality, &c.VoiceStyle, &c.ImageURL,
        &c.ReferenceImages, &c.SeedValue, &c.SortOrder, &c.LocalPath,
        &c.VoiceSampleURL, &c.VoiceProvider, &c.CreatedAt, &c.UpdatedAt,
        &c.DeletedAt,
    )
}

func scanScene(rows *sql.Rows, s *Scene) error {
    return rows.Scan(
        &s.ID, &s.DramaID, &s.EpisodeID, &s.Location, &s.Time,
        &s.Prompt, &s.StoryboardCount, &s.ImageURL, &s.Status,
        &s.LocalPath, &s.CreatedAt, &s.UpdatedAt, &s.DeletedAt,
    )
}

func scanStoryboard(rows *sql.Rows, sb *Storyboard) error {
    return rows.Scan(
        &sb.ID, &sb.EpisodeID, &sb.SceneID, &sb.StoryboardNumber,
        &sb.Title, &sb.Location, &sb.Time, &sb.ShotType, &sb.Angle,
        &sb.Movement, &sb.Action, &sb.Result, &sb.Atmosphere,
        &sb.ImagePrompt, &sb.VideoPrompt, &sb.BGMPrompt, &sb.SoundEffect,
        &sb.Dialogue, &sb.Description, &sb.Duration, &sb.ComposedImage,
        &sb.FirstFrameImage, &sb.LastFrameImage, &sb.ReferenceImages,
        &sb.VideoURL, &sb.TTSAudioURL, &sb.SubtitleURL,
        &sb.ComposedVideoURL, &sb.Status, &sb.CreatedAt, &sb.UpdatedAt,
        &sb.DeletedAt,
    )
}

// ========== 通用查询选项 ==========

type ListDramasOpts struct {
    Page     int
    PageSize int
    Status   string
    Keyword  string
}

// ========== 关联数据查询 ==========

// GetEpisodesByDramaID 获取剧集下所有分集
func GetEpisodesByDramaID(db *sql.DB, dramaID int64) ([]Episode, error) {
    rows, err := psql.Select("*").From("episodes").
        Where(sq.Eq{"drama_id": dramaID, "deleted_at": nil}).
        OrderBy("episode_number ASC").
        RunWith(db).Query()
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var eps []Episode
    for rows.Next() {
        var e Episode
        if err := scanEpisode(rows, &e); err != nil {
            return nil, err
        }
        eps = append(eps, e)
    }
    return eps, nil
}

// GetCharactersByDramaID 获取剧集下所有角色（未软删）
func GetCharactersByDramaID(db *sql.DB, dramaID int64) ([]Character, error) {
    rows, err := psql.Select("*").From("characters").
        Where(sq.Eq{"drama_id": dramaID, "deleted_at": nil}).
        OrderBy("sort_order ASC, id ASC").
        RunWith(db).Query()
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var chars []Character
    for rows.Next() {
        var c Character
        if err := scanCharacter(rows, &c); err != nil {
            return nil, err
        }
        chars = append(chars, c)
    }
    return chars, nil
}

// GetScenesByDramaID 获取剧集下所有场景
func GetScenesByDramaID(db *sql.DB, dramaID int64) ([]Scene, error) {
    rows, err := psql.Select("*").From("scenes").
        Where(sq.Eq{"drama_id": dramaID, "deleted_at": nil}).
        OrderBy("id ASC").
        RunWith(db).Query()
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var scenes []Scene
    for rows.Next() {
        var s Scene
        if err := scanScene(rows, &s); err != nil {
            return nil, err
        }
        scenes = append(scenes, s)
    }
    return scenes, nil
}

// GetStoryboardsByEpisodeID 获取分集下所有分镜（按 storyboard_number 排序）
func GetStoryboardsByEpisodeID(db *sql.DB, episodeID int64) ([]Storyboard, error) {
    rows, err := psql.Select("*").From("storyboards").
        Where(sq.Eq{"episode_id": episodeID, "deleted_at": nil}).
        OrderBy("storyboard_number ASC").
        RunWith(db).Query()
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var sbs []Storyboard
    for rows.Next() {
        var sb Storyboard
        if err := scanStoryboard(rows, &sb); err != nil {
            return nil, err
        }
        sbs = append(sbs, sb)
    }
    return sbs, nil
}

// GetStoryboardCharacterIDs 获取分镜关联的角色 ID 列表
func GetStoryboardCharacterIDs(db *sql.DB, storyboardID int64) ([]int64, error) {
    rows, err := psql.Select("character_id").From("storyboard_characters").
        Where(sq.Eq{"storyboard_id": storyboardID}).
        RunWith(db).Query()
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    var ids []int64
    for rows.Next() {
        var id int64
        if err := rows.Scan(&id); err != nil {
            return nil, err
        }
        ids = append(ids, id)
    }
    return ids, nil
}

// GetEpisodeCharacterIDs 获取集关联的角色 ID 集合
func GetEpisodeCharacterIDs(db *sql.DB, episodeID int64) (map[int64]bool, error) {
    rows, err := psql.Select("character_id").From("episode_characters").
        Where(sq.Eq{"episode_id": episodeID}).
        RunWith(db).Query()
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    m := make(map[int64]bool)
    for rows.Next() {
        var id int64
        if err := rows.Scan(&id); err != nil {
            return nil, err
        }
        m[id] = true
    }
    return m, nil
}

// GetEpisodeSceneIDs 获取集关联的场景 ID 集合
func GetEpisodeSceneIDs(db *sql.DB, episodeID int64) (map[int64]bool, error) {
    rows, err := psql.Select("scene_id").From("episode_scenes").
        Where(sq.Eq{"episode_id": episodeID}).
        RunWith(db).Query()
    if err != nil {
        return nil, err
    }
    defer rows.Close()

    m := make(map[int64]bool)
    for rows.Next() {
        var id int64
        if err := rows.Scan(&id); err != nil {
            return nil, err
        }
        m[id] = true
    }
    return m, nil
}
```

---

## 6. Handler 层

### 6.1 internal/handler/handler.go

```go
package handler

import "database/sql"

// Handler 聚合所有 HTTP handler，持有共享依赖
type Handler struct {
    DB *sql.DB
}

// New 创建 Handler 实例
func New(db *sql.DB) *Handler {
    return &Handler{DB: db}
}
```

### 6.2 internal/handler/drama.go

对应 TS 版 `backend/src/routes/dramas.ts` 的全部端点。

```go
package handler

import (
    "database/sql"
    "encoding/json"
    "fmt"
    "net/http"
    "strconv"

    "github.com/gin-gonic/gin"
    sq "github.com/Masterminds/squirrel"
    "github.com/huobao-drama/backend-go/internal/database"
    "github.com/huobao-drama/backend-go/internal/util"
)

// GET /api/v1/dramas
func (h *Handler) ListDramas(c *gin.Context) {
    page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
    pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
    status := c.Query("status")
    keyword := c.Query("keyword")

    if page < 1 { page = 1 }
    if pageSize < 1 || pageSize > 100 { pageSize = 20 }

    dramas, err := database.ListDramas(h.DB, database.ListDramasOpts{
        Page: page, PageSize: pageSize, Status: status, Keyword: keyword,
    })
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }

    // 填充关联数据
    for i := range dramas {
        h.enrichDrama(&dramas[i])
    }

    util.Success(c, gin.H{"items": dramas})
}

// POST /api/v1/dramas
func (h *Handler) CreateDrama(c *gin.Context) {
    var body struct {
        Title         string `json:"title" binding:"required"`
        Description   string `json:"description"`
        Genre         string `json:"genre"`
        Style         string `json:"style"`
        Tags          string `json:"tags"`
        Metadata      string `json:"metadata"`
        TotalEpisodes int    `json:"total_episodes"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "title is required")
        return
    }

    now := database.Now()
    style := body.Style
    if style == "" { style = "realistic" }
    totalEp := body.TotalEpisodes
    if totalEp <= 0 { totalEp = 1 }

    // 插入 drama
    res, err := h.DB.Exec(
        `INSERT INTO dramas (title, description, genre, style, total_episodes, status, tags, metadata, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, 'draft', ?, ?, ?, ?)`,
        body.Title, util.NullIfEmpty(body.Description), util.NullIfEmpty(body.Genre),
        style, totalEp, util.NullIfEmpty(body.Tags), util.NullIfEmpty(body.Metadata),
        now, now,
    )
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }
    dramaID, _ := res.LastInsertId()

    // 创建默认集数
    for i := 1; i <= totalEp; i++ {
        _, err := h.DB.Exec(
            `INSERT INTO episodes (drama_id, episode_number, title, status, created_at, updated_at)
             VALUES (?, ?, ?, 'draft', ?, ?)`,
            dramaID, i, fmt.Sprintf("第%d集", i), now, now,
        )
        if err != nil {
            // 记录错误但不中断
            continue
        }
    }

    // 返回完整 drama（含 episodes）
    drama, _ := database.GetDramaByID(h.DB, dramaID)
    if drama != nil {
        h.enrichDrama(drama)
    }
    util.Created(c, drama)
}

// GET /api/v1/dramas/stats
func (h *Handler) DramaStats(c *gin.Context) {
    var total int
    h.DB.QueryRow("SELECT COUNT(*) FROM dramas WHERE deleted_at IS NULL").Scan(&total)

    rows, _ := h.DB.Query(
        "SELECT status, COUNT(*) FROM dramas WHERE deleted_at IS NULL GROUP BY status",
    )
    defer rows.Close()

    byStatus := map[string]int{}
    for rows.Next() {
        var status string
        var count int
        rows.Scan(&status, &count)
        byStatus[status] = count
    }

    util.Success(c, gin.H{"total": total, "by_status": byStatus})
}

// GET /api/v1/dramas/:id
func (h *Handler) GetDrama(c *gin.Context) {
    id, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        util.BadRequest(c, "invalid id")
        return
    }

    drama, err := database.GetDramaByID(h.DB, id)
    if err != nil || drama == nil {
        util.NotFound(c, "drama not found")
        return
    }
    h.enrichDrama(drama)
    util.Success(c, drama)
}

// PUT /api/v1/dramas/:id
func (h *Handler) UpdateDrama(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    var body map[string]interface{}
    c.ShouldBindJSON(&body)

    allowedFields := map[string]bool{
        "title": true, "description": true, "genre": true,
        "style": true, "status": true, "tags": true, "metadata": true,
    }

    q := sq.Update("dramas")
    for k, v := range body {
        if !allowedFields[k] { continue }
        q = q.Set(k, v)
    }
    q = q.Set("updated_at", database.Now()).Where(sq.Eq{"id": id})

    _, err := q.RunWith(h.DB).Exec()
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }

    drama, _ := database.GetDramaByID(h.DB, id)
    h.enrichDrama(drama)
    util.Success(c, drama)
}

// DELETE /api/v1/dramas/:id
func (h *Handler) DeleteDrama(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    h.DB.Exec(
        "UPDATE dramas SET deleted_at = ?, updated_at = ? WHERE id = ?",
        database.Now(), database.Now(), id,
    )
    util.Success(c, nil)
}

// PUT /api/v1/dramas/:id/characters — 批量 upsert 角色
func (h *Handler) UpsertDramaCharacters(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    var body struct {
        Characters []struct {
            ID          *int64 `json:"id"`
            Name        string `json:"name"`
            Role        string `json:"role"`
            Description string `json:"description"`
            Appearance  string `json:"appearance"`
            Personality string `json:"personality"`
            SortOrder   *int   `json:"sort_order"`
        } `json:"characters"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "invalid body")
        return
    }

    now := database.Now()
    for _, ch := range body.Characters {
        if ch.ID != nil && *ch.ID > 0 {
            // 更新
            h.DB.Exec(
                `UPDATE characters SET name=?, role=?, description=?, appearance=?,
                 personality=?, sort_order=?, updated_at=? WHERE id=? AND drama_id=?`,
                ch.Name, util.NullIfEmpty(ch.Role), util.NullIfEmpty(ch.Description),
                util.NullIfEmpty(ch.Appearance), util.NullIfEmpty(ch.Personality),
                ch.SortOrder, now, *ch.ID, id,
            )
        } else {
            // 新增
            h.DB.Exec(
                `INSERT INTO characters (drama_id, name, role, description, appearance, personality, sort_order, created_at, updated_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                id, ch.Name, util.NullIfEmpty(ch.Role), util.NullIfEmpty(ch.Description),
                util.NullIfEmpty(ch.Appearance), util.NullIfEmpty(ch.Personality),
                ch.SortOrder, now, now,
            )
        }
    }

    chars, _ := database.GetCharactersByDramaID(h.DB, id)
    util.Success(c, chars)
}

// PUT /api/v1/dramas/:id/episodes — 批量 upsert 集数
func (h *Handler) UpsertDramaEpisodes(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    var body struct {
        Episodes []struct {
            ID            *int64 `json:"id"`
            EpisodeNumber int    `json:"episode_number"`
            Title         string `json:"title"`
            Description   string `json:"description"`
        } `json:"episodes"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "invalid body")
        return
    }

    now := database.Now()
    for _, ep := range body.Episodes {
        if ep.ID != nil && *ep.ID > 0 {
            h.DB.Exec(
                `UPDATE episodes SET title=?, description=?, updated_at=? WHERE id=? AND drama_id=?`,
                ep.Title, util.NullIfEmpty(ep.Description), now, *ep.ID, id,
            )
        } else {
            h.DB.Exec(
                `INSERT INTO episodes (drama_id, episode_number, title, description, status, created_at, updated_at)
                 VALUES (?, ?, ?, ?, 'draft', ?, ?)`,
                id, ep.EpisodeNumber, ep.Title, util.NullIfEmpty(ep.Description), now, now,
            )
        }
    }

    eps, _ := database.GetEpisodesByDramaID(h.DB, id)
    util.Success(c, eps)
}

// enrichDrama 填充 drama 的关联数据
func (h *Handler) enrichDrama(d *Drama) {
    d.Episodes, _ = database.GetEpisodesByDramaID(h.DB, d.ID)
    d.Characters, _ = database.GetCharactersByDramaID(h.DB, d.ID)
    d.Scenes, _ = database.GetScenesByDramaID(h.DB, d.ID)
    d.Props, _ = database.GetPropsByDramaID(h.DB, d.ID)
}
```

### 6.3 internal/handler/episode.go

对应 TS 版 `backend/src/routes/episodes.ts`。

```go
package handler

import (
    "fmt"
    "strconv"

    "github.com/gin-gonic/gin"
    "github.com/huobao-drama/backend-go/internal/database"
    "github.com/huobao-drama/backend-go/internal/util"
)

// POST /api/v1/episodes
func (h *Handler) CreateEpisode(c *gin.Context) {
    var body struct {
        DramaID       int64  `json:"drama_id" binding:"required"`
        Title         string `json:"title"`
        ImageConfigID *int64 `json:"image_config_id"`
        VideoConfigID *int64 `json:"video_config_id"`
        AudioConfigID *int64 `json:"audio_config_id"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "drama_id is required")
        return
    }

    now := database.Now()

    // 自动计算 episode_number
    var maxNum int
    h.DB.QueryRow(
        "SELECT COALESCE(MAX(episode_number), 0) FROM episodes WHERE drama_id = ?",
        body.DramaID,
    ).Scan(&maxNum)
    nextNum := maxNum + 1

    title := body.Title
    if title == "" {
        title = fmt.Sprintf("第%d集", nextNum)
    }

    res, err := h.DB.Exec(
        `INSERT INTO episodes (drama_id, episode_number, title, status, image_config_id, video_config_id, audio_config_id, created_at, updated_at)
         VALUES (?, ?, ?, 'draft', ?, ?, ?, ?, ?)`,
        body.DramaID, nextNum, title,
        body.ImageConfigID, body.VideoConfigID, body.AudioConfigID,
        now, now,
    )
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }
    id, _ := res.LastInsertId()

    // 更新 drama 的 total_episodes
    h.DB.Exec("UPDATE dramas SET total_episodes = (SELECT COUNT(*) FROM episodes WHERE drama_id = ? AND deleted_at IS NULL) WHERE id = ?", body.DramaID, body.DramaID)

    util.Created(c, gin.H{"id": id, "episode_number": nextNum})
}

// PUT /api/v1/episodes/:id
func (h *Handler) UpdateEpisode(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    var body map[string]interface{}
    c.ShouldBindJSON(&body)

    allowedFields := map[string]bool{
        "content": true, "script_content": true, "title": true,
        "description": true, "status": true,
        "image_config_id": true, "video_config_id": true, "audio_config_id": true,
    }

    q := sq.Update("episodes")
    for k, v := range body {
        if !allowedFields[k] { continue }
        q = q.Set(k, v)
    }
    q = q.Set("updated_at", database.Now()).Where(sq.Eq{"id": id})

    if _, err := q.RunWith(h.DB).Exec(); err != nil {
        util.ServerError(c, err.Error())
        return
    }
    util.Success(c, nil)
}

// GET /api/v1/episodes/:id/characters
func (h *Handler) GetEpisodeCharacters(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    rows, err := h.DB.Query(
        `SELECT c.* FROM characters c
         JOIN episode_characters ec ON ec.character_id = c.id
         WHERE ec.episode_id = ? AND c.deleted_at IS NULL
         ORDER BY c.sort_order ASC, c.id ASC`, id,
    )
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }
    defer rows.Close()

    var chars []database.Character
    for rows.Next() {
        var ch database.Character
        database.ScanCharacter(rows, &ch)
        chars = append(chars, ch)
    }
    util.Success(c, chars)
}

// GET /api/v1/episodes/:id/scenes
func (h *Handler) GetEpisodeScenes(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    rows, err := h.DB.Query(
        `SELECT s.* FROM scenes s
         JOIN episode_scenes es ON es.scene_id = s.id
         WHERE es.episode_id = ? AND s.deleted_at IS NULL
         ORDER BY s.id ASC`, id,
    )
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }
    defer rows.Close()

    var scenes []database.Scene
    for rows.Next() {
        var s database.Scene
        database.ScanScene(rows, &s)
        scenes = append(scenes, s)
    }
    util.Success(c, scenes)
}

// GET /api/v1/episodes/:episode_id/storyboards
func (h *Handler) GetEpisodeStoryboards(c *gin.Context) {
    episodeID, _ := strconv.ParseInt(c.Param("episode_id"), 10, 64)

    sbs, err := database.GetStoryboardsByEpisodeID(h.DB, episodeID)
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }

    // 为每个分镜填充 character_ids 和 characters
    for i := range sbs {
        ids, _ := database.GetStoryboardCharacterIDs(h.DB, sbs[i].ID)
        sbs[i].CharacterIDs = ids

        if len(ids) > 0 {
            chars, _ := database.GetCharactersByIDs(h.DB, ids)
            sbs[i].Characters = chars
        }
    }

    util.Success(c, sbs)
}

// GET /api/v1/episodes/:id/pipeline-status
func (h *Handler) GetEpisodePipelineStatus(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    var ep database.Episode
    row := h.DB.QueryRow("SELECT * FROM episodes WHERE id = ?", id)
    database.ScanEpisodeRow(row, &ep)

    chars, _ := database.GetEpisodeCharacters(h.DB, id)
    scenes, _ := database.GetEpisodeScenes(h.DB, id)
    sbs, _ := database.GetStoryboardsByEpisodeID(h.DB, id)

    steps := []gin.H{
        {"step": "script_rewrite", "label": "剧本改写", "status": pipelineStatus(ep.ScriptContent.String != "")},
        {"step": "character_extract", "label": "角色提取", "status": pipelineStatus(len(chars) > 0), "count": len(chars)},
        {"step": "voice_assign", "label": "音色分配", "status": pipelineVoiceStatus(chars)},
        {"step": "scene_extract", "label": "场景提取", "status": pipelineStatus(len(scenes) > 0), "count": len(scenes)},
        {"step": "storyboard_extract", "label": "分镜拆解", "status": pipelineStatus(len(sbs) > 0), "count": len(sbs)},
        {"step": "image_gen", "label": "图片生成", "status": pipelineImageStatus(sbs)},
        {"step": "video_gen", "label": "视频生成", "status": pipelineVideoStatus(sbs)},
        {"step": "shot_compose", "label": "镜头合成", "status": pipelineComposeStatus(sbs)},
        {"step": "episode_merge", "label": "集数拼接", "status": pipelineStatus(ep.VideoURL.String != "")},
    }

    util.Success(c, steps)
}

// pipeline 辅助函数
func pipelineStatus(done bool) string {
    if done { return "done" }
    return "pending"
}

func pipelineVoiceStatus(chars []database.Character) string {
    if len(chars) == 0 { return "pending" }
    assigned := 0
    for _, c := range chars {
        if c.VoiceStyle.Valid && c.VoiceStyle.String != "" {
            assigned++
        }
    }
    if assigned == len(chars) { return "done" }
    if assigned > 0 { return "partial" }
    return "pending"
}

func pipelineImageStatus(sbs []database.Storyboard) string {
    if len(sbs) == 0 { return "pending" }
    done := 0
    for _, sb := range sbs {
        if sb.ComposedImage.Valid || sb.FirstFrameImage.Valid {
            done++
        }
    }
    if done == len(sbs) { return "done" }
    if done > 0 { return "partial" }
    return "pending"
}

func pipelineVideoStatus(sbs []database.Storyboard) string {
    if len(sbs) == 0 { return "pending" }
    done := 0
    for _, sb := range sbs {
        if sb.VideoURL.Valid { done++ }
    }
    if done == len(sbs) { return "done" }
    if done > 0 { return "partial" }
    return "pending"
}

func pipelineComposeStatus(sbs []database.Storyboard) string {
    if len(sbs) == 0 { return "pending" }
    done := 0
    for _, sb := range sbs {
        if sb.ComposedVideoURL.Valid { done++ }
    }
    if done == len(sbs) { return "done" }
    if done > 0 { return "partial" }
    return "pending"
}
```

### 6.4 internal/handler/scene.go

对应 TS 版 `backend/src/routes/scenes.ts`。

```go
package handler

import (
    "strconv"

    "github.com/gin-gonic/gin"
    "github.com/huobao-drama/backend-go/internal/database"
    "github.com/huobao-drama/backend-go/internal/util"
)

// POST /api/v1/scenes
func (h *Handler) CreateScene(c *gin.Context) {
    var body struct {
        DramaID   int64  `json:"drama_id" binding:"required"`
        EpisodeID *int64 `json:"episode_id"`
        Location  string `json:"location" binding:"required"`
        Time      string `json:"time" binding:"required"`
        Prompt    string `json:"prompt" binding:"required"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "drama_id, location, time, prompt are required")
        return
    }

    now := database.Now()
    res, err := h.DB.Exec(
        `INSERT INTO scenes (drama_id, episode_id, location, time, prompt, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, 'pending', ?, ?)`,
        body.DramaID, body.EpisodeID, body.Location, body.Time, body.Prompt, now, now,
    )
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }
    id, _ := res.LastInsertId()
    util.Created(c, gin.H{"id": id})
}

// PUT /api/v1/scenes/:id
func (h *Handler) UpdateScene(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    var body map[string]interface{}
    c.ShouldBindJSON(&body)

    allowedFields := map[string]bool{"location": true, "time": true, "prompt": true}
    q := sq.Update("scenes")
    for k, v := range body {
        if !allowedFields[k] { continue }
        q = q.Set(k, v)
    }
    q = q.Set("updated_at", database.Now()).Where(sq.Eq{"id": id})

    if _, err := q.RunWith(h.DB).Exec(); err != nil {
        util.ServerError(c, err.Error())
        return
    }
    util.Success(c, nil)
}

// DELETE /api/v1/scenes/:id
func (h *Handler) DeleteScene(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    h.DB.Exec("DELETE FROM scenes WHERE id = ?", id)
    util.Success(c, nil)
}

// POST /api/v1/scenes/:id/generate-image — Phase 3 实现
func (h *Handler) GenerateSceneImage(c *gin.Context) {
    // 占位：Phase 3 实现
    util.Success(c, gin.H{"message": "not implemented yet"})
}
```

### 6.5 internal/handler/character.go

对应 TS 版 `backend/src/routes/characters.ts`。

```go
package handler

import (
    "strconv"

    "github.com/gin-gonic/gin"
    "github.com/huobao-drama/backend-go/internal/database"
    "github.com/huobao-drama/backend-go/internal/util"
)

// PUT /api/v1/characters/:id
func (h *Handler) UpdateCharacter(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    var body map[string]interface{}
    c.ShouldBindJSON(&body)

    allowedFields := map[string]bool{
        "name": true, "role": true, "description": true,
        "appearance": true, "personality": true, "voice_style": true,
        "voice_provider": true, "image_url": true, "local_path": true,
    }

    q := sq.Update("characters")
    for k, v := range body {
        if !allowedFields[k] { continue }
        // camelCase → snake_case
        snakeKey := util.ToSnakeCase(k)
        q = q.Set(snakeKey, v)
    }
    q = q.Set("updated_at", database.Now()).Where(sq.Eq{"id": id})

    // 如果 voice_style 变更，清除 voice_sample_url
    if vs, ok := body["voice_style"]; ok && vs != nil {
        q = q.Set("voice_sample_url", nil)
    }

    if _, err := q.RunWith(h.DB).Exec(); err != nil {
        util.ServerError(c, err.Error())
        return
    }
    util.Success(c, nil)
}

// DELETE /api/v1/characters/:id — 软删除
func (h *Handler) DeleteCharacter(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    h.DB.Exec(
        "UPDATE characters SET deleted_at = ?, updated_at = ? WHERE id = ?",
        database.Now(), database.Now(), id,
    )
    util.Success(c, nil)
}

// POST /api/v1/characters/:id/generate-voice-sample — Phase 3 实现
func (h *Handler) GenerateCharacterVoiceSample(c *gin.Context) {
    util.Success(c, gin.H{"message": "not implemented yet"})
}

// POST /api/v1/characters/:id/generate-image — Phase 3 实现
func (h *Handler) GenerateCharacterImage(c *gin.Context) {
    util.Success(c, gin.H{"message": "not implemented yet"})
}

// POST /api/v1/characters/batch-generate-images — Phase 3 实现
func (h *Handler) BatchGenerateCharacterImages(c *gin.Context) {
    util.Success(c, gin.H{"message": "not implemented yet"})
}
```

### 6.6 internal/handler/storyboard.go

对应 TS 版 `backend/src/routes/storyboards.ts`。

```go
package handler

import (
    "strconv"

    "github.com/gin-gonic/gin"
    "github.com/huobao-drama/backend-go/internal/database"
    "github.com/huobao-drama/backend-go/internal/util"
)

// POST /api/v1/storyboards
func (h *Handler) CreateStoryboard(c *gin.Context) {
    var body struct {
        EpisodeID        int64   `json:"episode_id" binding:"required"`
        StoryboardNumber int     `json:"storyboard_number" binding:"required"`
        Title            string  `json:"title"`
        Description      string  `json:"description"`
        Action           string  `json:"action"`
        Dialogue         string  `json:"dialogue"`
        SceneID          *int64  `json:"scene_id"`
        CharacterIDs     []int64 `json:"character_ids"`
        Duration         int     `json:"duration"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "episode_id and storyboard_number are required")
        return
    }

    now := database.Now()
    duration := body.Duration
    if duration <= 0 { duration = 10 }

    res, err := h.DB.Exec(
        `INSERT INTO storyboards
         (episode_id, scene_id, storyboard_number, title, description, action, dialogue, duration, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`,
        body.EpisodeID, body.SceneID, body.StoryboardNumber,
        util.NullIfEmpty(body.Title), util.NullIfEmpty(body.Description),
        util.NullIfEmpty(body.Action), util.NullIfEmpty(body.Dialogue),
        duration, now, now,
    )
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }
    sbID, _ := res.LastInsertId()

    // 关联角色
    if len(body.CharacterIDs) > 0 {
        for _, charID := range body.CharacterIDs {
            h.DB.Exec(
                "INSERT OR IGNORE INTO storyboard_characters (storyboard_id, character_id) VALUES (?, ?)",
                sbID, charID,
            )
        }
    }

    util.Created(c, gin.H{"id": sbID})
}

// PUT /api/v1/storyboards/:id
func (h *Handler) UpdateStoryboard(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    var body map[string]interface{}
    c.ShouldBindJSON(&body)

    allowedFields := map[string]bool{
        "title": true, "description": true, "shot_type": true,
        "angle": true, "movement": true, "action": true,
        "dialogue": true, "duration": true, "video_prompt": true,
        "image_prompt": true, "scene_id": true, "location": true,
        "time": true, "result": true, "atmosphere": true,
        "bgm_prompt": true, "sound_effect": true,
    }

    q := sq.Update("storyboards")
    for k, v := range body {
        if !allowedFields[k] { continue }
        q = q.Set(k, v)
    }

    // 如果 dialogue 变更，清除 tts 和 subtitle
    if _, ok := body["dialogue"]; ok {
        q = q.Set("tts_audio_url", nil).Set("subtitle_url", nil)
    }

    q = q.Set("updated_at", database.Now()).Where(sq.Eq{"id": id})

    if _, err := q.RunWith(h.DB).Exec(); err != nil {
        util.ServerError(c, err.Error())
        return
    }

    // 处理 character_ids
    if charIDs, ok := body["character_ids"]; ok {
        // 先清除旧关联
        h.DB.Exec("DELETE FROM storyboard_characters WHERE storyboard_id = ?", id)
        // 插入新关联
        if ids, ok := charIDs.([]interface{}); ok {
            for _, cid := range ids {
                if v, ok := cid.(float64); ok {
                    h.DB.Exec(
                        "INSERT OR IGNORE INTO storyboard_characters (storyboard_id, character_id) VALUES (?, ?)",
                        id, int64(v),
                    )
                }
            }
        }
    }

    util.Success(c, nil)
}

// DELETE /api/v1/storyboards/:id
func (h *Handler) DeleteStoryboard(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    h.DB.Exec("DELETE FROM storyboard_characters WHERE storyboard_id = ?", id)
    h.DB.Exec("DELETE FROM storyboards WHERE id = ?", id)
    util.Success(c, nil)
}

// POST /api/v1/storyboards/:id/generate-tts — Phase 3 实现
func (h *Handler) GenerateStoryboardTTS(c *gin.Context) {
    util.Success(c, gin.H{"message": "not implemented yet"})
}
```

---

## 7. 中间件

### 7.1 internal/middleware/logger.go

对应 TS 版 `backend/src/middleware/logger.ts`。

```go
package middleware

import (
    "fmt"
    "io"
    "strings"
    "time"

    "github.com/gin-gonic/gin"
    "github.com/rs/zerolog/log"
)

// RequestLogger 请求日志中间件
func RequestLogger() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        path := c.Request.URL.Path

        // 记录请求体（POST/PUT/PATCH，截断 500 字符）
        var bodyStr string
        if c.Request.Method == "POST" || c.Request.Method == "PUT" || c.Request.Method == "PATCH" {
            bodyBytes, _ := io.ReadAll(c.Request.Body)
            if len(bodyBytes) > 0 {
                bodyStr = string(bodyBytes)
                if len(bodyStr) > 500 {
                    bodyStr = bodyStr[:500] + "..."
                }
                // 重新设置 body 供后续 handler 读取
                c.Request.Body = io.NopCloser(strings.NewReader(string(bodyBytes)))
            }
        }

        log.Info().
            Str("method", c.Request.Method).
            Str("path", path).
            Str("body", bodyStr).
            Msg("→ Request")

        c.Next()

        elapsed := time.Since(start)
        status := c.Writer.Status()

        event := log.Info()
        if status >= 500 {
            event = log.Error()
        } else if status >= 400 {
            event = log.Warn()
        }

        event.
            Str("method", c.Request.Method).
            Str("path", path).
            Int("status", status).
            Dur("elapsed", elapsed).
            Str("client_ip", c.ClientIP()).
            Msg(fmt.Sprintf("← %d %s %s (%s)", status, c.Request.Method, path, elapsed))
    }
}

// ErrorHandler 全局错误恢复中间件
func ErrorHandler() gin.HandlerFunc {
    return func(c *gin.Context) {
        defer func() {
            if r := recover(); r != nil {
                log.Error().
                    Str("path", c.Request.URL.Path).
                    Interface("panic", r).
                    Msg("Recovered from panic")

                c.AbortWithStatusJSON(500, gin.H{
                    "code":    500,
                    "data":    nil,
                    "message": fmt.Sprintf("Internal server error: %v", r),
                })
            }
        }()
        c.Next()
    }
}
```

### 7.2 internal/middleware/cors.go

```go
package middleware

import (
    "time"

    "github.com/gin-contrib/cors"
    "github.com/gin-gonic/gin"
)

func CORS() gin.HandlerFunc {
    return cors.New(cors.Config{
        AllowOrigins:     []string{"http://localhost:3013", "http://localhost:5679"},
        AllowMethods:     []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
        AllowHeaders:     []string{"Origin", "Content-Type", "Authorization"},
        AllowCredentials: true,
        MaxAge:           12 * time.Hour,
    })
}
```

---

## 8. 工具函数

### 8.1 internal/util/response.go

对应 TS 版 `backend/src/utils/response.ts`。

```go
package util

import (
    "net/http"

    "github.com/gin-gonic/gin"
)

func Success(c *gin.Context, data interface{}) {
    c.JSON(http.StatusOK, gin.H{
        "code":    200,
        "data":    data,
        "message": "success",
    })
}

func Created(c *gin.Context, data interface{}) {
    c.JSON(http.StatusCreated, gin.H{
        "code":    201,
        "data":    data,
        "message": "created",
    })
}

func BadRequest(c *gin.Context, msg string) {
    c.JSON(http.StatusBadRequest, gin.H{
        "code":    400,
        "data":    nil,
        "message": msg,
    })
}

func NotFound(c *gin.Context, msg string) {
    c.JSON(http.StatusNotFound, gin.H{
        "code":    404,
        "data":    nil,
        "message": msg,
    })
}

func ServerError(c *gin.Context, msg string) {
    c.JSON(http.StatusInternalServerError, gin.H{
        "code":    500,
        "data":    nil,
        "message": msg,
    })
}

// NullIfEmpty 空字符串返回 nil（用于数据库 NULL 值）
func NullIfEmpty(s string) interface{} {
    if s == "" {
        return nil
    }
    return s
}
```

### 8.2 internal/util/transform.go

对应 TS 版 `backend/src/utils/transform.ts`。

```go
package util

import (
    "regexp"
    "strings"
)

var matchFirstCap = regexp.MustCompile("(.)([A-Z][a-z])")
var matchAllCap = regexp.MustCompile("([a-z0-9])([A-Z])")

// ToSnakeCase 将 camelCase 转换为 snake_case
func ToSnakeCase(str string) string {
    snake := matchFirstCap.ReplaceAllString(str, "${1}_${2}")
    snake = matchAllCap.ReplaceAllString(snake, "${1}_${2}")
    return strings.ToLower(snake)
}

// ToSnakeCaseMap 将 map 的 key 从 camelCase 转换为 snake_case
func ToSnakeCaseMap(m map[string]interface{}) map[string]interface{} {
    result := make(map[string]interface{})
    for k, v := range m {
        result[ToSnakeCase(k)] = v
    }
    return result
}
```

### 8.3 internal/util/task_logger.go

对应 TS 版 `backend/src/utils/task-logger.ts`。

```go
package util

import (
    "encoding/json"
    "fmt"
    "regexp"
    "strings"

    "github.com/rs/zerolog/log"
)

var sensitiveKeys = []string{"api_key", "apiKey", "authorization", "token", "access_token", "secret"}

// RedactURL 脱敏 URL 中的敏感参数
func RedactURL(rawURL string) string {
    for _, key := range sensitiveKeys {
        re := regexp.MustCompile(key + `=[^&]*`)
        rawURL = re.ReplaceAllString(rawURL, key+"=***")
    }
    return rawURL
}

// LogTask 记录结构化任务日志
func LogTask(scope, action string, meta map[string]interface{}) {
    event := log.Info().Str("scope", scope).Str("action", action)
    for k, v := range meta {
        k = strings.ToLower(k)
        v = sanitizeValue(k, v)
        event = event.Interface(k, v)
    }
    event.Msg("")
}

func sanitizeValue(key string, v interface{}) interface{} {
    keyLower := strings.ToLower(key)
    for _, sk := range sensitiveKeys {
        if keyLower == sk || strings.Contains(keyLower, sk) {
            return "***"
        }
    }

    switch val := v.(type) {
    case string:
        // 截断 base64
        if strings.HasPrefix(val, "data:") && len(val) > 100 {
            return val[:100] + "...(truncated)"
        }
        // 截断超长 hex（音频数据）
        if len(val) > 200 {
            return val[:200] + "...(truncated)"
        }
    case map[string]interface{}:
        for k2, v2 := range val {
            val[k2] = sanitizeValue(k2, v2)
        }
    }
    return v
}

// LogTaskStart 记录任务开始
func LogTaskStart(scope, action string, meta map[string]interface{}) {
    meta["_event"] = "START"
    LogTask(scope, action, meta)
}

// LogTaskSuccess 记录任务成功
func LogTaskSuccess(scope, action string, meta map[string]interface{}) {
    meta["_event"] = "SUCCESS"
    LogTask(scope, action, meta)
}

// LogTaskError 记录任务错误
func LogTaskError(scope, action string, meta map[string]interface{}) {
    meta["_event"] = "ERROR"
    event := log.Error().Str("scope", scope).Str("action", action)
    for k, v := range meta {
        event = event.Interface(k, sanitizeValue(k, v))
    }
    event.Msg("")
}

// LogTaskProgress 记录任务进度
func LogTaskProgress(scope, action string, meta map[string]interface{}) {
    meta["_event"] = "PROGRESS"
    LogTask(scope, action, meta)
}

// LogTaskWarn 记录任务警告
func LogTaskWarn(scope, action string, meta map[string]interface{}) {
    meta["_event"] = "WARN"
    event := log.Warn().Str("scope", scope).Str("action", action)
    for k, v := range meta {
        event = event.Interface(k, sanitizeValue(k, v))
    }
    event.Msg("")
}

// LogTaskPayload 记录任务详细载荷（debug 级别）
func LogTaskPayload(scope, action string, payload interface{}) {
    data, _ := json.MarshalIndent(payload, "", "  ")
    log.Debug().
        Str("scope", scope).
        Str("action", action).
        RawJSON("payload", data).
        Msg("")
}
```

---

## 9. Phase 1 验收标准

| 验收项 | 预期结果 |
|--------|----------|
| `go build ./cmd/server` | 编译通过，无错误 |
| `GET /api/v1/health` | 返回 `{"code":200,"data":{"status":"ok"},"message":"success"}` |
| `POST /api/v1/dramas` 创建剧集 | 返回 201，自动创建 N 个默认分集 |
| `GET /api/v1/dramas` 列表 | 返回分页数据，每项包含 episodes/characters/scenes |
| `GET /api/v1/dramas/stats` | 返回总数和按状态统计 |
| `PUT /api/v1/dramas/:id` | 更新成功 |
| `DELETE /api/v1/dramas/:id` | 软删除（deleted_at 非空） |
| `POST /api/v1/episodes` | 自动计算 episode_number |
| `GET /api/v1/episodes/:id/pipeline-status` | 返回 9 步流水线进度 |
| `POST /api/v1/storyboards` | 创建分镜 + 关联角色 |
| `PUT /api/v1/storyboards/:id` 更新 dialogue | 自动清除 tts_audio_url 和 subtitle_url |
| `GET /api/v1/episodes/:episode_id/storyboards` | 返回带 character_ids 和 characters 的分镜列表 |
| 前端代理测试 | 前端 dev server 代理到 Go 后端，列表页正常渲染 |
| 现有 DB 兼容 | 直接指向现有 `data/huobao_drama.db`，数据正常读写 |

---

## 10. 与 TS 版的对照表

| TS 文件 | Go 文件 | 说明 |
|---------|---------|------|
| `src/index.ts` | `cmd/server/main.go` | 入口 |
| `src/db/index.ts` | `internal/database/db.go` | DB 初始化 + Auto-DDL |
| `src/db/schema.ts` | `internal/database/models.go` | 表结构 → Go struct |
| `src/routes/dramas.ts` | `internal/handler/drama.go` | 剧集 CRUD |
| `src/routes/episodes.ts` | `internal/handler/episode.go` | 分集操作 |
| `src/routes/storyboards.ts` | `internal/handler/storyboard.go` | 分镜 CRUD |
| `src/routes/scenes.ts` | `internal/handler/scene.go` | 场景操作 |
| `src/routes/characters.ts` | `internal/handler/character.go` | 角色操作 |
| `src/middleware/logger.ts` | `internal/middleware/logger.go` | 日志中间件 |
| `src/utils/response.ts` | `internal/util/response.go` | 统一响应 |
| `src/utils/transform.ts` | `internal/util/transform.go` | 字段名转换 |
| `src/utils/task-logger.ts` | `internal/util/task_logger.go` | 任务日志 |
| — | `internal/config/config.go` | 新增：配置管理 |
| — | `internal/database/queries.go` | 新增：查询辅助函数 |
| — | `internal/middleware/cors.go` | 新增：CORS 中间件 |
| — | `Makefile` | 新增：构建命令 |
