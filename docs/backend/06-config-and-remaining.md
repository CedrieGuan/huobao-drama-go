# Phase 6 — 配置管理 + 剩余路由

> 对应 TS 版：
> - `backend/src/routes/aiConfigs.ts` — AI 服务配置 CRUD + 测试 + 一键预设
> - `backend/src/routes/agentConfigs.ts` — Agent 配置 CRUD
> - `backend/src/routes/skills.ts` — 技能文件管理（文件系统 CRUD）
> - `backend/src/routes/aiVoices.ts` — 音色列表 + 同步
> - `backend/src/services/ai.ts` — AI 配置查询服务

---

## 1. 概述

本阶段实现所有配置管理相关的路由：

| 模块 | 端点数 | 说明 |
|------|--------|------|
| AI 服务配置 | 8 | CRUD + 测试连通性 + 一键预设 + Provider 列表 |
| Agent 配置 | 5 | CRUD（upsert by agent_type） |
| 技能管理 | 5 | 文件系统 CRUD（skills/ 目录） |
| 音色管理 | 2 | 列表 + 从 Provider 同步 |

---

## 2. AI 服务配置

### 2.1 对应 TS 源码

`backend/src/routes/aiConfigs.ts` — 共 8 个端点

### 2.2 数据模型

```go
// internal/database/models.go — 已在 Phase 1 定义

// AIServiceConfig AI 服务配置
type AIServiceConfig struct {
    ID            int64      `json:"id" db:"id"`
    ServiceType   string     `json:"service_type" db:"service_type"`
    Provider      NullString `json:"provider" db:"provider"`
    Name          string     `json:"name" db:"name"`
    BaseURL       string     `json:"base_url" db:"base_url"`
    APIKey        string     `json:"api_key" db:"api_key"`
    Model         NullString `json:"model" db:"model"`        // JSON 数组字符串
    Endpoint      NullString `json:"endpoint" db:"endpoint"`
    QueryEndpoint NullString `json:"query_endpoint" db:"query_endpoint"`
    Priority      int        `json:"priority" db:"priority"`
    IsDefault     bool       `json:"is_default" db:"is_default"`
    IsActive      bool       `json:"is_active" db:"is_active"`
    Settings      NullString `json:"settings" db:"settings"`
    CreatedAt     string     `json:"created_at" db:"created_at"`
    UpdatedAt     string     `json:"updated_at" db:"updated_at"`
}
```

### 2.3 Handler 实现

```go
// internal/handler/ai_config.go

package handler

import (
    "database/sql"
    "encoding/json"
    "fmt"
    "io"
    "net/http"
    "strconv"
    "strings"
    "time"

    "github.com/gin-gonic/gin"
    sq "github.com/Masterminds/squirrel"
    "github.com/huobao-drama/backend-go/internal/adapter"
    "github.com/huobao-drama/backend-go/internal/database"
    "github.com/huobao-drama/backend-go/internal/util"
)

// GET /api/v1/ai-configs
func (h *Handler) ListAIConfigs(c *gin.Context) {
    serviceType := c.Query("service_type")

    q := psql.Select("*").From("ai_service_configs").OrderBy("priority DESC, id ASC")
    if serviceType != "" {
        q = q.Where(sq.Eq{"service_type": serviceType})
    }

    rows, err := q.RunWith(h.DB).Query()
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }
    defer rows.Close()

    type configItem struct {
        ID          int64       `json:"id"`
        ServiceType string      `json:"service_type"`
        Provider    string      `json:"provider"`
        Name        string      `json:"name"`
        BaseURL     string      `json:"base_url"`
        APIKey      string      `json:"api_key"`
        Model       interface{} `json:"model"` // 解析为数组
        Endpoint    *string     `json:"endpoint"`
        QueryEndpoint *string   `json:"query_endpoint"`
        Priority    int         `json:"priority"`
        IsDefault   bool        `json:"is_default"`
        IsActive    bool        `json:"is_active"`
        Settings    *string     `json:"settings"`
        CreatedAt   string      `json:"created_at"`
        UpdatedAt   string      `json:"updated_at"`
    }

    var items []configItem
    for rows.Next() {
        var ci configItem
        var modelJSON, endpoint, queryEndpoint, settings sql.NullString
        var isDefault, isActive int

        rows.Scan(
            &ci.ID, &ci.ServiceType, &ci.Provider, &ci.Name,
            &ci.BaseURL, &ci.APIKey, &modelJSON, &endpoint, &queryEndpoint,
            &ci.Priority, &isDefault, &isActive, &settings,
            &ci.CreatedAt, &ci.UpdatedAt,
        )

        ci.Endpoint = nullStringToPtr(endpoint)
        ci.QueryEndpoint = nullStringToPtr(queryEndpoint)
        ci.Settings = nullStringToPtr(settings)
        ci.IsDefault = isDefault == 1
        ci.IsActive = isActive == 1

        // 解析 model JSON 数组
        if modelJSON.Valid && modelJSON.String != "" {
            var models []string
            if err := json.Unmarshal([]byte(modelJSON.String), &models); err == nil {
                ci.Model = models
            } else {
                ci.Model = []string{modelJSON.String}
            }
        } else {
            ci.Model = []string{}
        }

        items = append(items, ci)
    }

    util.Success(c, items)
}

// GET /api/v1/ai-configs/:id
func (h *Handler) GetAIConfig(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    row := h.DB.QueryRow("SELECT * FROM ai_service_configs WHERE id = ?", id)
    // ... 类似 ListAIConfigs 的 scan 逻辑
    var cfg database.AIServiceConfig
    if err := scanAIServiceConfig(row, &cfg); err != nil {
        util.NotFound(c, "config not found")
        return
    }
    util.Success(c, cfg)
}

// POST /api/v1/ai-configs
func (h *Handler) CreateAIConfig(c *gin.Context) {
    var body struct {
        ServiceType string   `json:"service_type" binding:"required"`
        Provider    string   `json:"provider" binding:"required"`
        Name        string   `json:"name"`
        BaseURL     string   `json:"base_url"`
        APIKey      string   `json:"api_key"`
        Model       []string `json:"model"`
        Priority    int      `json:"priority"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "service_type and provider are required")
        return
    }

    now := database.Now()
    name := body.Name
    if name == "" {
        name = body.Provider + " " + body.ServiceType
    }

    var modelJSON *string
    if len(body.Model) > 0 {
        b, _ := json.Marshal(body.Model)
        s := string(b)
        modelJSON = &s
    }

    res, err := h.DB.Exec(
        `INSERT INTO ai_service_configs
         (service_type, provider, name, base_url, api_key, model, priority, is_active, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`,
        body.ServiceType, body.Provider, name, body.BaseURL, body.APIKey,
        modelJSON, body.Priority, now, now,
    )
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }

    id, _ := res.LastInsertId()
    util.Created(c, gin.H{"id": id})
}

// PUT /api/v1/ai-configs/:id
func (h *Handler) UpdateAIConfig(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    var body struct {
        Provider *string  `json:"provider"`
        Name     *string  `json:"name"`
        BaseURL  *string  `json:"base_url"`
        APIKey   *string  `json:"api_key"`
        Model    []string `json:"model"`
        Priority *int     `json:"priority"`
        IsActive *bool    `json:"is_active"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "invalid body")
        return
    }

    q := psql.Update("ai_service_configs")
    if body.Provider != nil {
        q = q.Set("provider", *body.Provider)
    }
    if body.Name != nil {
        q = q.Set("name", *body.Name)
    }
    if body.BaseURL != nil {
        q = q.Set("base_url", *body.BaseURL)
    }
    if body.APIKey != nil {
        q = q.Set("api_key", *body.APIKey)
    }
    if body.Model != nil {
        b, _ := json.Marshal(body.Model)
        q = q.Set("model", string(b))
    }
    if body.Priority != nil {
        q = q.Set("priority", *body.Priority)
    }
    if body.IsActive != nil {
        q = q.Set("is_active", boolToInt(*body.IsActive))
    }

    q = q.Set("updated_at", database.Now()).Where(sq.Eq{"id": id})

    if _, err := q.RunWith(h.DB).Exec(); err != nil {
        util.ServerError(c, err.Error())
        return
    }
    util.Success(c, nil)
}

// DELETE /api/v1/ai-configs/:id
func (h *Handler) DeleteAIConfig(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    h.DB.Exec("DELETE FROM ai_service_configs WHERE id = ?", id)
    util.Success(c, nil)
}

// POST /api/v1/ai-configs/test
func (h *Handler) TestAIConfig(c *gin.Context) {
    var body struct {
        ServiceType string `json:"service_type" binding:"required"`
        Provider    string `json:"provider" binding:"required"`
        BaseURL     string `json:"base_url" binding:"required"`
        APIKey      string `json:"api_key"`
        Model       string `json:"model"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "service_type, provider, base_url are required")
        return
    }

    // 根据 provider 构建探测请求
    var probeURL string
    var headers map[string]string
    var reqBody interface{}

    provider := strings.ToLower(body.Provider)

    switch provider {
    case "openai", "openrouter", "chatfire":
        probeURL = adapter.JoinProviderURL(body.BaseURL, "/v1", "/models")
        headers = map[string]string{
            "Authorization": "Bearer " + body.APIKey,
        }
    case "volcengine":
        probeURL = adapter.JoinProviderURL(body.BaseURL, "/api/v3", "/models")
        headers = map[string]string{
            "Authorization": "Bearer " + body.APIKey,
        }
    case "gemini":
        model := body.Model
        if model == "" {
            model = "gemini-2.0-flash-exp"
        }
        probeURL = adapter.JoinProviderURL(body.BaseURL, "/v1beta", "/models?key="+body.APIKey)
    case "ali":
        probeURL = adapter.JoinProviderURL(body.BaseURL, "/api/v1", "/models")
        headers = map[string]string{
            "Authorization": "Bearer " + body.APIKey,
        }
    case "minimax":
        probeURL = adapter.JoinProviderURL(body.BaseURL, "/v1", "/text/chatcompletion")
        headers = map[string]string{
            "Authorization": "Bearer " + body.APIKey,
            "Content-Type":  "application/json",
        }
        reqBody = map[string]interface{}{
            "model": body.Model,
            "messages": []map[string]string{
                {"role": "user", "content": "hi"},
            },
        }
    case "vidu":
        probeURL = adapter.JoinProviderURL(body.BaseURL, "", "/health")
        headers = map[string]string{
            "Token": body.APIKey,
        }
    default:
        // 通用探测：尝试 GET base_url
        probeURL = body.BaseURL
        headers = map[string]string{}
    }

    // 发送探测请求（10 秒超时）
    client := &http.Client{Timeout: 10 * time.Second}
    var req *http.Request
    if reqBody != nil {
        bodyBytes, _ := json.Marshal(reqBody)
        req, _ = http.NewRequest("POST", probeURL, bytes.NewReader(bodyBytes))
    } else {
        req, _ = http.NewRequest("GET", probeURL, nil)
    }
    for k, v := range headers {
        req.Header.Set(k, v)
    }

    resp, err := client.Do(req)
    if err != nil {
        util.Success(c, gin.H{
            "reachable": false,
            "error":     err.Error(),
        })
        return
    }
    defer resp.Body.Close()

    respBody, _ := io.ReadAll(resp.Body)
    preview := string(respBody)
    if len(preview) > 500 {
        preview = preview[:500] + "..."
    }

    util.Success(c, gin.H{
        "reachable":  true,
        "status":     resp.StatusCode,
        "url":        util.RedactURL(probeURL),
        "preview":    preview,
    })
}

// POST /api/v1/ai-configs/huobao-preset
// 一键预设：用同一个 API Key 创建 4 个 AI 服务配置 + 5 个 Agent 配置
func (h *Handler) HuobaoPreset(c *gin.Context) {
    var body struct {
        APIKey string `json:"api_key" binding:"required"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "api_key is required")
        return
    }

    now := database.Now()
    apiKey := body.APIKey

    // 1. 创建/更新 4 个 AI 服务配置
    type presetConfig struct {
        ServiceType string
        Provider    string
        Name        string
        BaseURL     string
        Model       []string
    }

    presets := []presetConfig{
        {
            ServiceType: "text",
            Provider:    "chatfire",
            Name:        "ChatFire 文本",
            BaseURL:     "https://api.chatfire.cn",
            Model:       []string{"gpt-4o"},
        },
        {
            ServiceType: "image",
            Provider:    "gemini",
            Name:        "Gemini 图片",
            BaseURL:     "https://generativelanguage.googleapis.com",
            Model:       []string{"gemini-2.0-flash-exp"},
        },
        {
            ServiceType: "video",
            Provider:    "volcengine",
            Name:        "火山引擎视频",
            BaseURL:     "https://visual.volcengineapi.com",
            Model:       []string{"doubao-seedance-1-0-lite-250428"},
        },
        {
            ServiceType: "audio",
            Provider:    "minimax",
            Name:        "MiniMax 音频",
            BaseURL:     "https://api.minimax.chat",
            Model:       []string{"speech-02"},
        },
    }

    for _, p := range presets {
        modelJSON, _ := json.Marshal(p.Model)

        // 检查是否已存在
        var existingID int64
        err := h.DB.QueryRow(
            "SELECT id FROM ai_service_configs WHERE service_type = ? AND provider = ?",
            p.ServiceType, p.Provider,
        ).Scan(&existingID)

        if err == nil {
            // 已存在 → 更新
            h.DB.Exec(
                `UPDATE ai_service_configs SET api_key = ?, model = ?, updated_at = ? WHERE id = ?`,
                apiKey, string(modelJSON), now, existingID,
            )
        } else {
            // 不存在 → 新增
            h.DB.Exec(
                `INSERT INTO ai_service_configs
                 (service_type, provider, name, base_url, api_key, model, priority, is_active, created_at, updated_at)
                 VALUES (?, ?, ?, ?, ?, ?, 0, 1, ?, ?)`,
                p.ServiceType, p.Provider, p.Name, p.BaseURL, apiKey,
                string(modelJSON), now, now,
            )
        }
    }

    // 2. 创建/更新 5 个 Agent 配置
    agentTypes := []string{
        "script_rewriter", "extractor", "storyboard_breaker",
        "voice_assigner", "grid_prompt_generator",
    }

    for _, agentType := range agentTypes {
        defaults, ok := agent.DefaultPrompts[agentType]
        if !ok {
            continue
        }

        // 检查是否已存在
        var existingID int64
        err := h.DB.QueryRow(
            "SELECT id FROM agent_configs WHERE agent_type = ?", agentType,
        ).Scan(&existingID)

        if err == nil {
            // 更新 + 取消软删
            h.DB.Exec(
                `UPDATE agent_configs SET name = ?, is_active = 1, deleted_at = NULL, updated_at = ? WHERE id = ?`,
                defaults.Name, now, existingID,
            )
        } else {
            // 新增
            h.DB.Exec(
                `INSERT INTO agent_configs (agent_type, name, is_active, created_at, updated_at)
                 VALUES (?, ?, 1, ?, ?)`,
                agentType, defaults.Name, now, now,
            )
        }
    }

    util.Success(c, gin.H{
        "message":    "Preset configured successfully",
        "ai_configs": 4,
        "agent_configs": 5,
    })
}

// GET /api/v1/ai-providers
func (h *Handler) ListAIProviders(c *gin.Context) {
    // 优先从数据库读取 ai_service_providers 表
    rows, err := h.DB.Query("SELECT * FROM ai_service_providers WHERE is_active = 1 ORDER BY id ASC")
    if err == nil {
        defer rows.Close()
        var providers []map[string]interface{}
        for rows.Next() {
            var id int64
            var name, serviceType, provider string
            var displayName, defaultURL, presetModels, desc sql.NullString

            rows.Scan(&id, &name, &displayName, &serviceType, &provider,
                &defaultURL, &presetModels, &desc, &id, &id, &id)
            // 实际 scan 字段需要匹配表结构

            item := map[string]interface{}{
                "name":         name,
                "service_type": serviceType,
                "provider":     provider,
            }
            if displayName.Valid {
                item["display_name"] = displayName.String
            }
            if defaultURL.Valid {
                item["default_url"] = defaultURL.String
            }
            if presetModels.Valid {
                var models []string
                json.Unmarshal([]byte(presetModels.String), &models)
                item["preset_models"] = models
            }
            providers = append(providers, item)
        }

        if len(providers) > 0 {
            util.Success(c, providers)
            return
        }
    }

    // 回退到硬编码列表
    util.Success(c, adapter.GetProviderList())
}

// ========== 辅助函数 ==========

func nullStringToPtr(ns sql.NullString) *string {
    if ns.Valid {
        return &ns.String
    }
    return nil
}

func boolToInt(b bool) int {
    if b {
        return 1
    }
    return 0
}
```

---

## 3. Agent 配置管理

### 3.1 对应 TS 源码

`backend/src/routes/agentConfigs.ts` — 共 5 个端点

### 3.2 Handler 实现

```go
// internal/handler/agent_config.go

package handler

import (
    "database/sql"
    "encoding/json"
    "strconv"

    "github.com/gin-gonic/gin"
    sq "github.com/Masterminds/squirrel"
    "github.com/huobao-drama/backend-go/internal/agent"
    "github.com/huobao-drama/backend-go/internal/database"
    "github.com/huobao-drama/backend-go/internal/util"
)

// GET /api/v1/agent-configs
func (h *Handler) ListAgentConfigs(c *gin.Context) {
    rows, err := h.DB.Query(
        `SELECT id, agent_type, name, description, model, system_prompt,
                temperature, max_tokens, max_iterations, is_active,
                created_at, updated_at, deleted_at
         FROM agent_configs
         WHERE deleted_at IS NULL
         ORDER BY agent_type ASC`,
    )
    if err != nil {
        util.ServerError(c, err.Error())
        return
    }
    defer rows.Close()

    var configs []database.AgentConfig
    for rows.Next() {
        var cfg database.AgentConfig
        scanAgentConfigRow(rows, &cfg)
        configs = append(configs, cfg)
    }

    util.Success(c, configs)
}

// GET /api/v1/agent-configs/:id
func (h *Handler) GetAgentConfig(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    row := h.DB.QueryRow(
        `SELECT id, agent_type, name, description, model, system_prompt,
                temperature, max_tokens, max_iterations, is_active,
                created_at, updated_at, deleted_at
         FROM agent_configs WHERE id = ? AND deleted_at IS NULL`, id,
    )

    var cfg database.AgentConfig
    if err := scanAgentConfigRowSingle(row, &cfg); err != nil {
        util.NotFound(c, "agent config not found")
        return
    }
    util.Success(c, cfg)
}

// POST /api/v1/agent-configs
// Upsert by agent_type：如果同类型已存在（含软删），则更新并取消软删；否则新增
func (h *Handler) CreateAgentConfig(c *gin.Context) {
    var body struct {
        AgentType     string   `json:"agent_type" binding:"required"`
        Name          string   `json:"name"`
        Description   string   `json:"description"`
        Model         string   `json:"model"`
        SystemPrompt  string   `json:"system_prompt"`
        Temperature   *float64 `json:"temperature"`
        MaxTokens     *int     `json:"max_tokens"`
        MaxIterations *int     `json:"max_iterations"`
        IsActive      *bool    `json:"is_active"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "agent_type is required")
        return
    }

    // 校验 agent_type
    if !agent.IsValidAgentType(body.AgentType) {
        util.BadRequest(c, "invalid agent_type: "+body.AgentType)
        return
    }

    now := database.Now()

    // 检查是否已存在（含软删）
    var existingID int64
    err := h.DB.QueryRow(
        "SELECT id FROM agent_configs WHERE agent_type = ?", body.AgentType,
    ).Scan(&existingID)

    if err == nil {
        // 已存在 → 更新
        q := psql.Update("agent_configs").
            Set("updated_at", now).
            Set("deleted_at", nil).
            Set("is_active", 1)

        if body.Name != "" {
            q = q.Set("name", body.Name)
        }
        if body.Description != "" {
            q = q.Set("description", body.Description)
        }
        if body.Model != "" {
            q = q.Set("model", body.Model)
        }
        if body.SystemPrompt != "" {
            q = q.Set("system_prompt", body.SystemPrompt)
        }
        if body.Temperature != nil {
            q = q.Set("temperature", *body.Temperature)
        }
        if body.MaxTokens != nil {
            q = q.Set("max_tokens", *body.MaxTokens)
        }
        if body.MaxIterations != nil {
            q = q.Set("max_iterations", *body.MaxIterations)
        }

        q = q.Where(sq.Eq{"id": existingID})
        q.RunWith(h.DB).Exec()

        util.Success(c, gin.H{"id": existingID, "action": "updated"})
    } else {
        // 不存在 → 新增
        name := body.Name
        if name == "" {
            defaults, _ := agent.DefaultPrompts[body.AgentType]
            name = defaults.Name
        }

        res, err := h.DB.Exec(
            `INSERT INTO agent_configs
             (agent_type, name, description, model, system_prompt,
              temperature, max_tokens, max_iterations, is_active, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`,
            body.AgentType, name,
            util.NullIfEmpty(body.Description),
            util.NullIfEmpty(body.Model),
            util.NullIfEmpty(body.SystemPrompt),
            body.Temperature, body.MaxTokens, body.MaxIterations,
            now, now,
        )
        if err != nil {
            util.ServerError(c, err.Error())
            return
        }
        id, _ := res.LastInsertId()
        util.Created(c, gin.H{"id": id, "action": "created"})
    }
}

// PUT /api/v1/agent-configs/:id
func (h *Handler) UpdateAgentConfig(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    var body struct {
        Name          *string  `json:"name"`
        Description   *string  `json:"description"`
        Model         *string  `json:"model"`
        SystemPrompt  *string  `json:"system_prompt"`
        Temperature   *float64 `json:"temperature"`
        MaxTokens     *int     `json:"max_tokens"`
        MaxIterations *int     `json:"max_iterations"`
        IsActive      *bool    `json:"is_active"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "invalid body")
        return
    }

    q := psql.Update("agent_configs")
    if body.Name != nil {
        q = q.Set("name", *body.Name)
    }
    if body.Description != nil {
        q = q.Set("description", *body.Description)
    }
    if body.Model != nil {
        q = q.Set("model", *body.Model)
    }
    if body.SystemPrompt != nil {
        q = q.Set("system_prompt", *body.SystemPrompt)
    }
    if body.Temperature != nil {
        q = q.Set("temperature", *body.Temperature)
    }
    if body.MaxTokens != nil {
        q = q.Set("max_tokens", *body.MaxTokens)
    }
    if body.MaxIterations != nil {
        q = q.Set("max_iterations", *body.MaxIterations)
    }
    if body.IsActive != nil {
        q = q.Set("is_active", boolToInt(*body.IsActive))
    }

    q = q.Set("updated_at", database.Now()).Where(sq.Eq{"id": id})

    if _, err := q.RunWith(h.DB).Exec(); err != nil {
        util.ServerError(c, err.Error())
        return
    }
    util.Success(c, nil)
}

// DELETE /api/v1/agent-configs/:id — 软删除
func (h *Handler) DeleteAgentConfig(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    h.DB.Exec(
        "UPDATE agent_configs SET deleted_at = ?, updated_at = ? WHERE id = ?",
        database.Now(), database.Now(), id,
    )
    util.Success(c, nil)
}

// ========== Scan 辅助函数 ==========

func scanAgentConfigRow(rows *sql.Rows, cfg *database.AgentConfig) {
    rows.Scan(
        &cfg.ID, &cfg.AgentType, &cfg.Name, &cfg.Description,
        &cfg.Model, &cfg.SystemPrompt, &cfg.Temperature,
        &cfg.MaxTokens, &cfg.MaxIterations, &cfg.IsActive,
        &cfg.CreatedAt, &cfg.UpdatedAt, &cfg.DeletedAt,
    )
}

func scanAgentConfigRowSingle(row *sql.Row, cfg *database.AgentConfig) error {
    return row.Scan(
        &cfg.ID, &cfg.AgentType, &cfg.Name, &cfg.Description,
        &cfg.Model, &cfg.SystemPrompt, &cfg.Temperature,
        &cfg.MaxTokens, &cfg.MaxIterations, &cfg.IsActive,
        &cfg.CreatedAt, &cfg.UpdatedAt, &cfg.DeletedAt,
    )
}
```

---

## 4. 技能管理

### 4.1 对应 TS 源码

`backend/src/routes/skills.ts` — 文件系统 CRUD，操作 `skills/` 目录下的 `SKILL.md` 文件。

### 4.2 TS 版行为详解

```
skills/
├── extractor/
│   └── SKILL.md
├── grid_prompt_generator/
│   └── SKILL.md
├── script_rewriter/
│   └── SKILL.md
├── storyboard_breaker/
│   └── SKILL.md
└── voice_assigner/
    └── SKILL.md
```

| 端点 | 行为 |
|------|------|
| `GET /api/v1/skills` | 递归扫描 skills/ 目录，解析每个 SKILL.md 的 YAML frontmatter，返回 `{id, name, description}` 列表 |
| `GET /api/v1/skills/*id` | 返回指定 SKILL.md 的原始文本内容 |
| `POST /api/v1/skills` | 创建新的 skill 目录 + SKILL.md（带 frontmatter 模板） |
| `PUT /api/v1/skills/*id` | 更新 SKILL.md 的内容 |
| `DELETE /api/v1/skills/*id` | 递归删除整个 skill 目录 |

### 4.3 Handler 实现

```go
// internal/handler/skill.go

package handler

import (
    "fmt"
    "os"
    "path/filepath"
    "regexp"
    "strings"

    "github.com/gin-gonic/gin"
    "github.com/huobao-drama/backend-go/internal/util"
)

// skillsDir 在 main.go 中通过 flag 或配置设置
// 与 agent/skills.go 共享同一目录
var SkillsDir string

// GET /api/v1/skills
func (h *Handler) ListSkills(c *gin.Context) {
    type skillInfo struct {
        ID          string `json:"id"`
        Name        string `json:"name"`
        Description string `json:"description"`
    }

    entries, err := os.ReadDir(SkillsDir)
    if err != nil {
        util.Success(c, []skillInfo{})
        return
    }

    var skills []skillInfo
    for _, entry := range entries {
        if !entry.IsDir() {
            continue
        }

        skillPath := filepath.Join(SkillsDir, entry.Name(), "SKILL.md")
        data, err := os.ReadFile(skillPath)
        if err != nil {
            continue
        }

        // 解析 frontmatter
        name, desc := parseFrontmatter(string(data))
        if name == "" {
            name = entry.Name()
        }

        skills = append(skills, skillInfo{
            ID:          entry.Name(),
            Name:        name,
            Description: desc,
        })
    }

    util.Success(c, skills)
}

// GET /api/v1/skills/*id
func (h *Handler) GetSkill(c *gin.Context) {
    // Gin 的 /*id 路由参数包含前导斜杠
    id := strings.TrimPrefix(c.Param("id"), "/")
    if id == "" {
        util.BadRequest(c, "skill id is required")
        return
    }

    skillPath := filepath.Join(SkillsDir, id, "SKILL.md")
    data, err := os.ReadFile(skillPath)
    if err != nil {
        util.NotFound(c, "skill not found")
        return
    }

    c.Header("Content-Type", "text/plain; charset=utf-8")
    c.String(200, string(data))
}

// POST /api/v1/skills
func (h *Handler) CreateSkill(c *gin.Context) {
    var body struct {
        ID          string `json:"id" binding:"required"`
        Name        string `json:"name"`
        Description string `json:"description"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "id is required")
        return
    }

    // 校验 ID 不能包含路径分隔符
    if strings.Contains(body.ID, "/") || strings.Contains(body.ID, "..") {
        util.BadRequest(c, "invalid skill id")
        return
    }

    skillDir := filepath.Join(SkillsDir, body.ID)
    if _, err := os.Stat(skillDir); err == nil {
        util.BadRequest(c, "skill already exists")
        return
    }

    os.MkdirAll(skillDir, 0755)

    name := body.Name
    if name == "" {
        name = body.ID
    }

    // 写入带 frontmatter 的模板
    content := fmt.Sprintf("---\nname: %s\ndescription: %s\n---\n\n# %s\n\nWrite your skill instructions here.\n",
        name, body.Description, name,
    )
    os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte(content), 0644)

    util.Created(c, gin.H{"id": body.ID})
}

// PUT /api/v1/skills/*id
func (h *Handler) UpdateSkill(c *gin.Context) {
    id := strings.TrimPrefix(c.Param("id"), "/")
    if id == "" {
        util.BadRequest(c, "skill id is required")
        return
    }

    var body struct {
        Content string `json:"content"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "content is required")
        return
    }

    skillPath := filepath.Join(SkillsDir, id, "SKILL.md")

    // 如果目录不存在则创建
    os.MkdirAll(filepath.Dir(skillPath), 0755)

    if err := os.WriteFile(skillPath, []byte(body.Content), 0644); err != nil {
        util.ServerError(c, err.Error())
        return
    }

    util.Success(c, nil)
}

// DELETE /api/v1/skills/*id
func (h *Handler) DeleteSkill(c *gin.Context) {
    id := strings.TrimPrefix(c.Param("id"), "/")
    if id == "" {
        util.BadRequest(c, "skill id is required")
        return
    }

    skillDir := filepath.Join(SkillsDir, id)
    if err := os.RemoveAll(skillDir); err != nil {
        util.ServerError(c, err.Error())
        return
    }

    util.Success(c, nil)
}

// ========== Frontmatter 解析 ==========

var frontmatterRe = regexp.MustCompile(`(?s)^---\s*\n(.*?)\n---`)

type frontmatter struct {
    Name        string `yaml:"name"`
    Description string `yaml:"description"`
}

func parseFrontmatter(content string) (name, description string) {
    matches := frontmatterRe.FindStringSubmatch(content)
    if len(matches) < 2 {
        return "", ""
    }

    fmContent := matches[1]

    // 简易 YAML 解析（不引入 yaml 依赖）
    for _, line := range strings.Split(fmContent, "\n") {
        line = strings.TrimSpace(line)
        if strings.HasPrefix(line, "name:") {
            name = strings.TrimSpace(strings.TrimPrefix(line, "name:"))
            name = strings.Trim(name, "\"'")
        }
        if strings.HasPrefix(line, "description:") {
            description = strings.TrimSpace(strings.TrimPrefix(line, "description:"))
            description = strings.Trim(description, "\"'")
        }
    }

    return name, description
}
```

---

## 5. 音色管理

### 5.1 对应 TS 源码

`backend/src/routes/aiVoices.ts` — 2 个端点

### 5.2 Handler 实现

```go
// internal/handler/ai_voice.go

package handler

import (
    "database/sql"
    "encoding/json"
    "net/http"
    "regexp"
    "strings"

    "github.com/gin-gonic/gin"
    "github.com/huobao-drama/backend-go/internal/adapter"
    "github.com/huobao-drama/backend-go/internal/database"
    "github.com/huobao-drama/backend-go/internal/service"
    "github.com/huobao-drama/backend-go/internal/util"
)

// GET /api/v1/ai-voices
func (h *Handler) ListAIVoices(c *gin.Context) {
    provider := c.DefaultQuery("provider", "minimax")

    rows, err := h.DB.Query(
        `SELECT id, voice_id, voice_name, description, language, provider, created_at
         FROM ai_voices WHERE provider = ?
         ORDER BY voice_name ASC`, provider,
    )
    if err != nil {
        util.Success(c, []interface{}{})
        return
    }
    defer rows.Close()

    var voices []map[string]interface{}
    for rows.Next() {
        var id int64
        var voiceID, voiceName string
        var description, language, provider, createdAt sql.NullString

        rows.Scan(&id, &voiceID, &voiceName, &description, &language, &provider, &createdAt)

        // 解析 description JSON
        var desc []string
        if description.Valid && description.String != "" {
            json.Unmarshal([]byte(description.String), &desc)
        }

        voices = append(voices, map[string]interface{}{
            "id":          id,
            "voice_id":    voiceID,
            "voice_name":  voiceName,
            "description": desc,
            "language":    language.String,
            "provider":    provider.String,
            "created_at":  createdAt.String,
        })
    }

    util.Success(c, voices)
}

// POST /api/v1/ai-voices/sync
func (h *Handler) SyncAIVoices(c *gin.Context) {
    // 1. 获取 MiniMax 音频配置
    config, err := service.GetActiveConfig(h.DB, service.ServiceTypeAudio)
    if err != nil || config == nil {
        util.BadRequest(c, "no active audio AI config")
        return
    }

    // 2. 调用 MiniMax /v1/get_voice API
    reqURL := adapter.JoinProviderURL(config.BaseURL, "/v1", "/get_voice")
    req, _ := http.NewRequest("POST", reqURL, nil)
    req.Header.Set("Authorization", "Bearer "+config.APIKey)
    req.Header.Set("Content-Type", "application/json")

    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        util.BadRequest(c, "failed to fetch voices: "+err.Error())
        return
    }
    defer resp.Body.Close()

    var result struct {
        Data struct {
            Voices []struct {
                VoiceID     string   `json:"voice_id"`
                VoiceName   string   `json:"voice_name"`
                Description []string `json:"description"`
                Language    []string `json:"language"`
            } `json:"voices"`
        } `json:"data"`
    }
    json.NewDecoder(resp.Body).Decode(&result)

    // 3. 过滤：只保留中文和粤语，排除 beta/cartoon 等模式
    excludePatterns := regexp.MustCompile(`(?i)(beta|卡通|cartoon|动漫)`)

    type voiceEntry struct {
        VoiceID     string
        VoiceName   string
        Description string // JSON
        Language    string
    }
    var filtered []voiceEntry

    for _, v := range result.Data.Voices {
        if excludePatterns.MatchString(v.VoiceName) {
            continue
        }

        // 检查语言
        hasChinese := false
        var langParts []string
        for _, lang := range v.Language {
            langParts = append(langParts, lang)
            lower := strings.ToLower(lang)
            if strings.Contains(lower, "zh") ||
                strings.Contains(lower, "cantonese") ||
                strings.Contains(lower, "chinese") {
                hasChinese = true
            }
        }
        if !hasChinese {
            continue
        }

        descJSON, _ := json.Marshal(v.Description)
        filtered = append(filtered, voiceEntry{
            VoiceID:     v.VoiceID,
            VoiceName:   v.VoiceName,
            Description: string(descJSON),
            Language:    strings.Join(langParts, ","),
        })
    }

    // 4. 清除旧记录并批量插入（事务）
    tx, _ := h.DB.Begin()
    tx.Exec("DELETE FROM ai_voices WHERE provider = ?", config.Provider)
    now := database.Now()
    for _, v := range filtered {
        tx.Exec(
            `INSERT INTO ai_voices (voice_id, voice_name, description, language, provider, created_at)
             VALUES (?, ?, ?, ?, ?, ?)`,
            v.VoiceID, v.VoiceName, v.Description, v.Language, config.Provider, now,
        )
    }
    tx.Commit()

    util.Success(c, gin.H{
        "synced": len(filtered),
        "total":  len(result.Data.Voices),
    })
}
```

---

## 6. 补充：Character 和 Scene 的生成端点

Phase 3 留了占位符，这里补充完整实现。

### 6.1 Character 生成端点

```go
// internal/handler/character.go — 补充 Phase 3 的占位方法

// POST /api/v1/characters/:id/generate-voice-sample
func (h *Handler) GenerateCharacterVoiceSample(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    var body struct {
        EpisodeID int64 `json:"episode_id" binding:"required"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "episode_id is required")
        return
    }

    // 查询角色
    var charName string
    var voiceStyle sql.NullString
    h.DB.QueryRow(
        "SELECT name, voice_style FROM characters WHERE id = ?", id,
    ).Scan(&charName, &voiceStyle)

    if !voiceStyle.Valid || voiceStyle.String == "" {
        util.BadRequest(c, "character has no voice_style assigned")
        return
    }

    // 查询分集的音频配置 ID
    var audioConfigID sql.NullInt64
    h.DB.QueryRow("SELECT audio_config_id FROM episodes WHERE id = ?", body.EpisodeID).
        Scan(&audioConfigID)

    var configID *int64
    if audioConfigID.Valid {
        configID = &audioConfigID.Int64
    }

    // 生成试听音频
    localPath, err := service.GenerateVoiceSample(h.DB, charName, voiceStyle.String, configID)
    if err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    // 更新角色
    h.DB.Exec(
        "UPDATE characters SET voice_sample_url = ?, updated_at = ? WHERE id = ?",
        localPath, database.Now(), id,
    )

    util.Success(c, gin.H{
        "voice_sample_url": localPath,
    })
}

// POST /api/v1/characters/:id/generate-image
func (h *Handler) GenerateCharacterImage(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    var body struct {
        EpisodeID int64 `json:"episode_id" binding:"required"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "episode_id is required")
        return
    }

    // 查询角色信息
    var charName string
    var appearance sql.NullString
    h.DB.QueryRow(
        "SELECT name, appearance FROM characters WHERE id = ?", id,
    ).Scan(&charName, &appearance)

    // 构建 prompt
    prompt := fmt.Sprintf("Portrait of character %s", charName)
    if appearance.Valid && appearance.String != "" {
        prompt = fmt.Sprintf("%s, %s, cinematic portrait, high quality, consistent art style",
            charName, appearance.String)
    }

    // 查询分集的图片配置
    var imageConfigID sql.NullInt64
    h.DB.QueryRow("SELECT image_config_id FROM episodes WHERE id = ?", body.EpisodeID).
        Scan(&imageConfigID)

    // 获取 drama_id
    var dramaID int64
    h.DB.QueryRow("SELECT drama_id FROM characters WHERE id = ?", id).Scan(&dramaID)

    var configID *int64
    if imageConfigID.Valid {
        configID = &imageConfigID.Int64
    }

    genID, err := service.GenerateImage(h.DB, service.ImageGenParams{
        DramaID:     &dramaID,
        CharacterID: &id,
        Prompt:      prompt,
        ConfigID:    configID,
    })
    if err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    util.Success(c, gin.H{
        "id":     genID,
        "status": "processing",
    })
}

// POST /api/v1/characters/batch-generate-images
func (h *Handler) BatchGenerateCharacterImages(c *gin.Context) {
    var body struct {
        CharacterIDs []int64 `json:"character_ids" binding:"required"`
        EpisodeID    int64   `json:"episode_id" binding:"required"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "character_ids and episode_id are required")
        return
    }

    successCount := 0
    for _, charID := range body.CharacterIDs {
        var charName string
        var appearance sql.NullString
        var dramaID int64
        h.DB.QueryRow(
            "SELECT name, appearance, drama_id FROM characters WHERE id = ?", charID,
        ).Scan(&charName, &appearance, &dramaID)

        prompt := fmt.Sprintf("Portrait of %s", charName)
        if appearance.Valid {
            prompt = fmt.Sprintf("%s, %s, cinematic portrait, high quality", charName, appearance.String)
        }

        // 查询分集的图片配置
        var imageConfigID sql.NullInt64
        h.DB.QueryRow("SELECT image_config_id FROM episodes WHERE id = ?", body.EpisodeID).
            Scan(&imageConfigID)

        var configID *int64
        if imageConfigID.Valid {
            configID = &imageConfigID.Int64
        }

        _, err := service.GenerateImage(h.DB, service.ImageGenParams{
            DramaID:     &dramaID,
            CharacterID: &charID,
            Prompt:      prompt,
            ConfigID:    configID,
        })
        if err == nil {
            successCount++
        }
    }

    util.Success(c, gin.H{
        "total":    len(body.CharacterIDs),
        "started":  successCount,
    })
}
```

### 6.2 Scene 生成端点

```go
// internal/handler/scene.go — 补充 GenerateSceneImage

// POST /api/v1/scenes/:id/generate-image
func (h *Handler) GenerateSceneImage(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    var body struct {
        EpisodeID int64 `json:"episode_id" binding:"required"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "episode_id is required")
        return
    }

    // 查询场景信息
    var location, prompt string
    var dramaID int64
    h.DB.QueryRow(
        "SELECT location, prompt, drama_id FROM scenes WHERE id = ?", id,
    ).Scan(&location, &prompt, &dramaID)

    // 更新场景状态
    h.DB.Exec("UPDATE scenes SET status = 'processing', updated_at = ? WHERE id = ?",
        database.Now(), id)

    // 查询分集的图片配置
    var imageConfigID sql.NullInt64
    h.DB.QueryRow("SELECT image_config_id FROM episodes WHERE id = ?", body.EpisodeID).
        Scan(&imageConfigID)

    var configID *int64
    if imageConfigID.Valid {
        configID = &imageConfigID.Int64
    }

    // 构建提示词
    fullPrompt := fmt.Sprintf("%s scene, %s, cinematic, high quality, no text, no watermark",
        location, prompt)

    genID, err := service.GenerateImage(h.DB, service.ImageGenParams{
        DramaID:  &dramaID,
        SceneID:  &id,
        Prompt:   fullPrompt,
        ConfigID: configID,
    })
    if err != nil {
        h.DB.Exec("UPDATE scenes SET status = 'failed', updated_at = ? WHERE id = ?",
            database.Now(), id)
        util.BadRequest(c, err.Error())
        return
    }

    util.Success(c, gin.H{
        "id":     genID,
        "status": "processing",
    })
}
```

---

## 7. 路由注册汇总

Phase 6 涉及的路由注册：

```go
// 在 cmd/server/main.go 的 setupRouter 中注册

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

// Skills
v1.GET("/skills", h.ListSkills)
v1.GET("/skills/*id", h.GetSkill)
v1.POST("/skills", h.CreateSkill)
v1.PUT("/skills/*id", h.UpdateSkill)
v1.DELETE("/skills/*id", h.DeleteSkill)

// AI Voices
v1.GET("/ai-voices", h.ListAIVoices)
v1.POST("/ai-voices/sync", h.SyncAIVoices)
```

---

## 8. 依赖关系

### 8.1 Phase 6 依赖

- **Phase 1**：数据库模型、统一响应格式、查询辅助函数
- **Phase 2**：`adapter.JoinProviderURL`、`adapter.GetProviderList`
- **Phase 5**：`agent.DefaultPrompts`、`agent.IsValidAgentType`

### 8.2 Phase 6 为 Phase 7 提供

- AI 配置测试接口（集成测试用）
- 一键预设（快速搭建测试环境）
- 音色同步（测试 TTS 流程）

---

## 9. 测试要点

### 9.1 AI 配置 CRUD

| 测试场景 | 验证内容 |
|----------|----------|
| 创建配置 | 正确插入 service_type + provider + model JSON |
| 更新配置 | 只更新提供的字段 |
| 删除配置 | 硬删除（非软删） |
| 按 service_type 过滤 | 只返回对应类型 |
| model 字段解析 | `["gpt-4o"]` 正确解析为数组 |

### 9.2 AI 配置测试

| 测试场景 | 验证内容 |
|----------|----------|
| OpenAI provider | 探测 `/v1/models` |
| Gemini provider | 探测 `/v1beta/models` |
| MiniMax provider | 发送 POST 请求 |
| 无效 URL | reachable=false |
| 无效 API Key | reachable=true 但 status >= 400 |

### 9.3 一键预设

| 测试场景 | 验证内容 |
|----------|----------|
| 首次执行 | 创建 4 个 AI 配置 + 5 个 Agent 配置 |
| 重复执行 | 更新已有配置，不重复创建 |
| Agent 配置含软删 | 取消软删 |

### 9.4 Agent 配置

| 测试场景 | 验证内容 |
|----------|----------|
| 创建（新 agent_type） | 正确插入 |
| 创建（已存在 agent_type） | 更新已有记录 |
| 软删除 | deleted_at 非空，列表不显示 |
| 无效 agent_type | 返回 400 |

### 9.5 技能管理

| 测试场景 | 验证内容 |
|----------|----------|
| 列表 | 返回所有含 SKILL.md 的子目录 |
| 获取内容 | 返回原始 Markdown |
| 创建 | 生成带 frontmatter 的模板 |
| 更新 | 覆盖 SKILL.md 内容 |
| 删除 | 整个目录被移除 |
| 路径安全 | `../../etc` 等路径被拒绝 |

### 9.6 音色管理

| 测试场景 | 验证内容 |
|----------|----------|
| 列表（默认 provider） | 返回 minimax 音色 |
| 列表（指定 provider） | 按指定 provider 过滤 |
| 同步 | 清除旧数据并插入新数据 |
| 同步（无音频配置） | 返回 400 |

---

## 10. 与 TS 版的对照表

| TS 文件 | Go 文件 | 说明 |
|---------|---------|------|
| `routes/aiConfigs.ts` | `handler/ai_config.go` | AI 配置 CRUD + 测试 + 预设 |
| `routes/agentConfigs.ts` | `handler/agent_config.go` | Agent 配置 CRUD |
| `routes/skills.ts` | `handler/skill.go` | 技能文件管理 |
| `routes/aiVoices.ts` | `handler/ai_voice.go` | 音色列表 + 同步 |
| `services/ai.ts` | `service/ai_config.go` (Phase 3) | AI 配置查询服务 |
| — | `handler/character.go` (补充) | 角色图片/语音生成 |
| — | `handler/scene.go` (补充) | 场景图片生成 |