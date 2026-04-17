# Phase 3 — 图片/视频/TTS 生成服务

> 对应 TS 版：`services/ai.ts`、`services/image-generation.ts`、`services/video-generation.ts`、`services/tts-generation.ts`、`routes/images.ts`、`routes/videos.ts`、`routes/upload.ts`、`routes/aiVoices.ts`、`routes/webhooks.ts`、`utils/storage.ts`

---

## 1. 概述

本阶段实现所有 AI 内容生成相关的核心服务和路由：

- **AI 配置查询**：按 serviceType + priority 查询活跃配置
- **图片生成**：提交任务 → 调用 Provider API → 同步/异步处理 → 下载保存 → 更新关联表
- **视频生成**：提交任务 → 调用 Provider API → 异步轮询/Webhook → 下载保存 → 更新关联表
- **TTS 合成**：文本 → Provider API → hex 解码 → 保存音频文件
- **Vidu Webhook**：接收回调 → 下载视频 → 更新记录
- **文件存储**：远程文件下载、上传文件保存、base64 图片保存、图片压缩为 DataURL
- **音色管理**：音色列表查询、从 Provider 同步音色库

### 1.1 生产替换补充要求

仅靠 goroutine 异步执行还不够支撑生产替换，Go 版必须补齐以下运行时约束：

- **可恢复**：进程重启后，`processing/pending` 任务不能永久卡死
- **可终止**：优雅关闭时不再接收新请求，已有轮询任务允许在超时内收尾
- **可判定**：需要明确哪些任务可继续轮询，哪些任务应标记为失败
- **可观测**：所有任务都必须带 `generation_id/task_id/provider/status` 结构化日志

### 1.2 任务生命周期设计

```
created/pending
    ↓
processing
    ├── completed
    └── failed
```

补充规则：

1. 创建 DB 记录后才启动后台任务，避免“远端已发起但本地无记录”
2. 异步任务拿到 `task_id` 后必须立刻落库
3. 只有 `task_id` 已知的 `processing` 任务才允许在重启后恢复轮询
4. 没有 `task_id` 且长时间停留在 `processing` 的任务，启动恢复时直接标记为 `failed`
5. 每次轮询都更新 `updated_at`，用于识别僵尸任务

### 1.3 启动恢复机制

```go
// internal/service/task_recovery.go

func ResumePendingTasks(db *sql.DB) error {
    // 图片任务：可恢复的继续轮询，不可恢复的标记失败
    imageRows, err := listRecoverableImageTasks(db)
    if err != nil {
        return err
    }
    for _, row := range imageRows {
        switch {
        case row.TaskID != "" && row.Status == "processing":
            cfg, _ := GetConfigByProvider(db, ServiceTypeImage, row.Provider, row.Model)
            if cfg != nil {
                go pollImageTask(db, row.ID, *cfg, row.TaskID)
            }
        case row.TaskID == "" && isStale(row.UpdatedAt, 2*time.Minute):
            updateImageGenStatus(db, row.ID, "failed", "interrupted before task_id persisted")
        }
    }

    // 视频任务：同理；Vidu webhook-only 任务只恢复状态，不主动重复提交
    videoRows, err := listRecoverableVideoTasks(db)
    if err != nil {
        return err
    }
    for _, row := range videoRows {
        switch {
        case row.Provider == "vidu":
            // webhook-only provider，保留 processing，等待回调或由清理任务超时失败
        case row.TaskID != "" && row.Status == "processing":
            cfg, _ := GetConfigByProvider(db, ServiceTypeVideo, row.Provider, row.Model)
            if cfg != nil {
                go pollVideoTask(db, row.ID, *cfg, row.TaskID)
            }
        case row.TaskID == "" && isStale(row.UpdatedAt, 2*time.Minute):
            updateVideoGenStatus(db, row.ID, "failed", "interrupted before task_id persisted")
        }
    }
    return nil
}
```

### 1.4 关闭与超时策略

- HTTP Server 使用 `Shutdown(context.WithTimeout(...))`
- 新请求在关闭开始后拒绝进入长任务
- 单次 Provider 请求设置 timeout
- 轮询任务有总超时上限
- 超时和主动中断都要回写最终错误原因

---

## 2. AI 配置查询服务

### 2.1 对应 TS 源码

`backend/src/services/ai.ts`

### 2.2 Go 实现

```go
// internal/service/ai_config.go

// ServiceType 对应 TS 版的 ServiceType
type ServiceType string

const (
    ServiceTypeText  ServiceType = "text"
    ServiceTypeImage ServiceType = "image"
    ServiceTypeVideo ServiceType = "video"
    ServiceTypeAudio ServiceType = "audio"
)

// AIConfig 是从 ai_service_configs 表查询出的活跃配置
type AIConfig struct {
    Provider string
    BaseURL  string
    APIKey   string
    Model    string   // models JSON 数组的第一个元素
}

// GetActiveConfig 按 serviceType 查询活跃配置，按 priority 降序取第一个
func GetActiveConfig(db *sql.DB, serviceType ServiceType) (*AIConfig, error) {
    query := `SELECT provider, base_url, api_key, model
              FROM ai_service_configs
              WHERE service_type = ? AND is_active = 1
              ORDER BY priority DESC
              LIMIT 1`

    row := db.QueryRow(query, string(serviceType))
    var cfg AIConfig
    var modelsJSON string
    if err := row.Scan(&cfg.Provider, &cfg.BaseURL, &cfg.APIKey, &modelsJSON); err != nil {
        if err == sql.ErrNoRows {
            return nil, nil  // 没有活跃配置
        }
        return nil, err
    }

    // model 字段是 JSON 数组，如 ["gpt-4o"]，取第一个
    var models []string
    if modelsJSON != "" {
        json.Unmarshal([]byte(modelsJSON), &models)
    }
    if len(models) > 0 {
        cfg.Model = models[0]
    }
    return &cfg, nil
}

// GetConfigByID 按 ID 查询配置
func GetConfigByID(db *sql.DB, id int64) (*AIConfig, error) {
    // 与 GetActiveConfig 类似，但用 WHERE id = ? AND is_active = 1
}

// GetAudioConfigByID 先尝试按 ID 查询，不存在则回退到默认音频配置
func GetAudioConfigByID(db *sql.DB, id *int64) (*AIConfig, error) {
    if id != nil && *id > 0 {
        cfg, err := GetConfigByID(db, *id)
        if err == nil && cfg != nil {
            return cfg, nil
        }
    }
    return GetActiveConfig(db, ServiceTypeAudio)
}

// GetTextProviderBaseURL 根据 provider 类型拼接正确的 base URL
func GetTextProviderBaseURL(cfg *AIConfig) string {
    provider := strings.ToLower(cfg.Provider)
    switch provider {
    case "openai", "openrouter", "chatfire":
        return adapter.JoinProviderURL(cfg.BaseURL, "/v1", "")
    case "volcengine":
        return adapter.JoinProviderURL(cfg.BaseURL, "/api/v3", "")
    case "ali":
        return adapter.JoinProviderURL(cfg.BaseURL, "/api/v1", "")
    default:
        return cfg.BaseURL
    }
}
```

### 2.3 要点

- `ai_service_configs.model` 字段存储 JSON 数组（如 `["doubao-seedream-3-0-t2i-250415"]`），需要解析取第一个
- `priority` 字段：数值越大优先级越高，与 TS 版排序逻辑一致
- `is_active` 字段在 SQLite 中存为 0/1 integer

---

## 3. 图片生成服务

### 3.1 对应 TS 源码

`backend/src/services/image-generation.ts` + `backend/src/routes/images.ts`

### 3.2 流程图

```
POST /api/v1/images
  │
  ├── 1. 查询 AI 配置（image 类型，或指定 config_id）
  ├── 2. 插入 image_generations 记录 (status=processing)
  ├── 3. 返回 generation ID
  │
  └── [goroutine] processImageGeneration
        ├── 4. 从 DB 读取记录
        ├── 5. 归一化参考图（本地路径 → DataURL）
        ├── 6. 调用 Adapter.BuildGenerateRequest
        ├── 7. 发送 HTTP 请求
        ├── 8. 解析响应
        │     ├── 同步 + URL → 下载图片 → 更新记录 + 关联表
        │     ├── 同步 + base64 → 保存 base64 → 更新记录 + 关联表
        │     └── 异步 → 记录 task_id → pollImageTask
        │
        └── pollImageTask [goroutine + ticker]
              ├── 每 5 秒查询一次
              ├── 最长 10 分钟
              ├── completed → 下载 → 更新
              ├── failed → 标记失败
              └── timeout → 标记失败
```

### 3.3 数据模型

```go
// internal/database/models.go — 新增

type ImageGeneration struct {
    ID               int64   `json:"id"`
    StoryboardID     *int64  `json:"storyboard_id"`
    DramaID          *int64  `json:"drama_id"`
    SceneID          *int64  `json:"scene_id"`
    CharacterID      *int64  `json:"character_id"`
    PropID           *int64  `json:"prop_id"`
    ImageType        *string `json:"image_type"`
    FrameType        *string `json:"frame_type"`  // first_frame / last_frame / 空
    Provider         string  `json:"provider"`
    Prompt           string  `json:"prompt"`
    NegativePrompt   *string `json:"negative_prompt"`
    Model            *string `json:"model"`
    Size             *string `json:"size"`
    Quality          *string `json:"quality"`
    Style            *string `json:"style"`
    Steps            *int    `json:"steps"`
    CfgScale         *float64 `json:"cfg_scale"`
    Seed             *int64  `json:"seed"`
    ImageURL         *string `json:"image_url"`
    MinioURL         *string `json:"minio_url"`
    LocalPath        *string `json:"local_path"`
    Status           string  `json:"status"`
    TaskID           *string `json:"task_id"`
    ErrorMsg         *string `json:"error_msg"`
    Width            *int    `json:"width"`
    Height           *int    `json:"height"`
    ReferenceImages  *string `json:"reference_images"` // JSON 数组
    CreatedAt        string  `json:"created_at"`
    UpdatedAt        string  `json:"updated_at"`
    CompletedAt      *string `json:"completed_at"`
}
```

### 3.4 核心服务

```go
// internal/service/image_gen.go

type ImageGenParams struct {
    StoryboardID    *int64
    DramaID         *int64
    SceneID         *int64
    CharacterID     *int64
    Prompt          string
    Model           string
    Size            string
    ReferenceImages []string
    FrameType       string
    ConfigID        *int64
}

// GenerateImage 提交图片生成任务，返回 generation ID
func GenerateImage(db *sql.DB, params ImageGenParams) (int64, error) {
    // 1. 获取 AI 配置
    var config *AIConfig
    var err error
    if params.ConfigID != nil {
        config, err = GetConfigByID(db, *params.ConfigID)
    } else {
        config, err = GetActiveConfig(db, ServiceTypeImage)
    }
    if config == nil {
        return 0, fmt.Errorf("no active image AI config")
    }

    // 2. 插入 image_generations 记录
    model := params.Model
    if model == "" {
        model = config.Model
    }
    size := params.Size
    if size == "" {
        size = "1920x1080"
    }
    var refImagesJSON *string
    if len(params.ReferenceImages) > 0 {
        b, _ := json.Marshal(params.ReferenceImages)
        s := string(b)
        refImagesJSON = &s
    }

    now := util.Now()
    result, err := db.Exec(
        `INSERT INTO image_generations
         (storyboard_id, drama_id, scene_id, character_id, prompt, model,
          provider, size, frame_type, reference_images, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'processing', ?, ?)`,
        params.StoryboardID, params.DramaID, params.SceneID, params.CharacterID,
        params.Prompt, model, config.Provider, size, params.FrameType,
        refImagesJSON, now, now,
    )
    if err != nil {
        return 0, err
    }
    id, _ := result.LastInsertId()

    // 3. 异步处理
    cfgCopy := *config
    go processImageGeneration(db, id, cfgCopy)

    return id, nil
}

// processImageGeneration 后台处理图片生成
func processImageGeneration(db *sql.DB, id int64, config AIConfig) {
    adp := adapter.GetImageAdapter(config.Provider)

    // 读取记录
    record, err := getImageGenRecord(db, id)
    if err != nil {
        updateImageGenStatus(db, id, "failed", err.Error())
        return
    }

    // 归一化参考图（本地路径 → DataURL）
    refImages, _ := normalizeReferenceImages(record.ReferenceImages)

    // 构建 API 请求
    req, err := adp.BuildGenerateRequest(&config, &adapter.ImageGenRecord{
        ID:               record.ID,
        Model:            record.Model,
        Prompt:           record.Prompt,
        Size:             record.Size,
        FrameType:        record.FrameType,
        ReferenceImages:  refImages,
    })
    if err != nil {
        updateImageGenStatus(db, id, "failed", err.Error())
        return
    }

    // 发送请求（10 分钟超时）
    respBody, err := httpDoRequest(req, 10*time.Minute)
    if err != nil {
        updateImageGenStatus(db, id, "failed", err.Error())
        return
    }

    // 解析响应
    genResp, err := adp.ParseGenerateResponse(respBody)
    if err != nil {
        updateImageGenStatus(db, id, "failed", err.Error())
        return
    }

    if !genResp.IsAsync && genResp.ImageURL != "" {
        // 同步模式 + URL：直接下载
        localPath, err := util.DownloadFile(genResp.ImageURL, "images")
        if err != nil {
            updateImageGenStatus(db, id, "failed", "download failed: "+err.Error())
            return
        }
        handleImageComplete(db, id, genResp.ImageURL, localPath)
        return
    }

    if !genResp.IsAsync && genResp.ImageURL == "" {
        // 同步模式 + base64（Gemini）
        b64, err := adp.ExtractImageBase64(respBody)
        if err != nil {
            updateImageGenStatus(db, id, "failed", "extract base64 failed: "+err.Error())
            return
        }
        localPath, err := util.SaveBase64Image(b64.Data, b64.MimeType, "images")
        if err != nil {
            updateImageGenStatus(db, id, "failed", "save base64 failed: "+err.Error())
            return
        }
        handleImageComplete(db, id, "", localPath)
        return
    }

    // 异步模式：更新 task_id，启动轮询
    updateImageGenTaskID(db, id, genResp.TaskID)
    go pollImageTask(db, id, config, genResp.TaskID)
}

// pollImageTask 异步轮询图片生成任务
func pollImageTask(db *sql.DB, id int64, config AIConfig, taskID string) {
    adp := adapter.GetImageAdapter(config.Provider)
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()
    deadline := time.After(10 * time.Minute)

    for {
        select {
        case <-ticker.C:
            req, err := adp.BuildPollRequest(&config, taskID)
            if err != nil {
                continue
            }
            respBody, err := httpDoRequest(req, 30*time.Second)
            if err != nil {
                continue
            }
            pollResp, err := adp.ParsePollResponse(respBody)
            if err != nil {
                continue
            }

            switch pollResp.Status {
            case "completed":
                if pollResp.ImageURL != "" {
                    localPath, _ := util.DownloadFile(pollResp.ImageURL, "images")
                    handleImageComplete(db, id, pollResp.ImageURL, localPath)
                    return
                }
                // Gemini 可能返回 base64
                b64, _ := adp.ExtractImageBase64(respBody)
                if b64 != nil {
                    localPath, _ := util.SaveBase64Image(b64.Data, b64.MimeType, "images")
                    handleImageComplete(db, id, "", localPath)
                    return
                }
                updateImageGenStatus(db, id, "failed", "completed but no image data")
                return

            case "failed":
                errMsg := pollResp.Error
                if errMsg == "" {
                    errMsg = "generation failed"
                }
                updateImageGenStatus(db, id, "failed", errMsg)
                return
            }

        case <-deadline:
            updateImageGenStatus(db, id, "failed", "polling exceeded 10 minutes")
            return
        }
    }
}

// handleImageComplete 完成图片生成，更新 image_generations + 关联表
func handleImageComplete(db *sql.DB, id int64, imageURL string, localPath string) {
    now := util.Now()
    db.Exec(
        `UPDATE image_generations
         SET image_url = ?, local_path = ?, status = 'completed',
             completed_at = ?, updated_at = ?
         WHERE id = ?`,
        imageURL, localPath, now, now, id,
    )

    // 读取记录以获取关联 ID
    record, _ := getImageGenRecord(db, id)
    if record == nil {
        return
    }

    // 更新 storyboard 关联
    if record.StoryboardID != nil {
        field := "composed_image"
        if record.FrameType != nil {
            switch *record.FrameType {
            case "first_frame":
                field = "first_frame_image"
            case "last_frame":
                field = "last_frame_image"
            }
        }
        db.Exec(fmt.Sprintf(
            `UPDATE storyboards SET %s = ?, updated_at = ? WHERE id = ?`, field,
        ), localPath, now, *record.StoryboardID)
    }

    // 更新 character 关联
    if record.CharacterID != nil {
        db.Exec(
            `UPDATE characters SET image_url = ?, updated_at = ? WHERE id = ?`,
            localPath, now, *record.CharacterID,
        )
    }

    // 更新 scene 关联
    if record.SceneID != nil {
        db.Exec(
            `UPDATE scenes SET image_url = ?, status = 'completed', updated_at = ? WHERE id = ?`,
            localPath, now, *record.SceneID,
        )
    }
}
```

### 3.5 参考图归一化

```go
// normalizeReferenceImages 将本地路径转为 DataURL，远程 URL 保持不变
func normalizeReferenceImages(refImagesJSON *string) ([]string, error) {
    if refImagesJSON == nil {
        return nil, nil
    }
    var refs []string
    if err := json.Unmarshal([]byte(*refImagesJSON), &refs); err != nil {
        return nil, err
    }

    // 去重
    seen := make(map[string]bool)
    var deduped []string
    for _, r := range refs {
        r = strings.TrimSpace(r)
        if r == "" || seen[r] {
            continue
        }
        seen[r] = true
        deduped = append(deduped, r)
    }

    var results []string
    for _, value := range deduped {
        if len(results) >= 6 {
            break  // 最多 6 张参考图
        }
        if strings.HasPrefix(value, "data:image/") {
            results = append(results, value)
            continue
        }
        if strings.HasPrefix(value, "static/") || strings.HasPrefix(value, "/static/") {
            localPath := value
            if strings.HasPrefix(value, "/static/") {
                localPath = value[1:]
            }
            dataURL, err := util.ReadImageAsCompressedDataURL(localPath, 768, 768, 68)
            if err != nil {
                continue
            }
            results = append(results, dataURL)
            continue
        }
        // 远程 URL
        results = append(results, value)
    }
    return results, nil
}
```

### 3.6 HTTP 路由

```go
// internal/handler/image.go

func (h *Handler) CreateImage(c *gin.Context) {
    var req struct {
        Prompt          string   `json:"prompt" binding:"required"`
        StoryboardID    *int64   `json:"storyboard_id"`
        DramaID         *int64   `json:"drama_id"`
        SceneID         *int64   `json:"scene_id"`
        CharacterID     *int64   `json:"character_id"`
        Model           string   `json:"model"`
        Size            string   `json:"size"`
        ReferenceImages []string `json:"reference_images"`
        FrameType       string   `json:"frame_type"`
        ConfigID        *int64   `json:"config_id"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        util.BadRequest(c, "prompt is required")
        return
    }

    // 如果有 storyboard_id，自动解析 config_id
    if req.StoryboardID != nil && (req.ConfigID == nil || *req.ConfigID == 0) {
        ep := getEpisodeByStoryboardID(h.DB, *req.StoryboardID)
        if ep != nil && ep.ImageConfigID != nil {
            req.ConfigID = ep.ImageConfigID
        }
    }

    params := service.ImageGenParams{
        StoryboardID:    req.StoryboardID,
        DramaID:         req.DramaID,
        SceneID:         req.SceneID,
        CharacterID:     req.CharacterID,
        Prompt:          req.Prompt,
        Model:           req.Model,
        Size:            req.Size,
        ReferenceImages: req.ReferenceImages,
        FrameType:       req.FrameType,
        ConfigID:        req.ConfigID,
    }

    id, err := service.GenerateImage(h.DB, params)
    if err != nil {
        util.BadRequest(c, err.Error())
        return
    }
    util.Success(c, gin.H{"id": id, "status": "processing"})
}

func (h *Handler) GetImage(c *gin.Context) {
    id := util.ParseInt64Param(c, "id")
    record, err := getImageGenRecord(h.DB, id)
    if err != nil {
        util.NotFound(c, "image generation not found")
        return
    }
    util.Success(c, util.ToSnakeCaseMap(record))
}

func (h *Handler) ListImages(c *gin.Context) {
    storyID := c.Query("storyboard_id")
    dramaID := c.Query("drama_id")
    records := listImageGenRecords(h.DB, storyID, dramaID)
    util.Success(c, util.ToSnakeCaseArray(records))
}

func (h *Handler) DeleteImage(c *gin.Context) {
    id := util.ParseInt64Param(c, "id")
    h.DB.Exec("DELETE FROM image_generations WHERE id = ?", id)
    util.Success(c, nil)
}
```

---

## 4. 视频生成服务

### 4.1 对应 TS 源码

`backend/src/services/video-generation.ts` + `backend/src/routes/videos.ts`

### 4.2 流程图

```
POST /api/v1/videos
  │
  ├── 1. 查询 AI 配置（video 类型，或指定 config_id）
  ├── 2. 插入 video_generations 记录 (status=processing)
  ├── 3. 返回 generation ID
  │
  └── [goroutine] processVideoGeneration
        ├── 4. 归一化参考图 URL（本地路径 → DataURL）
        ├── 5. 调用 Adapter.BuildGenerateRequest
        ├── 6. 发送 HTTP 请求
        ├── 7. 解析响应
        │     ├── 同步 + URL → 下载 → 更新 storyboard
        │     └── 异步 → 记录 task_id
        │           ├── Vidu → 不轮询，等 Webhook
        │           └── 其他 → pollVideoTask
        │
        └── pollVideoTask [goroutine + ticker 10s]
              ├── 每 10 秒查询一次
              ├── 最长 50 分钟 (300 次 × 10s)
              ├── completed → 下载 → 更新 storyboard
              ├── failed → 标记失败
              └── timeout → 标记失败
```

### 4.3 数据模型

```go
// internal/database/models.go — 新增

type VideoGeneration struct {
    ID                 int64   `json:"id"`
    StoryboardID       *int64  `json:"storyboard_id"`
    DramaID            *int64  `json:"drama_id"`
    Provider           string  `json:"provider"`
    Prompt             string  `json:"prompt"`
    Model              *string `json:"model"`
    ImageGenID         *int64  `json:"image_gen_id"`
    ReferenceMode      *string `json:"reference_mode"`  // none/single/first_last/multiple
    ImageURL           *string `json:"image_url"`
    FirstFrameURL      *string `json:"first_frame_url"`
    LastFrameURL       *string `json:"last_frame_url"`
    ReferenceImageURLs *string `json:"reference_image_urls"` // JSON 数组
    Duration           *int    `json:"duration"`
    FPS                *int    `json:"fps"`
    Resolution         *string `json:"resolution"`
    AspectRatio        *string `json:"aspect_ratio"`
    Style              *string `json:"style"`
    MotionLevel        *int    `json:"motion_level"`
    CameraMotion       *string `json:"camera_motion"`
    Seed               *int64  `json:"seed"`
    VideoURL           *string `json:"video_url"`
    MinioURL           *string `json:"minio_url"`
    LocalPath          *string `json:"local_path"`
    Status             string  `json:"status"`
    TaskID             *string `json:"task_id"`
    ErrorMsg           *string `json:"error_msg"`
    Width              *int    `json:"width"`
    Height             *int    `json:"height"`
    CreatedAt          string  `json:"created_at"`
    UpdatedAt          string  `json:"updated_at"`
    CompletedAt        *string `json:"completed_at"`
    DeletedAt          *string `json:"deleted_at"`
}
```

### 4.4 核心服务

```go
// internal/service/video_gen.go

type VideoGenParams struct {
    StoryboardID       *int64
    DramaID            *int64
    Prompt             string
    Model              string
    ReferenceMode      string   // none / single / first_last / multiple
    ImageURL           string
    FirstFrameURL      string
    LastFrameURL       string
    ReferenceImageURLs []string
    Duration           int
    AspectRatio        string
    ConfigID           *int64
}

// GenerateVideo 提交视频生成任务
func GenerateVideo(db *sql.DB, params VideoGenParams) (int64, error) {
    // 获取配置
    var config *AIConfig
    var err error
    if params.ConfigID != nil {
        config, err = GetConfigByID(db, *params.ConfigID)
    } else {
        config, err = GetActiveConfig(db, ServiceTypeVideo)
    }
    if config == nil {
        return 0, fmt.Errorf("no active video AI config")
    }

    // 默认值
    model := params.Model
    if model == "" {
        model = config.Model
    }
    refMode := params.ReferenceMode
    if refMode == "" {
        refMode = "none"
    }
    duration := params.Duration
    if duration == 0 {
        duration = 5
    }
    aspectRatio := params.AspectRatio
    if aspectRatio == "" {
        aspectRatio = "16:9"
    }
    var refURLsJSON *string
    if len(params.ReferenceImageURLs) > 0 {
        b, _ := json.Marshal(params.ReferenceImageURLs)
        s := string(b)
        refURLsJSON = &s
    }

    now := util.Now()
    result, err := db.Exec(
        `INSERT INTO video_generations
         (storyboard_id, drama_id, prompt, model, provider, reference_mode,
          image_url, first_frame_url, last_frame_url, reference_image_urls,
          duration, aspect_ratio, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'processing', ?, ?)`,
        params.StoryboardID, params.DramaID, params.Prompt, model, config.Provider,
        refMode, params.ImageURL, params.FirstFrameURL, params.LastFrameURL,
        refURLsJSON, duration, aspectRatio, now, now,
    )
    if err != nil {
        return 0, err
    }
    id, _ := result.LastInsertId()

    cfgCopy := *config
    go processVideoGeneration(db, id, cfgCopy)

    return id, nil
}

// processVideoGeneration 后台处理视频生成
func processVideoGeneration(db *sql.DB, id int64, config AIConfig) {
    adp := adapter.GetVideoAdapter(config.Provider)

    record, err := getVideoGenRecord(db, id)
    if err != nil {
        updateVideoGenStatus(db, id, "failed", err.Error())
        return
    }

    // 归一化参考图 URL
    resolvedImageURL, _ := normalizeVideoReferenceURL(record.ImageURL)
    resolvedFirstFrame, _ := normalizeVideoReferenceURL(record.FirstFrameURL)
    resolvedLastFrame, _ := normalizeVideoReferenceURL(record.LastFrameURL)
    resolvedRefURLs, _ := normalizeVideoReferenceURLs(record.ReferenceImageURLs)

    // 构建 API 请求
    req, err := adp.BuildGenerateRequest(&config, &adapter.VideoGenRecord{
        ID:                record.ID,
        Model:             record.Model,
        Prompt:            record.Prompt,
        ReferenceMode:     record.ReferenceMode,
        ImageURL:          resolvedImageURL,
        FirstFrameURL:     resolvedFirstFrame,
        LastFrameURL:      resolvedLastFrame,
        ReferenceImageURLs: refStringsToJSON(resolvedRefURLs),
        Duration:          record.Duration,
        AspectRatio:       record.AspectRatio,
    })
    if err != nil {
        updateVideoGenStatus(db, id, "failed", err.Error())
        return
    }

    respBody, err := httpDoRequest(req, 10*time.Minute)
    if err != nil {
        updateVideoGenStatus(db, id, "failed", err.Error())
        return
    }

    genResp, err := adp.ParseGenerateResponse(respBody)
    if err != nil {
        updateVideoGenStatus(db, id, "failed", err.Error())
        return
    }

    if !genResp.IsAsync && genResp.VideoURL != "" {
        // 同步完成
        handleVideoComplete(db, id, genResp.VideoURL, nil, record.StoryboardID)
        return
    }

    // 异步：更新 task_id
    now := util.Now()
    db.Exec(
        `UPDATE video_generations SET task_id = ?, status = 'processing', updated_at = ? WHERE id = ?`,
        genResp.TaskID, now, id,
    )

    // Vidu 不轮询，等 Webhook
    if config.Provider == "vidu" {
        return
    }

    // 其他 Provider 启动轮询
    go pollVideoTask(db, id, config, genResp.TaskID, record.StoryboardID)
}

// pollVideoTask 异步轮询视频生成任务
func pollVideoTask(db *sql.DB, id int64, config AIConfig, taskID string, storyboardID *int64) {
    adp := adapter.GetVideoAdapter(config.Provider)
    ticker := time.NewTicker(10 * time.Second)
    defer ticker.Stop()

    for i := 0; i < 300; i++ { // 最多 300 次 × 10s = 50 分钟
        <-ticker.C

        req, err := adp.BuildPollRequest(&config, taskID)
        if err != nil {
            continue
        }

        respBody, err := httpDoRequest(req, 30*time.Second)
        if err != nil {
            continue
        }

        pollResp, err := adp.ParsePollResponse(respBody)
        if err != nil {
            continue
        }

        switch pollResp.Status {
        case "completed":
            if pollResp.VideoURL != "" {
                handleVideoComplete(db, id, pollResp.VideoURL, nil, storyboardID)
                return
            }
        case "failed":
            errMsg := pollResp.Error
            if errMsg == "" {
                errMsg = "video generation failed"
            }
            updateVideoGenStatus(db, id, "failed", errMsg)
            return
        }
    }

    updateVideoGenStatus(db, id, "failed", "polling timeout")
}

// handleVideoComplete 下载视频并更新数据库
func handleVideoComplete(db *sql.DB, id int64, videoURL string, duration *int, storyboardID *int64) {
    localPath, err := util.DownloadFile(videoURL, "videos")
    if err != nil {
        updateVideoGenStatus(db, id, "failed", "download failed: "+err.Error())
        return
    }

    now := util.Now()
    db.Exec(
        `UPDATE video_generations
         SET video_url = ?, local_path = ?, status = 'completed',
             completed_at = ?, updated_at = ?
         WHERE id = ?`,
        videoURL, localPath, now, now, id,
    )

    // 更新关联的 storyboard
    if storyboardID != nil {
        updateFields := map[string]interface{}{
            "video_url":   localPath,
            "updated_at":  now,
        }
        if duration != nil {
            updateFields["duration"] = *duration
        }
        // 动态构建 UPDATE
        squirrel.Update("storyboards").
            SetMap(updateFields).
            Where(squirrel.Eq{"id": *storyboardID}).
            RunWith(db).Exec()
    }
}

// normalizeVideoReferenceURL 将本地路径转为 DataURL，远程 URL 保持不变
func normalizeVideoReferenceURL(value *string) (*string, error) {
    if value == nil {
        return nil, nil
    }
    raw := strings.TrimSpace(*value)
    if raw == "" {
        return nil, nil
    }
    if strings.HasPrefix(raw, "data:image/") {
        return &raw, nil
    }
    if strings.HasPrefix(raw, "static/") || strings.HasPrefix(raw, "/static/") {
        localPath := raw
        if strings.HasPrefix(raw, "/static/") {
            localPath = raw[1:]
        }
        dataURL, err := util.ReadImageAsCompressedDataURL(localPath, 768, 768, 68)
        if err != nil {
            return nil, nil // 静默忽略
        }
        return &dataURL, nil
    }
    return &raw, nil
}

// normalizeVideoReferenceURLs 批量归一化参考图 URL
func normalizeVideoReferenceURLs(jsonStr *string) ([]string, error) {
    if jsonStr == nil {
        return nil, nil
    }
    var refs []string
    json.Unmarshal([]byte(*jsonStr), &refs)

    seen := make(map[string]bool)
    var results []string
    for _, r := range refs {
        r = strings.TrimSpace(r)
        if r == "" || seen[r] {
            continue
        }
        seen[r] = true
        normalized, err := normalizeVideoReferenceURL(&r)
        if err == nil && normalized != nil {
            results = append(results, *normalized)
        }
    }
    return results, nil
}
```

### 4.5 HTTP 路由

```go
// internal/handler/video.go

func (h *Handler) CreateVideo(c *gin.Context) {
    var req struct {
        Prompt             string   `json:"prompt" binding:"required"`
        StoryboardID       *int64   `json:"storyboard_id"`
        DramaID            *int64   `json:"drama_id"`
        Model              string   `json:"model"`
        ReferenceMode      string   `json:"reference_mode"`
        ImageURL           string   `json:"image_url"`
        FirstFrameURL      string   `json:"first_frame_url"`
        LastFrameURL       string   `json:"last_frame_url"`
        ReferenceImageURLs []string `json:"reference_image_urls"`
        Duration           int      `json:"duration"`
        AspectRatio        string   `json:"aspect_ratio"`
        ConfigID           *int64   `json:"config_id"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        util.BadRequest(c, "prompt is required")
        return
    }

    // 自动解析 config_id
    if req.StoryboardID != nil && (req.ConfigID == nil || *req.ConfigID == 0) {
        ep := getEpisodeByStoryboardID(h.DB, *req.StoryboardID)
        if ep != nil && ep.VideoConfigID != nil {
            req.ConfigID = ep.VideoConfigID
        }
    }

    params := service.VideoGenParams{
        StoryboardID:       req.StoryboardID,
        DramaID:            req.DramaID,
        Prompt:             req.Prompt,
        Model:              req.Model,
        ReferenceMode:      req.ReferenceMode,
        ImageURL:           req.ImageURL,
        FirstFrameURL:      req.FirstFrameURL,
        LastFrameURL:       req.LastFrameURL,
        ReferenceImageURLs: req.ReferenceImageURLs,
        Duration:           req.Duration,
        AspectRatio:        req.AspectRatio,
        ConfigID:           req.ConfigID,
    }

    id, err := service.GenerateVideo(h.DB, params)
    if err != nil {
        util.BadRequest(c, err.Error())
        return
    }
    util.Success(c, gin.H{"id": id, "status": "processing"})
}

func (h *Handler) GetVideo(c *gin.Context) {
    id := util.ParseInt64Param(c, "id")
    record, err := getVideoGenRecord(h.DB, id)
    if err != nil {
        util.NotFound(c, "video generation not found")
        return
    }
    util.Success(c, util.ToSnakeCaseMap(record))
}

func (h *Handler) ListVideos(c *gin.Context) {
    storyID := c.Query("storyboard_id")
    dramaID := c.Query("drama_id")
    records := listVideoGenRecords(h.DB, storyID, dramaID)
    util.Success(c, util.ToSnakeCaseArray(records))
}

func (h *Handler) DeleteVideo(c *gin.Context) {
    id := util.ParseInt64Param(c, "id")
    h.DB.Exec("DELETE FROM video_generations WHERE id = ?", id)
    util.Success(c, nil)
}
```

---

## 5. Vidu Webhook 回调

### 5.1 对应 TS 源码

`backend/src/routes/webhooks.ts`

### 5.2 流程

```
POST /webhooks/vidu
  │
  ├── 解析 body: { task_id, state, video_url, error }
  ├── 按 task_id 查找 video_generations 记录
  │
  ├── state == "success" && video_url
  │     ├── 下载视频到本地
  │     ├── 更新 video_generations: status=completed
  │     └── 更新关联 storyboard: video_url
  │
  ├── state == "failed"
  │     └── 更新 video_generations: status=failed
  │
  └── 其他状态 → 返回 "status noted"
```

### 5.3 实现

```go
// internal/handler/webhook.go

func (h *Handler) ViduCallback(c *gin.Context) {
    var body struct {
        TaskID   string `json:"task_id"`
        State    string `json:"state"`
        VideoURL string `json:"video_url"`
        Error    string `json:"error"`
    }
    if err := c.ShouldBindJSON(&body); err != nil {
        util.BadRequest(c, "invalid body")
        return
    }

    if body.TaskID == "" {
        util.BadRequest(c, "Missing task_id")
        return
    }

    // 查找 video_generation 记录
    var recordID int64
    var storyboardID *int64
    err := h.DB.QueryRow(
        `SELECT id, storyboard_id FROM video_generations WHERE task_id = ?`,
        body.TaskID,
    ).Scan(&recordID, &storyboardID)
    if err != nil {
        // 记录可能还没写入，返回成功避免重复回调
        util.Success(c, gin.H{"message": "task not found"})
        return
    }

    if body.State == "success" && body.VideoURL != "" {
        localPath, err := util.DownloadFile(body.VideoURL, "videos")
        if err != nil {
            // 下载失败
            h.DB.Exec(
                `UPDATE video_generations SET status = 'failed', error_msg = ? WHERE id = ?`,
                "webhook download failed: "+err.Error(), recordID,
            )
            util.BadRequest(c, err.Error())
            return
        }

        now := util.Now()
        h.DB.Exec(
            `UPDATE video_generations
             SET video_url = ?, local_path = ?, status = 'completed',
                 updated_at = ?, completed_at = ?
             WHERE id = ?`,
            body.VideoURL, localPath, now, now, recordID,
        )

        // 更新 storyboard
        if storyboardID != nil {
            h.DB.Exec(
                `UPDATE storyboards SET video_url = ?, updated_at = ? WHERE id = ?`,
                localPath, now, *storyboardID,
            )
        }

        util.Success(c, gin.H{"message": "video updated successfully"})
        return
    }

    if body.State == "failed" {
        errMsg := body.Error
        if errMsg == "" {
            errMsg = "Vidu generation failed"
        }
        h.DB.Exec(
            `UPDATE video_generations SET status = 'failed', error_msg = ? WHERE id = ?`,
            errMsg, recordID,
        )
        util.Success(c, gin.H{"message": "error recorded"})
        return
    }

    // 其他状态（processing 等）
    util.Success(c, gin.H{"message": "status noted"})
}
```

---

## 6. TTS 语音合成

### 6.1 对应 TS 源码

`backend/src/services/tts-generation.ts` + `backend/src/routes/storyboards.ts`（generate-tts 部分）

### 6.2 流程

```
generateTTS(text, voice, configID?)
  │
  ├── 1. 查询音频 AI 配置
  ├── 2. 获取 TTS Adapter
  ├── 3. Adapter.BuildGenerateRequest 构建请求
  ├── 4. 发送 HTTP 请求
  ├── 5. 解析响应 → 提取 audioHex
  ├── 6. hex 解码为二进制
  ├── 7. 保存到 data/static/audio/{uuid}.{format}
  └── 8. 返回相对路径 "static/audio/xxx.mp3"
```

### 6.3 核心服务

```go
// internal/service/tts_gen.go

type TTSParams struct {
    Text     string
    Voice    string
    Model    string
    Speed    float64
    Emotion  string
    ConfigID *int64
}

type TTSResult struct {
    LocalPath string  // 相对路径，如 "static/audio/xxx.mp3"
    Bytes     int
    AudioMs   int
}

// GenerateTTS 生成 TTS 音频，返回本地文件相对路径
func GenerateTTS(db *sql.DB, params TTSParams) (*TTSResult, error) {
    config, err := GetAudioConfigByID(db, params.ConfigID)
    if err != nil || config == nil {
        return nil, fmt.Errorf("no active audio AI config")
    }

    adp := adapter.GetTTSAdapter(config.Provider)

    // 构建 API 请求
    req, err := adp.BuildGenerateRequest(config, map[string]interface{}{
        "text":    params.Text,
        "voice":   params.Voice,
        "model":   params.Model,
        "speed":   params.Speed,
        "emotion": params.Emotion,
    })
    if err != nil {
        return nil, err
    }

    // 发送请求
    respBody, err := httpDoRequest(req, 60*time.Second)
    if err != nil {
        return nil, fmt.Errorf("TTS API error: %w", err)
    }

    // 解析响应
    ttsResp, err := adp.ParseResponse(respBody)
    if err != nil {
        return nil, fmt.Errorf("TTS parse error: %w", err)
    }

    // hex 解码为二进制
    audioBytes, err := hex.DecodeString(ttsResp.AudioHex)
    if err != nil {
        return nil, fmt.Errorf("hex decode error: %w", err)
    }

    // 保存文件
    ext := ttsResp.Format
    if ext == "" {
        ext = "mp3"
    }
    filename := uuid.New().String() + "." + ext
    localPath := filepath.Join("static", "audio", filename)

    fullPath := util.GetAbsolutePath(localPath)
    os.MkdirAll(filepath.Dir(fullPath), 0755)
    if err := os.WriteFile(fullPath, audioBytes, 0644); err != nil {
        return nil, err
    }

    return &TTSResult{
        LocalPath: localPath,
        Bytes:     len(audioBytes),
        AudioMs:   ttsResp.AudioLength,
    }, nil
}

// GenerateVoiceSample 为角色生成试听音频
func GenerateVoiceSample(db *sql.DB, characterName string, voiceID string, configID *int64) (string, error) {
    sampleText := fmt.Sprintf("你好，我是%s。很高兴认识你，这是我的声音试听。", characterName)
    result, err := GenerateTTS(db, TTSParams{
        Text:     sampleText,
        Voice:    voiceID,
        ConfigID: configID,
    })
    if err != nil {
        return "", err
    }
    return result.LocalPath, nil
}
```

### 6.4 分镜 TTS 生成路由

```go
// internal/handler/storyboard.go — GenerateTTS 方法

// 对白解析辅助函数
var (
    ignoreTTSSpeakers = regexp.MustCompile(`(?i)^(环境音|环境声|音效|效果音|sfx|sound ?effect|bgm|背景音|背景音乐|ambient)$`)
    ignoreTTSText     = regexp.MustCompile(`(?i)^(无|无对白|无台词|无旁白|无需配音|无需对白|none|null|n/a|na|环境音|环境声|音效|效果音|纯音效|纯环境音|只有环境音|仅环境音|背景音|背景音乐|bgm|sfx|ambient)$`)
)

type DialogueParts struct {
    Speaker   string
    PureText  string
    Ignorable bool
}

func parseDialogueForTTS(dialogue string) DialogueParts {
    dialogue = strings.TrimSpace(dialogue)
    if dialogue == "" {
        return DialogueParts{Ignorable: true}
    }

    // 提取说话人：xxx: 或 xxx：
    speaker := ""
    speakerRe := regexp.MustCompile(`^(.+?)[:：]`)
    if matches := speakerRe.FindStringSubmatch(dialogue); len(matches) > 1 {
        speaker = strings.TrimSpace(
            regexp.MustCompile(`[（(].+?[)）]`).ReplaceAllString(matches[1], ""),
        )
    }

    // 提取纯文本
    pureText := regexp.MustCompile(`^.+?[:：]\s*`).ReplaceAllString(dialogue, "")
    pureText = strings.TrimSpace(
        regexp.MustCompile(`[（(].+?[)）]`).ReplaceAllString(pureText, ""),
    )

    ignorable := false
    if speaker != "" && ignoreTTSSpeakers.MatchString(speaker) {
        ignorable = true
    }
    if pureText == "" || ignoreTTSText.MatchString(pureText) {
        ignorable = true
    }

    return DialogueParts{
        Speaker:   speaker,
        PureText:  pureText,
        Ignorable: ignorable,
    }
}

func (h *Handler) GenerateStoryboardTTS(c *gin.Context) {
    id := util.ParseInt64Param(c, "id")

    sb, err := getStoryboard(h.DB, id)
    if err != nil {
        util.NotFound(c, "storyboard not found")
        return
    }

    parsed := parseDialogueForTTS(sb.Dialogue)
    if parsed.Ignorable {
        util.Success(c, gin.H{"message": "no dialogue to generate"})
        return
    }

    // 查找角色对应的 voice
    voice := "alloy" // 默认
    ep, _ := getEpisode(h.DB, sb.EpisodeID)
    if ep != nil && parsed.Speaker != "" {
        chars, _ := listCharactersByDrama(h.DB, ep.DramaID)
        for _, ch := range chars {
            if ch.Name == parsed.Speaker && ch.VoiceStyle != nil {
                voice = *ch.VoiceStyle
                break
            }
        }
    }

    var configID *int64
    if ep != nil {
        configID = ep.AudioConfigID
    }

    result, err := service.GenerateTTS(h.DB, service.TTSParams{
        Text:     parsed.PureText,
        Voice:    voice,
        ConfigID: configID,
    })
    if err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    // 更新 storyboard 的 tts_audio_url
    now := util.Now()
    h.DB.Exec(
        `UPDATE storyboards SET tts_audio_url = ?, updated_at = ? WHERE id = ?`,
        result.LocalPath, now, id,
    )

    util.Success(c, gin.H{
        "tts_audio_url": result.LocalPath,
        "bytes":         result.Bytes,
    })
}
```

---

## 7. 文件上传

### 7.1 对应 TS 源码

`backend/src/routes/upload.ts`

### 7.2 实现

```go
// internal/handler/upload.go

func (h *Handler) UploadImage(c *gin.Context) {
    file, err := c.FormFile("file")
    if err != nil {
        util.BadRequest(c, "file is required")
        return
    }

    // 保存到 data/static/uploads/
    ext := filepath.Ext(file.Filename)
    if ext == "" {
        ext = ".png"
    }
    filename := uuid.New().String() + ext
    relativePath := filepath.Join("static", "uploads", filename)
    fullPath := util.GetAbsolutePath(relativePath)

    os.MkdirAll(filepath.Dir(fullPath), 0755)

    if err := c.SaveUploadedFile(file, fullPath); err != nil {
        util.BadRequest(c, "save failed: "+err.Error())
        return
    }

    util.Success(c, gin.H{
        "url":        "/" + relativePath,
        "local_path": relativePath,
    })
}
```

---

## 8. 音色管理

### 8.1 对应 TS 源码

`backend/src/routes/aiVoices.ts`

### 8.2 数据模型

```go
// internal/database/models.go — 新增

type AIVoice struct {
    ID          int64  `json:"id"`
    VoiceID     string `json:"voice_id"`
    VoiceName   string `json:"voice_name"`
    Description string `json:"description"` // JSON 数组字符串
    Language    string `json:"language"`
    Provider    string `json:"provider"`
    CreatedAt   string `json:"created_at"`
}
```

### 8.3 路由

```go
// internal/handler/ai_voice.go

// GET /api/v1/ai-voices
func (h *Handler) ListVoices(c *gin.Context) {
    provider := c.DefaultQuery("provider", "minimax")

    rows, err := h.DB.Query(
        `SELECT id, voice_id, voice_name, description, language, provider, created_at
         FROM ai_voices WHERE provider = ?`, provider,
    )
    if err != nil {
        util.Success(c, []interface{}{})
        return
    }
    defer rows.Close()

    var voices []map[string]interface{}
    for rows.Next() {
        var v database.AIVoice
        rows.Scan(&v.ID, &v.VoiceID, &v.VoiceName, &v.Description, &v.Language, &v.Provider, &v.CreatedAt)

        // 解析 description JSON
        var desc []string
        if v.Description != "" {
            json.Unmarshal([]byte(v.Description), &desc)
        }

        voices = append(voices, map[string]interface{}{
            "id":          v.ID,
            "voice_id":    v.VoiceID,
            "voice_name":  v.VoiceName,
            "description": desc,
            "language":    v.Language,
            "provider":    v.Provider,
            "created_at":  v.CreatedAt,
        })
    }
    util.Success(c, voices)
}

// POST /api/v1/ai-voices/sync
func (h *Handler) SyncVoices(c *gin.Context) {
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

    // 3. 过滤：只保留中文和粤语，排除特定模式
    // TS 版排除模式: beta, cartoon, 等
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
        // 检查语言是否包含中文或粤语
        hasChinese := false
        var langStr string
        for _, lang := range v.Language {
            langStr += lang + ","
            if strings.Contains(strings.ToLower(lang), "zh") ||
               strings.Contains(strings.ToLower(lang), "cantonese") ||
               strings.Contains(strings.ToLower(lang), "chinese") {
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
            Language:    strings.TrimSuffix(langStr, ","),
        })
    }

    // 4. 清除旧记录并批量插入
    tx, _ := h.DB.Begin()
    tx.Exec("DELETE FROM ai_voices WHERE provider = ?", config.Provider)
    now := util.Now()
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

## 9. 文件存储工具

### 9.1 对应 TS 源码

`backend/src/utils/storage.ts`

### 9.2 Go 实现

```go
// internal/util/storage.go

var storageRoot string  // 初始化时设置，默认 ../../data

func InitStorage(root string) {
    storageRoot = root
}

// GetAbsolutePath 将相对路径转为绝对路径
// "static/images/xxx.png" → "/project/data/static/images/xxx.png"
func GetAbsolutePath(relativePath string) string {
    if filepath.IsAbs(relativePath) {
        return relativePath
    }
    return filepath.Join(storageRoot, relativePath)
}

// DownloadFile 下载远程文件到本地 data/static/{subDir}/
// 返回相对路径 "static/{subDir}/{filename}"
func DownloadFile(url string, subDir string) (string, error) {
    resp, err := http.Get(url)
    if err != nil {
        return "", err
    }
    defer resp.Body.Close()

    if resp.StatusCode != 200 {
        return "", fmt.Errorf("download failed: HTTP %d", resp.StatusCode)
    }

    // 从 URL 或 Content-Type 推断扩展名
    ext := extractExtFromURL(url)
    if ext == "" {
        ext = ".bin"
    }

    filename := uuid.New().String() + ext
    relativePath := filepath.Join("static", subDir, filename)
    fullPath := GetAbsolutePath(relativePath)

    os.MkdirAll(filepath.Dir(fullPath), 0755)

    f, err := os.Create(fullPath)
    if err != nil {
        return "", err
    }
    defer f.Close()

    if _, err := io.Copy(f, resp.Body); err != nil {
        os.Remove(fullPath)
        return "", err
    }

    return relativePath, nil
}

// SaveBase64Image 将 base64 图片数据保存到本地
func SaveBase64Image(base64Data string, mimeType string, subDir string) (string, error) {
    data, err := base64.StdEncoding.DecodeString(base64Data)
    if err != nil {
        return "", err
    }

    ext := mimeToExt(mimeType)
    filename := uuid.New().String() + ext
    relativePath := filepath.Join("static", subDir, filename)
    fullPath := GetAbsolutePath(relativePath)

    os.MkdirAll(filepath.Dir(fullPath), 0755)
    if err := os.WriteFile(fullPath, data, 0644); err != nil {
        return "", err
    }

    return relativePath, nil
}

// ReadImageAsCompressedDataURL 读取本地图片，压缩后转为 data URL
// 替代 TS 版 sharp 的 readImageAsCompressedDataUrl
func ReadImageAsCompressedDataURL(relativePath string, maxWidth, maxHeight, quality int) (string, error) {
    fullPath := GetAbsolutePath(relativePath)

    // 读取图片
    img, err := imaging.Open(fullPath)
    if err != nil {
        return "", err
    }

    // 缩放
    bounds := img.Bounds()
    w, h := bounds.Dx(), bounds.Dy()
    if w > maxWidth || h > maxHeight {
        img = imaging.Fit(img, maxWidth, maxHeight, imaging.Lanczos)
    }

    // 编码为 JPEG
    var buf bytes.Buffer
    imaging.Encode(&buf, img, imaging.JPEG)
    compressed := buf.Bytes()

    // 转为 data URL
    b64 := base64.StdEncoding.EncodeToString(compressed)
    return fmt.Sprintf("data:image/jpeg;base64,%s", b64), nil
}

// ParseDataURL 解析 data:mime;base64,xxx 格式
func ParseDataURL(dataURL string) (mimeType string, data string, err error) {
    if !strings.HasPrefix(dataURL, "data:") {
        return "", "", fmt.Errorf("not a data URL")
    }
    parts := strings.SplitN(dataURL[5:], ",", 2)
    if len(parts) != 2 {
        return "", "", fmt.Errorf("invalid data URL format")
    }
    meta := parts[0]
    data = parts[1]

    if strings.HasPrefix(meta, "image/") {
        mimeType = strings.SplitN(meta, ";", 2)[0]
    }
    return mimeType, data, nil
}

// extractExtFromURL 从 URL 提取文件扩展名
func extractExtFromURL(rawURL string) string {
    u, err := url.Parse(rawURL)
    if err != nil {
        return ""
    }
    ext := filepath.Ext(u.Path)
    if ext != "" {
        return ext
    }
    return ".bin"
}

// mimeToExt MIME 类型转扩展名
func mimeToExt(mime string) string {
    switch mime {
    case "image/png":
        return ".png"
    case "image/jpeg", "image/jpg":
        return ".jpg"
    case "image/webp":
        return ".webp"
    case "image/gif":
        return ".gif"
    default:
        return ".bin"
    }
}
```

---

## 10. 通用 HTTP 请求工具

```go
// internal/util/http.go

// HTTPResponse 封装 HTTP 响应
type HTTPResponse struct {
    StatusCode int
    Body       []byte
}

// httpDoRequest 执行 HTTP 请求（带超时）
func httpDoRequest(req *adapter.ProviderRequest, timeout time.Duration) ([]byte, error) {
    ctx, cancel := context.WithTimeout(context.Background(), timeout)
    defer cancel()

    var body io.Reader
    if req.Body != nil {
        bodyBytes, _ := json.Marshal(req.Body)
        body = bytes.NewReader(bodyBytes)
    }

    httpReq, err := http.NewRequestWithContext(ctx, req.Method, req.URL, body)
    if err != nil {
        return nil, err
    }

    for k, v := range req.Headers {
        httpReq.Header.Set(k, v)
    }

    resp, err := http.DefaultClient.Do(httpReq)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    respBody, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, err
    }

    if resp.StatusCode >= 400 {
        return nil, fmt.Errorf("API error %d: %s", resp.StatusCode, string(respBody))
    }

    return respBody, nil
}
```

---

## 11. 路由注册汇总

Phase 3 涉及的路由注册代码：

```go
// cmd/server/main.go — Phase 3 路由

// Images
v1.POST("/images", h.CreateImage)
v1.GET("/images", h.ListImages)
v1.GET("/images/:id", h.GetImage)
v1.DELETE("/images/:id", h.DeleteImage)

// Videos
v1.POST("/videos", h.CreateVideo)
v1.GET("/videos", h.ListVideos)
v1.GET("/videos/:id", h.GetVideo)
v1.DELETE("/videos/:id", h.DeleteVideo)

// Upload
v1.POST("/upload/image", h.UploadImage)

// Storyboard TTS (补充到 Phase 1 的 storyboard 路由组)
v1.POST("/storyboards/:id/generate-tts", h.GenerateStoryboardTTS)

// AI Voices
v1.GET("/ai-voices", h.ListVoices)
v1.POST("/ai-voices/sync", h.SyncVoices)

// Webhooks (不在 /api/v1 下)
r.POST("/webhooks/vidu", h.ViduCallback)
```

---

## 12. 依赖关系

Phase 3 依赖：

- **Phase 1**：数据库模型（dramas/episodes/characters/scenes/storyboards）、基础查询函数、统一响应格式
- **Phase 2**：所有 Adapter 实现（必须在 Phase 3 之前完成）

Phase 3 为后续阶段提供：

- **Phase 4**：TTS 服务被 `ffmpeg-compose` 调用
- **Phase 5**：Agent 工具中会调用 `GenerateImage`、`GenerateVideo`、`GenerateTTS`
- **Phase 6**：AI 配置管理路由依赖 `GetActiveConfig` 服务

---

## 13. 测试要点

### 13.1 图片生成

| 测试场景 | 验证内容 |
|----------|----------|
| 同步模式 + URL 返回 | MiniMax Provider，直接返回图片 URL |
| 同步模式 + base64 返回 | Gemini Provider，返回 base64 数据 |
| 异步模式 + 轮询 | VolcEngine/Ali Provider，轮询直到完成 |
| 参考图本地路径归一化 | `static/images/xxx.png` → `data:image/jpeg;base64,...` |
| 参考图远程 URL 保持 | `https://...` 不变 |
| 关联表更新 | storyboard/character/scene 的 image_url 正确更新 |
| 超时处理 | 10 分钟后标记为 failed |

### 13.2 视频生成

| 测试场景 | 验证内容 |
|----------|----------|
| 异步 + 轮询 | MiniMax/VolcEngine Provider |
| 异步 + Webhook | Vidu Provider，POST /webhooks/vidu |
| 首帧/尾帧 URL 归一化 | 本地路径转 DataURL |
| storyboard 关联更新 | video_url + duration 正确写入 |

### 13.3 TTS

| 测试场景 | 验证内容 |
|----------|----------|
| 正常对白 | `小明：你好世界` → speaker="小明", text="你好世界" |
| 环境音忽略 | `环境音：风吹声` → ignorable=true |
| 无对白 | `无` → ignorable=true |
| 音频文件保存 | hex 正确解码为 MP3 |

### 13.4 Webhook

| 测试场景 | 验证内容 |
|----------|----------|
| 成功回调 | state=success → 下载视频 → 更新 DB |
| 失败回调 | state=failed → 标记 error |
| 无效 task_id | 返回成功避免重复回调 |
| 重复回调 | 幂等处理 |
