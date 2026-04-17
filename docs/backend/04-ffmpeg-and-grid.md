# Phase 4 — FFmpeg 合成 + 拼接 + 宫格图

> 对应 TS 文件：
> - `backend/src/services/ffmpeg-compose.ts`
> - `backend/src/services/ffmpeg-merge.ts`
> - `backend/src/services/grid-split.ts`
> - `backend/src/routes/compose.ts`
> - `backend/src/routes/merge.ts`
> - `backend/src/routes/grid.ts`

---

## 1. FFmpeg 单镜头合成

### 1.1 功能描述

将一个 storyboard 的素材合成为最终视频：**原始视频 + TTS 对白音频 + SRT 字幕烧录**。

对应 TS 版 `composeStoryboard(storyboardId)` 函数。

### 1.2 处理流程

```
输入：storyboard_id
  │
  ├── 1. 读取 storyboard 记录，校验 videoUrl 非空
  ├── 2. 设置状态 compose_processing
  ├── 3. 解析对白 (parseDialogueForTTS)
  │     ├── 提取 speaker（冒号前的部分）
  │     ├── 提取 pureText（冒号后的部分，去除括号注释）
  │     └── 判断 ignorable（环境音/BGM/无对白等）
  │
  ├── 4. 生成 TTS 音频（如果非 ignorable）
  │     ├── 检查已有 ttsAudioUrl 文件是否存在 → 复用
  │     └── 不存在则调用 generateTTS()
  │           └── voiceId 来源：对白 speaker 匹配角色的 voiceStyle，默认 "alloy"
  │
  ├── 5. 生成 SRT 字幕文件（如果非 ignorable）
  │     └── 格式：1\n00:00:00,500 --> 00:00:{duration-1},000\n{pureText}\n
  │
  ├── 6. FFmpeg 合成
  │     ├── 无音频无字幕：直接复制视频（或加 -an）
  │     ├── 有音频：-map 0:v -map 1:a -c:a aac -shortest
  │     └── 有字幕：video filter subtitles=filename='...' (如果 ffmpeg 支持)
  │
  ├── 7. 成功 → 更新 composedVideoUrl, status=compose_completed
  └── 8. 失败 → 更新 status=compose_failed
```

### 1.3 对白解析规则

TS 版定义了两个正则表达式常量，Go 版需保持一致：

```go
// internal/service/ffmpeg_compose.go

var ignoreTTSSpeakers = regexp.MustCompile(
    `(?i)^(环境音|环境声|音效|效果音|sfx|sound ?effect|bgm|背景音|背景音乐|ambient)$`,
)

var ignoreTTSText = regexp.MustCompile(
    `(?i)^(无|无对白|无台词|无旁白|无需配音|无需对白|none|null|n/a|na|环境音|环境声|音效|效果音|纯音效|纯环境音|只有环境音|仅环境音|背景音|背景音乐|bgm|sfx|ambient)$`,
)

type DialogueParseResult struct {
    Speaker   string
    PureText  string
    Ignorable bool
}

func parseDialogueForTTS(dialogue string) DialogueParseResult {
    raw := strings.TrimSpace(dialogue)
    if raw == "" {
        return DialogueParseResult{Ignorable: true}
    }

    var speaker string
    if colonIdx := strings.IndexAny(raw, ":："); colonIdx != -1 {
        speaker = strings.TrimSpace(
            regexp.MustCompile(`[（(].+?[)）]`).ReplaceAllString(raw[:colonIdx], ""),
        )
        // 提取纯文本
        text := raw[colonIdx+1:]
        // 跳过 UTF-8 全角冒号占两字节的情况
        if raw[colonIdx] == '：' {
            // 已经是正确位置
        }
        text = regexp.MustCompile(`[（(].+?[)）]`).ReplaceAllString(text, "")
        text = strings.TrimSpace(text)

        ignorable := (speaker != "" && ignoreTTSSpeakers.MatchString(speaker)) ||
            text == "" || ignoreTTSText.MatchString(text)

        return DialogueParseResult{
            Speaker:   speaker,
            PureText:  text,
            Ignorable: ignorable,
        }
    }

    return DialogueParseResult{
        PureText:  raw,
        Ignorable: raw == "" || ignoreTTSText.MatchString(raw),
    }
}
```

### 1.4 SRT 字幕生成

```go
func generateSRTFile(pureText string, duration int) (string, error) {
    srtDir := filepath.Join(storageRoot, "subtitles")
    os.MkdirAll(srtDir, 0755)

    filename := uuid.New().String() + ".srt"
    srtPath := filepath.Join(srtDir, filename)

    // SRT 时间格式: HH:MM:SS,mmm
    endSec := duration - 1
    if endSec < 1 {
        endSec = 1
    }
    if endSec > 59 {
        endSec = 59
    }

    content := fmt.Sprintf("1\n00:00:00,500 --> 00:00:%02d,000\n%s\n",
        endSec, pureText)

    if err := os.WriteFile(srtPath, []byte(content), 0644); err != nil {
        return "", err
    }
    return fmt.Sprintf("static/subtitles/%s", filename), nil
}
```

### 1.5 FFmpeg 命令构建

```go
// 缓存 subtitles filter 支持检测结果
var subtitleFilterSupported *bool
var subtitleFilterOnce sync.Once

func supportsSubtitleFilter() bool {
    subtitleFilterOnce.Do(func() {
        cmd := exec.Command("ffmpeg", "-hide_banner", "-filters")
        output, err := cmd.CombinedOutput()
        if err != nil {
            val := false
            subtitleFilterSupported = &val
            return
        }
        val := bytes.Contains(output, []byte("subtitles"))
        subtitleFilterSupported = &val
    })
    return *subtitleFilterSupported
}

func buildComposeArgs(videoPath, audioPath, subtitlePath, outputPath string) []string {
    args := []string{"-y", "-i", videoPath}

    hasAudio := audioPath != ""
    hasSubtitle := subtitlePath != "" && supportsSubtitleFilter()

    if hasAudio {
        args = append(args, "-i", audioPath)
    }

    // Video filters
    if hasSubtitle {
        // SRT 路径转义（Windows 反斜杠、冒号、单引号）
        escaped := strings.ReplaceAll(subtitlePath, `\`, "/")
        escaped = strings.ReplaceAll(escaped, ":", `\:`)
        escaped = strings.ReplaceAll(escaped, "'", `\'`)
        forceStyle := `FontSize=20\,PrimaryColour=&HFFFFFF&\,OutlineColour=&H000000&\,Outline=2`
        filter := fmt.Sprintf("subtitles=filename='%s':force_style='%s'", escaped, forceStyle)
        args = append(args, "-vf", filter)
    }

    // 编码选项
    args = append(args, "-c:v", "libx264", "-preset", "fast", "-crf", "23")

    if hasAudio {
        args = append(args,
            "-map", "0:v", "-map", "1:a",
            "-c:a", "aac",
            "-shortest",
        )
    } else {
        args = append(args, "-an")
    }

    args = append(args, outputPath)
    return args
}
```

### 1.6 完整合成函数

```go
func ComposeStoryboard(db *sql.DB, storyboardID int64) (string, error) {
    // 1. 读取 storyboard
    sb, err := database.GetStoryboardByID(db, storyboardID)
    if err != nil {
        return "", fmt.Errorf("storyboard %d not found", storyboardID)
    }
    if sb.VideoURL == "" {
        return "", fmt.Errorf("storyboard %d has no video", storyboardID)
    }

    // 2. 更新状态
    database.UpdateStoryboardStatus(db, storyboardID, "compose_processing", "")

    // 3. 解析对白
    parsed := parseDialogueForTTS(sb.Dialogue)

    var audioPath, subtitlePath string

    // 4. TTS 音频
    if !parsed.Ignorable {
        // 检查已有音频
        if sb.TTSAudioURL != "" {
            absPath := toAbsPath(sb.TTSAudioURL)
            if _, err := os.Stat(absPath); err == nil {
                audioPath = absPath
            }
        }

        if audioPath == "" && parsed.PureText != "" {
            voiceID := "alloy"
            if parsed.Speaker != "" {
                // 查找角色的 voiceStyle
                ep, _ := database.GetEpisodeByID(db, sb.EpisodeID)
                if ep != nil {
                    chars, _ := database.ListCharactersByDramaID(db, ep.DramaID)
                    for _, ch := range chars {
                        if ch.Name == parsed.Speaker && ch.VoiceStyle != "" {
                            voiceID = ch.VoiceStyle
                            break
                        }
                    }
                }
            }

            audioRelPath, err := GenerateTTS(db, TTSParams{
                Text:    parsed.PureText,
                Voice:   voiceID,
                ConfigID: getEpisodeAudioConfigID(db, sb.EpisodeID),
            })
            if err == nil {
                audioPath = toAbsPath(audioRelPath)
                database.UpdateStoryboardTTS(db, storyboardID, audioRelPath)
            }
        }
    }

    // 5. SRT 字幕
    if !parsed.Ignorable && parsed.PureText != "" {
        srtRelPath, err := generateSRTFile(parsed.PureText, sb.Duration)
        if err == nil {
            subtitlePath = toAbsPath(srtRelPath)
            database.UpdateStoryboardSubtitle(db, storyboardID, srtRelPath)
        }
    }

    // 6. FFmpeg 合成
    outputDir := filepath.Join(storageRoot, "composed")
    os.MkdirAll(outputDir, 0755)
    outputPath := filepath.Join(outputDir, uuid.New().String()+".mp4")

    videoPath := toAbsPath(sb.VideoURL)
    args := buildComposeArgs(videoPath, audioPath, subtitlePath, outputPath)

    cmd := exec.Command("ffmpeg", args...)
    output, err := cmd.CombinedOutput()
    if err != nil {
        database.UpdateStoryboardStatus(db, storyboardID, "compose_failed", "")
        return "", fmt.Errorf("ffmpeg compose failed: %s: %w", string(output), err)
    }

    // 7. 更新数据库
    composedRelPath := "static/composed/" + filepath.Base(outputPath)
    database.UpdateStoryboardComposed(db, storyboardID, composedRelPath)

    return composedRelPath, nil
}
```

### 1.7 路径解析辅助

```go
func toAbsPath(relPath string) string {
    if filepath.IsAbs(relPath) {
        return relPath
    }
    if strings.HasPrefix(relPath, "static/") {
        return filepath.Join(dataRoot, relPath)
    }
    return filepath.Join(storageRoot, relPath)
}
```

---

## 2. FFmpeg 多镜头拼接

### 2.1 功能描述

将一集所有已合成的 storyboard 视频按 `storyboard_number` 顺序拼接为一集完整视频。

对应 TS 版 `mergeEpisodeVideos(episodeId, dramaId)` 函数。

### 2.2 处理流程

```
输入：episode_id, drama_id
  │
  ├── 1. 查询该集所有 storyboard，按 storyboard_number 排序
  ├── 2. 过滤出有 composedVideoUrl 的记录
  ├── 3. 校验：所有 storyboard 必须都已合成
  ├── 4. 创建 video_merges 记录 (status=processing)
  ├── 5. 异步执行拼接：
  │     ├── 生成 concat 列表文件 (file '/path/to/video1.mp4')
  │     ├── ffmpeg -f concat -safe 0 -i list.txt
  │     │     -c:v libx264 -preset medium -crf 23
  │     │     -c:a aac -ar 48000 -b:a 192k
  │     │     -movflags +faststart
  │     ├── 清理临时 concat 文件
  │     ├── ffprobe 获取总时长
  │     ├── 更新 video_merges (status=completed)
  │     └── 更新 episodes (video_url)
  └── 6. 返回 merge_id（立即返回，拼接异步进行）
```

### 2.3 concat 列表文件

```go
func generateConcatList(videoPaths []string) (string, error) {
    tempDir := filepath.Join(storageRoot, "temp")
    os.MkdirAll(tempDir, 0755)

    listPath := filepath.Join(tempDir, uuid.New().String()+".txt")

    var lines []string
    for _, vp := range videoPaths {
        abs := toAbsPath(vp)
        // ffmpeg concat 格式要求单引号转义
        escaped := strings.ReplaceAll(abs, "'", `'\''`)
        lines = append(lines, fmt.Sprintf("file '%s'", escaped))
    }

    if err := os.WriteFile(listPath, []byte(strings.Join(lines, "\n")), 0644); err != nil {
        return "", err
    }
    return listPath, nil
}
```

### 2.4 FFmpeg 拼接命令

```go
func doMerge(db *sql.DB, mergeID, episodeID int64, videos []string) error {
    // 1. 生成 concat 列表
    listPath, err := generateConcatList(videos)
    if err != nil {
        return err
    }
    defer os.Remove(listPath) // 清理临时文件

    // 2. 输出路径
    outputDir := filepath.Join(storageRoot, "merged")
    os.MkdirAll(outputDir, 0755)
    outputPath := filepath.Join(outputDir, uuid.New().String()+".mp4")

    // 3. 执行 ffmpeg
    args := []string{
        "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", listPath,
        "-fflags", "+genpts",
        "-c:v", "libx264",
        "-preset", "medium",
        "-crf", "23",
        "-c:a", "aac",
        "-ar", "48000",
        "-b:a", "192k",
        "-movflags", "+faststart",
        outputPath,
    }

    cmd := exec.Command("ffmpeg", args...)
    output, err := cmd.CombinedOutput()
    if err != nil {
        return fmt.Errorf("ffmpeg merge failed: %s: %w", string(output), err)
    }

    // 4. 获取总时长
    duration := getVideoDuration(outputPath)

    // 5. 更新 merge 记录
    mergedRelPath := "static/merged/" + filepath.Base(outputPath)
    database.UpdateMergeCompleted(db, mergeID, mergedRelPath, duration)

    // 6. 更新 episode
    database.UpdateEpisodeVideoURL(db, episodeID, mergedRelPath)

    return nil
}
```

### 2.5 ffprobe 获取视频时长

```go
func getVideoDuration(filePath string) int {
    cmd := exec.Command("ffprobe",
        "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        filePath,
    )
    output, err := cmd.Output()
    if err != nil {
        return 0
    }
    seconds, err := strconv.ParseFloat(strings.TrimSpace(string(output)), 64)
    if err != nil {
        return 0
    }
    return int(math.Round(seconds))
}
```

### 2.6 异步合并入口

```go
func MergeEpisodeVideos(db *sql.DB, episodeID, dramaID int64) (int64, error) {
    // 1. 获取所有 storyboard
    storyboards, err := database.ListStoryboardsByEpisodeID(db, episodeID)
    if err != nil {
        return 0, err
    }

    // 2. 过滤已合成的
    var composed []string
    for _, sb := range storyboards {
        if sb.ComposedVideoURL != "" {
            composed = append(composed, sb.ComposedVideoURL)
        }
    }

    if len(composed) == 0 {
        return 0, fmt.Errorf("no videos to merge")
    }
    if len(composed) != len(storyboards) {
        return 0, fmt.Errorf("only %d/%d storyboards composed", len(composed), len(storyboards))
    }

    // 3. 创建 merge 记录
    mergeID := database.InsertVideoMerge(db, episodeID, dramaID, composed)

    // 4. 异步执行
    go func() {
        if err := doMerge(db, mergeID, episodeID, composed); err != nil {
            log.Error().Err(err).Int64("mergeID", mergeID).Msg("merge failed")
            database.UpdateMergeFailed(db, mergeID, err.Error())
        }
    }()

    return mergeID, nil
}
```

---

## 3. 宫格图切割

### 3.1 功能描述

将一张 NxM 的宫格图按 rows × cols 切割为独立的小图，并分配给对应 storyboard 作为首帧/尾帧/参考图。

对应 TS 版 `splitGridImage(imagePath, rows, cols)` 函数。

### 3.2 图片切割

使用 `github.com/disintegration/imaging` 纯 Go 图片处理库替代 Node.js 的 `sharp`：

```go
package service

import (
    "fmt"
    "image"
    "os"
    "path/filepath"
    "time"

    "github.com/disintegration/imaging"
    "github.com/google/uuid"
)

type SplitResult struct {
    Index     int    `json:"index"`
    LocalPath string `json:"local_path"`
}

func SplitGridImage(imagePath string, rows, cols int) ([]SplitResult, error) {
    absPath := imagePath
    if !filepath.IsAbs(imagePath) {
        absPath = getAbsolutePath(imagePath)
    }

    // 1. 打开图片
    img, err := imaging.Open(absPath, imaging.AutoOrientation)
    if err != nil {
        return nil, fmt.Errorf("failed to open image: %w", err)
    }

    bounds := img.Bounds()
    imgW := bounds.Dx()
    imgH := bounds.Dy()

    cellW := imgW / cols
    cellH := imgH / rows

    if cellW == 0 || cellH == 0 {
        return nil, fmt.Errorf("cell size too small: %dx%d grid on %dx%d image", cols, rows, imgW, imgH)
    }

    // 2. 输出目录
    outDir := getAbsolutePath("grid-cells")
    os.MkdirAll(outDir, 0755)

    // 3. 逐格切割
    var results []SplitResult
    ts := time.Now().UnixMilli()

    for r := 0; r < rows; r++ {
        for c := 0; c < cols; c++ {
            index := r*cols + c

            // imaging.Crop 裁切区域
            rect := image.Rect(
                c*cellW,
                r*cellH,
                (c+1)*cellW,
                (r+1)*cellH,
            )
            cell := imaging.Crop(img, rect)

            fileName := fmt.Sprintf("cell_%d_%d.png", ts, index)
            outPath := filepath.Join(outDir, fileName)

            if err := imaging.Save(cell, outPath); err != nil {
                return nil, fmt.Errorf("failed to save cell %d: %w", index, err)
            }

            results = append(results, SplitResult{
                Index:     index,
                LocalPath: "static/grid-cells/" + fileName,
            })
        }
    }

    return results, nil
}
```

---

## 4. 路由实现

### 4.1 Compose 路由

对应 TS 版 `backend/src/routes/compose.ts`

```go
// internal/handler/compose.go

func (h *Handler) RegisterComposeRoutes(rg *gin.RouterGroup) {
    rg.POST("/compose/storyboards/:id/compose", h.ComposeShot)
    rg.POST("/compose/episodes/:id/compose-all", h.ComposeAll)
    rg.GET("/compose/episodes/:id/compose-status", h.ComposeStatus)
}

// POST /compose/storyboards/:id/compose
func (h *Handler) ComposeShot(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    composedURL, err := service.ComposeStoryboard(h.DB, id)
    if err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    util.Success(c, gin.H{
        "id":               id,
        "composed_video_url": composedURL,
    })
}

// POST /compose/episodes/:id/compose-all
func (h *Handler) ComposeAll(c *gin.Context) {
    episodeID, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    storyboards, err := database.ListStoryboardsByEpisodeID(h.DB, episodeID)
    if err != nil || len(storyboards) == 0 {
        util.BadRequest(c, "No storyboards found")
        return
    }

    var withVideo []database.Storyboard
    for _, sb := range storyboards {
        if sb.VideoURL != "" {
            withVideo = append(withVideo, sb)
        }
    }

    if len(withVideo) == 0 {
        util.BadRequest(c, "No storyboards have video yet")
        return
    }

    // 批量设置 processing 状态
    database.UpdateStoryboardsStatusByEpisode(h.DB, episodeID, "compose_processing")

    // 异步逐个合成
    go func() {
        for _, sb := range withVideo {
            if _, err := service.ComposeStoryboard(h.DB, sb.ID); err != nil {
                log.Error().Err(err).Int64("storyboardID", sb.ID).Msg("compose failed")
            }
        }
    }()

    util.Success(c, gin.H{
        "message": fmt.Sprintf("Started composing %d storyboards", len(withVideo)),
        "total":   len(withVideo),
    })
}

// GET /compose/episodes/:id/compose-status
func (h *Handler) ComposeStatus(c *gin.Context) {
    episodeID, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    storyboards, _ := database.ListStoryboardsByEpisodeID(h.DB, episodeID)

    var withVideo, completed, failed, processing, idle []database.Storyboard
    for _, sb := range storyboards {
        if sb.VideoURL == "" {
            continue
        }
        withVideo = append(withVideo, sb)
        switch {
        case sb.Status == "compose_completed" && sb.ComposedVideoURL != "":
            completed = append(completed, sb)
        case sb.Status == "compose_failed":
            failed = append(failed, sb)
        case sb.Status == "compose_processing":
            processing = append(processing, sb)
        default:
            idle = append(idle, sb)
        }
    }

    type composeItem struct {
        ID               int64  `json:"id"`
        StoryboardNumber int    `json:"storyboard_number"`
        Status           string `json:"status"`
        ComposedVideoURL string `json:"composed_video_url"`
        ErrorMsg         string `json:"error_msg"`
    }

    items := make([]composeItem, 0, len(withVideo))
    for _, sb := range withVideo {
        status := sb.Status
        if status == "" {
            status = "pending"
        }
        errMsg := ""
        if status == "compose_failed" {
            errMsg = "视频合成失败，请检查视频、配音或字幕素材"
        }
        items = append(items, composeItem{
            ID:               sb.ID,
            StoryboardNumber: sb.StoryboardNumber,
            Status:           status,
            ComposedVideoURL: sb.ComposedVideoURL,
            ErrorMsg:         errMsg,
        })
    }

    util.Success(c, gin.H{
        "total":      len(withVideo),
        "completed":  len(completed),
        "failed":     len(failed),
        "processing": len(processing),
        "idle":       len(idle),
        "items":      items,
    })
}
```

### 4.2 Merge 路由

对应 TS 版 `backend/src/routes/merge.ts`

```go
// internal/handler/merge.go

func (h *Handler) RegisterMergeRoutes(rg *gin.RouterGroup) {
    rg.POST("/merge/episodes/:id/merge", h.MergeEpisode)
    rg.GET("/merge/episodes/:id/merge", h.MergeStatus)
}

// POST /merge/episodes/:id/merge
func (h *Handler) MergeEpisode(c *gin.Context) {
    episodeID, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    // 获取 episode 以得到 dramaID
    ep, err := database.GetEpisodeByID(h.DB, episodeID)
    if err != nil {
        util.BadRequest(c, "Episode not found")
        return
    }

    mergeID, err := service.MergeEpisodeVideos(h.DB, episodeID, ep.DramaID)
    if err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    util.Success(c, gin.H{
        "merge_id": mergeID,
        "status":   "processing",
    })
}

// GET /merge/episodes/:id/merge
func (h *Handler) MergeStatus(c *gin.Context) {
    episodeID, _ := strconv.ParseInt(c.Param("id"), 10, 64)

    merge, err := database.GetLatestVideoMergeByEpisodeID(h.DB, episodeID)
    if err != nil {
        util.BadRequest(c, "No merge record found")
        return
    }

    util.Success(c, util.ToSnakeCase(merge))
}
```

### 4.3 Grid 路由

对应 TS 版 `backend/src/routes/grid.ts`，包含 4 个端点：

```go
// internal/handler/grid.go

func (h *Handler) RegisterGridRoutes(rg *gin.RouterGroup) {
    rg.POST("/grid/prompt", h.GridPrompt)
    rg.POST("/grid/generate", h.GridGenerate)
    rg.POST("/grid/split", h.GridSplit)
    rg.GET("/grid/status/:id", h.GridStatus)
}

// POST /grid/prompt
// 生成宫格图提示词（优先使用 Agent，失败则 fallback 规则模板）
func (h *Handler) GridPrompt(c *gin.Context) {
    var req struct {
        StoryboardIDs []int64 `json:"storyboard_ids" binding:"required"`
        DramaID       int64   `json:"drama_id"`
        EpisodeID     int64   `json:"episode_id"`
        Rows          int     `json:"rows" binding:"required"`
        Cols          int     `json:"cols" binding:"required"`
        Mode          string  `json:"mode"` // first_frame / first_last / multi_ref
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    if req.Mode == "" {
        req.Mode = "first_frame"
    }

    // 策略：先尝试 Agent 生成，失败则用规则模板
    result, err := h.gridPromptWithAgent(req)
    if err != nil {
        // Fallback
        result = h.gridPromptFallback(req)
    }

    util.Success(c, result)
}

// POST /grid/generate
// 提交宫格图图片生成任务
func (h *Handler) GridGenerate(c *gin.Context) {
    var req struct {
        StoryboardIDs []int64 `json:"storyboard_ids" binding:"required"`
        DramaID       int64   `json:"drama_id"`
        Rows          int     `json:"rows" binding:"required"`
        Cols          int     `json:"cols" binding:"required"`
        Mode          string  `json:"mode"`
        CustomPrompt  string  `json:"custom_prompt"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    // 计算画布尺寸：960*cols x 540*rows
    width := 960 * req.Cols
    height := 540 * req.Rows

    // 收集参考图
    var refImages []string
    for _, sbID := range req.StoryboardIDs {
        sb, _ := database.GetStoryboardByID(h.DB, sbID)
        if sb != nil {
            if sb.FirstFrameImage != "" {
                refImages = append(refImages, sb.FirstFrameImage)
            }
            if sb.LastFrameImage != "" {
                refImages = append(refImages, sb.LastFrameImage)
            }
            if sb.ComposedImage != "" {
                refImages = append(refImages, sb.ComposedImage)
            }
        }
    }

    // 构建提示词
    prompt := req.CustomPrompt
    if prompt == "" {
        prompt = fmt.Sprintf(
            "A %dx%d comic panel grid with exactly %d visible panels arranged in %d rows and %d columns, "+
                "consistent art style, cinematic quality, no text, no watermark",
            width, height, req.Rows*req.Cols, req.Rows, req.Cols,
        )
    }

    size := fmt.Sprintf("%dx%d", width, height)

    genID, err := service.GenerateImage(h.DB, service.ImageGenParams{
        DramaID:         req.DramaID,
        Prompt:          prompt,
        Size:            size,
        ReferenceImages: refImages,
    })
    if err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    util.Success(c, gin.H{
        "image_generation_id": genID,
    })
}

// POST /grid/split
// 切割已完成的宫格图并分配到 storyboard
func (h *Handler) GridSplit(c *gin.Context) {
    var req struct {
        ImageGenID int64 `json:"image_generation_id" binding:"required"`
        Rows       int   `json:"rows" binding:"required"`
        Cols       int   `json:"cols" binding:"required"`
        Assignments []struct {
            StoryboardID int64  `json:"storyboard_id"`
            FrameType    string `json:"frame_type"` // first_frame / last_frame / reference
        } `json:"assignments" binding:"required"`
    }
    if err := c.ShouldBindJSON(&req); err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    // 1. 获取图片生成记录
    gen, err := database.GetImageGenerationByID(h.DB, req.ImageGenID)
    if err != nil || gen.LocalPath == "" {
        util.BadRequest(c, "Image generation not completed or not found")
        return
    }

    // 2. 切割
    results, err := service.SplitGridImage(gen.LocalPath, req.Rows, req.Cols)
    if err != nil {
        util.BadRequest(c, err.Error())
        return
    }

    // 3. 分配到 storyboard
    assigned := 0
    for i, assignment := range req.Assignments {
        if i >= len(results) {
            break
        }
        cellPath := results[i].LocalPath
        err := database.UpdateStoryboardFrameImage(h.DB, assignment.StoryboardID, assignment.FrameType, cellPath)
        if err == nil {
            assigned++
        }
    }

    util.Success(c, gin.H{
        "total_cells": len(results),
        "assigned":    assigned,
        "cells":       results,
    })
}

// GET /grid/status/:id
func (h *Handler) GridStatus(c *gin.Context) {
    id, _ := strconv.ParseInt(c.Param("id"), 10, 64)
    gen, err := database.GetImageGenerationByID(h.DB, id)
    if err != nil {
        util.BadRequest(c, "Not found")
        return
    }
    util.Success(c, util.ToSnakeCase(gen))
}
```

---

## 5. 数据库查询补充

Phase 4 需要的数据库操作（在 Phase 1 的 database 层基础上补充）：

```go
// Storyboard 相关
func GetStoryboardByID(db *sql.DB, id int64) (*Storyboard, error)
func ListStoryboardsByEpisodeID(db *sql.DB, episodeID int64) ([]Storyboard, error)
func UpdateStoryboardStatus(db *sql.DB, id int64, status, composedVideoURL string)
func UpdateStoryboardTTS(db *sql.DB, id int64, ttsAudioURL string)
func UpdateStoryboardSubtitle(db *sql.DB, id int64, subtitleURL string)
func UpdateStoryboardComposed(db *sql.DB, id int64, composedVideoURL string)
func UpdateStoryboardFrameImage(db *sql.DB, id int64, frameType, localPath string) error
func UpdateStoryboardsStatusByEpisode(db *sql.DB, episodeID int64, status string)

// Episode 相关
func GetEpisodeByID(db *sql.DB, id int64) (*Episode, error)
func UpdateEpisodeVideoURL(db *sql.DB, id int64, videoURL string)

// VideoMerge 相关
func InsertVideoMerge(db *sql.DB, episodeID, dramaID int64, videos []string) int64
func UpdateMergeCompleted(db *sql.DB, id int64, mergedURL string, duration int)
func UpdateMergeFailed(db *sql.DB, id int64, errMsg string)
func GetLatestVideoMergeByEpisodeID(db *sql.DB, episodeID int64) (*VideoMerge, error)

// ImageGeneration 相关
func GetImageGenerationByID(db *sql.DB, id int64) (*ImageGeneration, error)
```

---

## 6. 错误处理策略

| 场景 | 处理方式 |
|------|---------|
| storyboard 无视频 | 返回 400 错误，不开始合成 |
| TTS 生成失败 | 跳过音频，继续合成（无音频视频） |
| SRT 生成失败 | 跳过字幕，继续合成 |
| ffmpeg 不支持 subtitles filter | 跳过字幕烧录，日志警告 |
| ffmpeg 合成失败 | 更新状态为 `compose_failed`，返回错误 |
| 拼接时部分镜头未合成 | 返回 400 错误，要求先完成所有镜头合成 |
| 拼接失败 | 更新 merge 状态为 `failed` |
| 宫格图切割时图片未就绪 | 返回 400 错误 |
| 切割后分配超出的 assignment | 忽略多余项 |

---

## 7. 测试要点

### 7.1 单镜头合成

- [ ] 无对白 storyboard 合成（无音频无字幕）
- [ ] 有对白 storyboard 合成（生成 TTS + SRT + 合成）
- [ ] 已有 ttsAudioUrl 时复用音频
- [ ] 对白为环境音/BGM 时跳过 TTS
- [ ] ffmpeg 不支持 subtitles filter 时的 fallback
- [ ] 合成失败时状态正确回滚

### 7.2 多镜头拼接

- [ ] 正常拼接 2+ 个已合成镜头
- [ ] 未全部合成时拒绝拼接
- [ ] 拼接后 episode.videoUrl 正确更新
- [ ] ffprobe 时长获取正确
- [ ] 临时 concat 文件正确清理

### 7.3 宫格图

- [ ] 2x2 宫格切割为 4 张图
- [ ] 3x3 宫格切割为 9 张图
- [ ] 切割后正确分配到 storyboard 的 first_frame / last_frame
- [ ] 宫格图生成提示词包含正确的尺寸和面板数

---

## 8. 性能考虑

### 8.1 FFmpeg 调用

- 使用 `exec.Command` 直接调用系统 ffmpeg，无封装开销
- 批量合成时顺序执行（避免同时跑多个 ffmpeg 占满 CPU）
- 可考虑限制并发 ffmpeg 进程数（如 semaphore）

### 8.2 图片切割

- `imaging` 库为纯 Go 实现，无 CGO 依赖
- 切割操作为 CPU 密集型，大图可能耗时
- 宫格图通常不超过 4K 分辨率（3840x2160），单次切割 9 格 < 100ms

### 8.3 异步任务

- 合成和拼接均为异步执行，HTTP 立即返回
- 前端通过 compose-status 和 merge-status 轮询进度
- Go goroutine 比 Node.js setTimeout 链更适合长时任务场景