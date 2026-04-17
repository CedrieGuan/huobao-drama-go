# Phase 2 — AI Provider Adapter 层

> 对应 TS 版：
> - `backend/src/services/adapters/types.ts` — 接口定义
> - `backend/src/services/adapters/registry.ts` — 注册表
> - `backend/src/services/adapters/url.ts` — URL 构建
> - `backend/src/services/adapters/minimax-image.ts`
> - `backend/src/services/adapters/minimax-video.ts`
> - `backend/src/services/adapters/minimax-tts.ts`
> - `backend/src/services/adapters/openai-image.ts`
> - `backend/src/services/adapters/gemini-image.ts`
> - `backend/src/services/adapters/volcengine-image.ts`
> - `backend/src/services/adapters/volcengine-video.ts`
> - `backend/src/services/adapters/vidu-video.ts`
> - `backend/src/services/adapters/ali-image.ts`
> - `backend/src/services/adapters/ali-video.ts`

---

## 1. 概述

Adapter 层将不同 AI 服务商的 API 差异抽象为统一接口，使上层 Service 无需关心具体 Provider 的请求/响应格式。

### 1.1 支持的 Provider 清单

| Provider | 图片生成 | 视频生成 | TTS |
|----------|---------|---------|-----|
| MiniMax | ✅ sync/async | ✅ async poll | ✅ sync hex |
| OpenAI | ✅ url/base64 | — | — |
| Gemini | ✅ base64 | — | — |
| VolcEngine (火山引擎) | ✅ async | ✅ async 4-12s | — |
| Vidu | — | ✅ webhook only | — |
| Ali (通义万相) | ✅ DashScope async | ✅ DashScope async | — |
| Chatfire | ✅ (复用 OpenAI) | — | — |

---

## 2. 接口定义

### 2.1 internal/adapter/types.go

```go
package adapter

import "encoding/json"

// ========== 通用类型 ==========

// ProviderRequest 统一的 HTTP 请求结构
type ProviderRequest struct {
    URL     string            `json:"url"`
    Method  string            `json:"method"`
    Headers map[string]string `json:"headers"`
    Body    interface{}       `json:"body,omitempty"`
}

// AIConfig 从数据库查出的 AI 配置
type AIConfig struct {
    Provider string
    BaseURL  string
    APIKey   string
    Model    string
}

// ImageGenRecord 图片生成记录（从 DB 读取）
type ImageGenRecord struct {
    ID              int64
    Model           string
    Prompt          string
    Size            string
    FrameType       string
    ReferenceImages []string // 已归一化的参考图列表
}

// VideoGenRecord 视频生成记录（从 DB 读取）
type VideoGenRecord struct {
    ID                 int64
    Model              string
    Prompt             string
    ReferenceMode      string // none / single / first_last / multiple
    ImageURL           string // 已归一化
    FirstFrameURL      string // 已归一化
    LastFrameURL       string // 已归一化
    ReferenceImageURLs string // JSON 数组字符串，已归一化
    Duration           int
    AspectRatio        string
}

// ImageGenResponse 图片生成 API 响应解析结果
type ImageGenResponse struct {
    IsAsync  bool
    TaskID   string
    ImageURL string
}

// ImagePollResponse 图片轮询响应解析结果
type ImagePollResponse struct {
    Status   string // pending / processing / completed / failed
    ImageURL string
    Error    string
}

// VideoGenResponse 视频生成 API 响应解析结果
type VideoGenResponse struct {
    IsAsync  bool
    TaskID   string
    VideoURL string
}

// VideoPollResponse 视频轮询响应解析结果
type VideoPollResponse struct {
    Status   string // pending / processing / completed / failed
    VideoURL string
    Error    string
}

// Base64Image base64 编码的图片数据
type Base64Image struct {
    Data     string
    MimeType string
}

// TTSResponse TTS API 响应解析结果
type TTSResponse struct {
    AudioHex   string // hex 编码的音频数据
    AudioLength int    // 音频时长 ms
    SampleRate  int
    Bitrate     int
    Format      string // mp3 / wav
    Channel     int
}

// ========== Adapter 接口 ==========

// ImageProviderAdapter 图片生成 Provider 适配器接口
type ImageProviderAdapter interface {
    // Provider 返回厂商标识
    Provider() string

    // BuildGenerateRequest 构建图片生成 API 请求
    BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error)

    // ParseGenerateResponse 解析生成响应，判断同步/异步
    ParseGenerateResponse(body json.RawMessage) (*ImageGenResponse, error)

    // BuildPollRequest 构建异步轮询请求
    BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error)

    // ParsePollResponse 解析轮询响应
    ParsePollResponse(body json.RawMessage) (*ImagePollResponse, error)

    // ExtractImageBase64 从响应中提取 base64 图片（Gemini 等）
    ExtractImageBase64(body json.RawMessage) (*Base64Image, error)
}

// VideoProviderAdapter 视频生成 Provider 适配器接口
type VideoProviderAdapter interface {
    // Provider 返回厂商标识
    Provider() string

    // BuildGenerateRequest 构建视频生成 API 请求
    BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error)

    // ParseGenerateResponse 解析生成响应，判断同步/异步
    ParseGenerateResponse(body json.RawMessage) (*VideoGenResponse, error)

    // BuildPollRequest 构建异步轮询请求
    BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error)

    // ParsePollResponse 解析轮询响应
    ParsePollResponse(body json.RawMessage) (*VideoPollResponse, error)
}

// TTSProviderAdapter TTS 语音合成 Provider 适配器接口
type TTSProviderAdapter interface {
    // Provider 返回厂商标识
    Provider() string

    // BuildGenerateRequest 构建 TTS API 请求
    BuildGenerateRequest(config *AIConfig, params map[string]interface{}) (*ProviderRequest, error)

    // ParseResponse 解析 TTS 响应
    ParseResponse(body json.RawMessage) (*TTSResponse, error)
}
```

---

## 3. URL 构建工具

### 3.1 internal/adapter/url_builder.go

对应 TS 版 `backend/src/services/adapters/url.ts`。

```go
package adapter

import (
    "net/url"
    "strings"
)

// JoinProviderURL 安全拼接 Provider URL
// 确保 requiredPrefix 存在于最终 URL 路径中
func JoinProviderURL(baseURL, requiredPrefix, path string) string {
    baseURL = strings.TrimRight(baseURL, "/")
    requiredPrefix = normalizeSegment(requiredPrefix)
    path = normalizeSegment(path)

    // 尝试解析为合法 URL
    parsed, err := url.Parse(baseURL)
    if err != nil {
        // 不是合法 URL，作为字符串拼接
        return buildPathString(baseURL, requiredPrefix, path)
    }

    currentPath := parsed.Path
    if !strings.HasSuffix(currentPath, "/") && currentPath != "" {
        // 检查 currentPath 是否已包含 requiredPrefix
    }

    // 确保 requiredPrefix 存在
    if !pathContainsPrefix(currentPath, requiredPrefix) {
        currentPath = appendPath(currentPath, requiredPrefix)
    }

    // 追加 endpoint path
    if path != "" {
        currentPath = appendPath(currentPath, path)
    }

    parsed.Path = currentPath
    return parsed.String()
}

func normalizeSegment(s string) string {
    s = strings.TrimSpace(s)
    if s != "" && !strings.HasPrefix(s, "/") {
        s = "/" + s
    }
    return s
}

func pathContainsPrefix(currentPath, prefix string) bool {
    if prefix == "" {
        return true
    }
    // 标准化后比较
    normalized := strings.TrimSuffix(currentPath, "/")
    prefixNorm := strings.TrimSuffix(prefix, "/")
    return strings.Contains(normalized, prefixNorm)
}

func appendPath(base, suffix string) string {
    base = strings.TrimRight(base, "/")
    suffix = strings.TrimLeft(suffix, "/")
    if base == "" {
        return "/" + suffix
    }
    return base + "/" + suffix
}

func buildPathString(base, prefix, path string) string {
    result := strings.TrimRight(base, "/")

    if !strings.Contains(result, strings.TrimSuffix(prefix, "/")) {
        result += normalizeSegment(prefix)
    }

    if path != "" {
        result += normalizeSegment(path)
    }

    return result
}
```

---

## 4. 注册表

### 4.1 internal/adapter/registry.go

对应 TS 版 `backend/src/services/adapters/registry.ts`。

```go
package adapter

import "fmt"

// ========== 注册表 ==========

var imageAdapters = map[string]ImageProviderAdapter{
    "minimax":    &MiniMaxImageAdapter{},
    "openai":     &OpenAIImageAdapter{},
    "gemini":     &GeminiImageAdapter{},
    "volcengine": &VolcEngineImageAdapter{},
    "ali":        &AliImageAdapter{},
    "chatfire":   &OpenAIImageAdapter{}, // 复用 OpenAI 格式
}

var videoAdapters = map[string]VideoProviderAdapter{
    "minimax":    &MiniMaxVideoAdapter{},
    "volcengine": &VolcEngineVideoAdapter{},
    "vidu":       &ViduVideoAdapter{},
    "ali":        &AliVideoAdapter{},
}

var ttsAdapters = map[string]TTSProviderAdapter{
    "minimax": &MiniMaxTTSAdapter{},
}

// GetImageAdapter 获取图片 Adapter，未知厂商回退到 MiniMax
func GetImageAdapter(provider string) ImageProviderAdapter {
    if adp, ok := imageAdapters[provider]; ok {
        return adp
    }
    return imageAdapters["minimax"]
}

// GetVideoAdapter 获取视频 Adapter，未知厂商回退到 MiniMax
func GetVideoAdapter(provider string) VideoProviderAdapter {
    if adp, ok := videoAdapters[provider]; ok {
        return adp
    }
    return videoAdapters["minimax"]
}

// GetTTSAdapter 获取 TTS Adapter，未知厂商回退到 MiniMax
func GetTTSAdapter(provider string) TTSProviderAdapter {
    if adp, ok := ttsAdapters[provider]; ok {
        return adp
    }
    return ttsAdapters["minimax"]
}

// GetProviderList 返回所有已注册的 Provider 信息（用于 AI Providers 列表 API）
func GetProviderList() []map[string]interface{} {
    providers := []map[string]interface{}{
        {"name": "minimax", "display_name": "MiniMax", "service_type": "image", "provider": "minimax"},
        {"name": "minimax", "display_name": "MiniMax", "service_type": "video", "provider": "minimax"},
        {"name": "minimax", "display_name": "MiniMax", "service_type": "audio", "provider": "minimax"},
        {"name": "openai", "display_name": "OpenAI", "service_type": "image", "provider": "openai"},
        {"name": "gemini", "display_name": "Google Gemini", "service_type": "image", "provider": "gemini"},
        {"name": "volcengine", "display_name": "火山引擎", "service_type": "image", "provider": "volcengine"},
        {"name": "volcengine", "display_name": "火山引擎", "service_type": "video", "provider": "volcengine"},
        {"name": "vidu", "display_name": "Vidu", "service_type": "video", "provider": "vidu"},
        {"name": "ali", "display_name": "阿里云通义万相", "service_type": "image", "provider": "ali"},
        {"name": "ali", "display_name": "阿里云通义万相", "service_type": "video", "provider": "ali"},
        {"name": "chatfire", "display_name": "ChatFire", "service_type": "image", "provider": "chatfire"},
        {"name": "chatfire", "display_name": "ChatFire", "service_type": "text", "provider": "chatfire"},
    }
    return providers
}
```

---

## 5. MiniMax 图片适配器

### 5.1 internal/adapter/minimax_image.go

对应 TS 版 `backend/src/services/adapters/minimax-image.ts`。

**关键特征：**
- POST `/v1/image_generation`
- 支持同步（直接返回 `image_url`）和异步（返回 `task_id`）
- 异步轮询 GET `/v1/image_generation/task/{taskId}`
- 参考图通过 `reference_images` 字段传入

```go
package adapter

import (
    "encoding/json"
    "fmt"
)

// MiniMaxImageAdapter MiniMax 图片生成适配器
type MiniMaxImageAdapter struct{}

func (a *MiniMaxImageAdapter) Provider() string { return "minimax" }

func (a *MiniMaxImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/v1", "/image_generation")

    // 解析 size 为 width/height
    width, height := parseSize(record.Size, 1920, 1080)

    body := map[string]interface{}{
        "model":  record.Model,
        "prompt": record.Prompt,
        "width":  width,
        "height": height,
    }

    // 可选：aspect_ratio
    if w, h := parseSize(record.Size, 0, 0); w > 0 && h > 0 {
        body["aspect_ratio"] = fmt.Sprintf("%d:%d", simplifyRatio(w, h))
    }

    // 参考图
    if len(record.ReferenceImages) > 0 {
        body["reference_images"] = record.ReferenceImages
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
            "Content-Type":  "application/json",
        },
        Body: body,
    }, nil
}

func (a *MiniMaxImageAdapter) ParseGenerateResponse(body json.RawMessage) (*ImageGenResponse, error) {
    var resp struct {
        BaseResp struct {
            StatusCode int `json:"status_code"`
        } `json:"base_resp"`
        Data struct {
            ImageURL string `json:"image_url"`
            TaskID   string `json:"task_id"`
            Status   string `json:"status"`
        } `json:"data"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, fmt.Errorf("parse minimax image response: %w", err)
    }

    // 同步模式：直接有 image_url
    if resp.Data.ImageURL != "" {
        return &ImageGenResponse{
            IsAsync:  false,
            ImageURL: resp.Data.ImageURL,
        }, nil
    }

    // 异步模式：有 task_id
    if resp.Data.TaskID != "" {
        return &ImageGenResponse{
            IsAsync: true,
            TaskID:  resp.Data.TaskID,
        }, nil
    }

    return nil, fmt.Errorf("minimax: no image_url or task_id in response")
}

func (a *MiniMaxImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/v1", "/image_generation/task/"+taskID)

    return &ProviderRequest{
        URL:    url,
        Method: "GET",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
        },
    }, nil
}

func (a *MiniMaxImageAdapter) ParsePollResponse(body json.RawMessage) (*ImagePollResponse, error) {
    var resp struct {
        Data struct {
            Status   string `json:"status"`
            ImageURL string `json:"image_url"`
        } `json:"data"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    result := &ImagePollResponse{}

    switch resp.Data.Status {
    case "success", "Done":
        result.Status = "completed"
        result.ImageURL = resp.Data.ImageURL
    case "failed", "Failed":
        result.Status = "failed"
        result.Error = "minimax generation failed"
    default:
        result.Status = "processing"
    }

    return result, nil
}

func (a *MiniMaxImageAdapter) ExtractImageBase64(body json.RawMessage) (*Base64Image, error) {
    return nil, nil // MiniMax 不返回 base64
}
```

---

## 6. MiniMax 视频适配器

### 6.1 internal/adapter/minimax_video.go

对应 TS 版 `backend/src/services/adapters/minimax-video.ts`。

**关键特征：**
- 使用 OpenAI Chat Completions 格式的 `content[]` 数组
- Prompt 包含 `--ratio` 和 `--dur` 标记
- 三种参考模式：`single`、`first_last`、`multiple`
- 异步轮询 `/v1/video_generation/task/{taskId}`

```go
package adapter

import (
    "encoding/json"
    "fmt"
    "strings"
)

// MiniMaxVideoAdapter MiniMax 视频生成适配器
type MiniMaxVideoAdapter struct{}

func (a *MiniMaxVideoAdapter) Provider() string { return "minimax" }

func (a *MiniMaxVideoAdapter) BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/v1", "/video_generation")

    // 构建 prompt（含 --ratio 和 --dur 标记）
    prompt := record.Prompt
    if record.AspectRatio != "" {
        prompt += fmt.Sprintf(" --ratio %s", record.AspectRatio)
    }
    if record.Duration > 0 {
        prompt += fmt.Sprintf(" --dur %d", record.Duration)
    }

    // content 数组（OpenAI Chat Completions 格式）
    content := []map[string]interface{}{
        {"type": "text", "text": prompt},
    }

    // 根据参考模式添加图片
    refMode := record.ReferenceMode
    if refMode == "" {
        refMode = "none"
    }

    switch refMode {
    case "single":
        if record.ImageURL != "" {
            content = append(content, map[string]interface{}{
                "type":      "image_url",
                "image_url": map[string]string{"url": record.ImageURL},
            })
        }
    case "first_last":
        if record.FirstFrameURL != "" {
            content = append(content, map[string]interface{}{
                "type":      "image_url",
                "image_url": map[string]string{"url": record.FirstFrameURL},
            })
        }
        if record.LastFrameURL != "" {
            content = append(content, map[string]interface{}{
                "type":      "image_url",
                "image_url": map[string]string{"url": record.LastFrameURL},
            })
        }
    case "multiple":
        refs := parseJSONStringArray(record.ReferenceImageURLs)
        for _, refURL := range refs {
            content = append(content, map[string]interface{}{
                "type":      "image_url",
                "image_url": map[string]string{"url": refURL},
            })
        }
    }

    body := map[string]interface{}{
        "model":    record.Model,
        "messages": []map[string]interface{}{
            {"role": "user", "content": content},
        },
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
            "Content-Type":  "application/json",
        },
        Body: body,
    }, nil
}

func (a *MiniMaxVideoAdapter) ParseGenerateResponse(body json.RawMessage) (*VideoGenResponse, error) {
    var resp struct {
        Data struct {
            TaskID   string `json:"task_id"`
            VideoURL string `json:"video_url"`
            Status   string `json:"status"`
        } `json:"data"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    if resp.Data.VideoURL != "" {
        return &VideoGenResponse{IsAsync: false, VideoURL: resp.Data.VideoURL}, nil
    }

    if resp.Data.TaskID != "" {
        return &VideoGenResponse{IsAsync: true, TaskID: resp.Data.TaskID}, nil
    }

    return nil, fmt.Errorf("minimax video: no task_id or video_url")
}

func (a *MiniMaxVideoAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/v1", "/video_generation/task/"+taskID)
    return &ProviderRequest{
        URL:    url,
        Method: "GET",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
        },
    }, nil
}

func (a *MiniMaxVideoAdapter) ParsePollResponse(body json.RawMessage) (*VideoPollResponse, error) {
    var resp struct {
        Data struct {
            Status   string `json:"status"`
            VideoURL string `json:"video_url"`
            Error    string `json:"error"`
        } `json:"data"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    result := &VideoPollResponse{}
    switch resp.Data.Status {
    case "success", "Done":
        result.Status = "completed"
        result.VideoURL = resp.Data.VideoURL
    case "failed", "Failed":
        result.Status = "failed"
        result.Error = resp.Data.Error
        if result.Error == "" {
            result.Error = "minimax video generation failed"
        }
    default:
        result.Status = "processing"
    }
    return result, nil
}
```

---

## 7. MiniMax TTS 适配器

### 7.1 internal/adapter/minimax_tts.go

对应 TS 版 `backend/src/services/adapters/minimax-tts.ts`。

**关键特征：**
- POST `/v1/t2a_v2`
- 音频设置：32kHz 采样率、128kbps、MP3、单声道
- 同步返回，音频数据以 **hex 编码** 存在于 `data.audio` 字段
- 支持语速、音量、音调、情感参数

```go
package adapter

import (
    "encoding/json"
    "fmt"
)

// MiniMaxTTSAdapter MiniMax TTS 适配器
type MiniMaxTTSAdapter struct{}

func (a *MiniMaxTTSAdapter) Provider() string { return "minimax" }

func (a *MiniMaxTTSAdapter) BuildGenerateRequest(config *AIConfig, params map[string]interface{}) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/v1", "/t2a_v2")

    text, _ := params["text"].(string)
    voice, _ := params["voice"].(string)
    model, _ := params["model"].(string)

    if model == "" {
        model = config.Model
    }

    speed := 1.0
    if v, ok := params["speed"].(float64); ok && v > 0 {
        speed = v
    }

    body := map[string]interface{}{
        "model": model,
        "text":  text,
        "stream": false,
        "voice_setting": map[string]interface{}{
            "voice_id": voice,
            "speed":    speed,
            "vol":      1.0,
            "pitch":    0,
        },
        "audio_setting": map[string]interface{}{
            "sample_rate": 32000,
            "bitrate":     128000,
            "format":      "mp3",
            "channel":     1,
        },
    }

    // 可选：情感
    if emotion, ok := params["emotion"].(string); ok && emotion != "" {
        body["voice_setting"].(map[string]interface{})["emotion"] = emotion
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
            "Content-Type":  "application/json",
        },
        Body: body,
    }, nil
}

func (a *MiniMaxTTSAdapter) ParseResponse(body json.RawMessage) (*TTSResponse, error) {
    var resp struct {
        Data struct {
            Audio      string `json:"audio"`       // hex 编码的音频数据
            AudioLength int   `json:"audio_length"` // 毫秒
            SampleRate  int   `json:"sample_rate"`
            Bitrate     int   `json:"bitrate"`
            Format      string `json:"format"`
            Channel     int   `json:"channel"`
        } `json:"data"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, fmt.Errorf("parse minimax tts response: %w", err)
    }

    if resp.Data.Audio == "" {
        return nil, fmt.Errorf("minimax tts: no audio data in response")
    }

    format := resp.Data.Format
    if format == "" {
        format = "mp3"
    }

    return &TTSResponse{
        AudioHex:    resp.Data.Audio,
        AudioLength: resp.Data.AudioLength,
        SampleRate:  resp.Data.SampleRate,
        Bitrate:     resp.Data.Bitrate,
        Format:      format,
        Channel:     resp.Data.Channel,
    }, nil
}
```

---

## 8. OpenAI 图片适配器

### 8.1 internal/adapter/openai_image.go

对应 TS 版 `backend/src/services/adapters/openai-image.ts`。

**关键特征：**
- POST `/v1/images/generations`
- 默认模型 `dall-e-3`
- 支持 URL 和 `b64_json` 两种响应格式
- 被 Chatfire 复用

```go
package adapter

import (
    "encoding/json"
    "fmt"
)

// OpenAIImageAdapter OpenAI / Chatfire 图片生成适配器
type OpenAIImageAdapter struct{}

func (a *OpenAIImageAdapter) Provider() string { return "openai" }

func (a *OpenAIImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/v1", "/images/generations")

    model := record.Model
    if model == "" {
        model = "dall-e-3"
    }

    body := map[string]interface{}{
        "model":  model,
        "prompt": record.Prompt,
        "n":      1,
        "size":   record.Size,
        "response_format": "url",
    }

    // 参考图：OpenAI 通过 edit API 支持，这里简化处理
    if len(record.ReferenceImages) > 0 {
        // OpenAI 图片编辑需要不同的端点，这里传入作为 prompt 增强
        // 实际使用时需要根据模型能力调整
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
            "Content-Type":  "application/json",
        },
        Body: body,
    }, nil
}

func (a *OpenAIImageAdapter) ParseGenerateResponse(body json.RawMessage) (*ImageGenResponse, error) {
    var resp struct {
        Data []struct {
            URL           string `json:"url"`
            B64JSON       string `json:"b64_json"`
            RevisedPrompt string `json:"revised_prompt"`
        } `json:"data"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    if len(resp.Data) == 0 {
        return nil, fmt.Errorf("openai: no data in response")
    }

    item := resp.Data[0]
    if item.URL != "" {
        return &ImageGenResponse{IsAsync: false, ImageURL: item.URL}, nil
    }
    if item.B64JSON != "" {
        // base64 模式，返回空 URL 标记需要 base64 处理
        return &ImageGenResponse{IsAsync: false}, nil
    }

    return nil, fmt.Errorf("openai: no url or b64_json in response")
}

func (a *OpenAIImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
    // OpenAI 图片生成是同步的，不需要轮询
    return nil, fmt.Errorf("openai image does not support polling")
}

func (a *OpenAIImageAdapter) ParsePollResponse(body json.RawMessage) (*ImagePollResponse, error) {
    return nil, fmt.Errorf("openai image does not support polling")
}

func (a *OpenAIImageAdapter) ExtractImageBase64(body json.RawMessage) (*Base64Image, error) {
    var resp struct {
        Data []struct {
            B64JSON string `json:"b64_json"`
        } `json:"data"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }
    if len(resp.Data) > 0 && resp.Data[0].B64JSON != "" {
        return &Base64Image{
            Data:     resp.Data[0].B64JSON,
            MimeType: "image/png",
        }, nil
    }
    return nil, nil
}
```

---

## 9. Gemini 图片适配器

### 9.1 internal/adapter/gemini_image.go

对应 TS 版 `backend/src/services/adapters/gemini-image.ts`。

**关键特征：**
- 使用 Google REST API 格式 `contents[].parts[]`
- 双重认证：`?key=` 查询参数 + `x-goog-api-key` 头
- 主要返回 **base64**（通过 `inlineData.data`）
- `size` 需转换为 `aspectRatio`（使用 GCD 简化比）和 `imageSize`（512/1K/2K/4K）
- 参考图通过 `inline_data` parts 传入

```go
package adapter

import (
    "encoding/json"
    "fmt"
    "math"
    "strings"
)

// GeminiImageAdapter Google Gemini 图片生成适配器
type GeminiImageAdapter struct{}

func (a *GeminiImageAdapter) Provider() string { return "gemini" }

func (a *GeminiImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
    // Gemini 使用 model 名称作为 URL 路径的一部分
    model := record.Model
    if model == "" {
        model = "gemini-2.0-flash-exp"
    }

    endpoint := fmt.Sprintf("/models/%s:generateContent", model)
    url := JoinProviderURL(config.BaseURL, "/v1beta", endpoint)

    // 添加 API key 作为查询参数
    if !strings.Contains(url, "key=") {
        sep := "?"
        if strings.Contains(url, "?") {
            sep = "&"
        }
        url += sep + "key=" + config.APIKey
    }

    // 解析 size 为 aspectRatio 和 imageSize
    width, height := parseSize(record.Size, 1024, 1024)
    aspectRatio := computeAspectRatio(width, height)
    imageSize := computeImageSize(width, height)

    // 构建 parts
    parts := []map[string]interface{}{
        {"text": record.Prompt},
    }

    // 参考图作为 inline_data parts
    for _, ref := range record.ReferenceImages {
        if strings.HasPrefix(ref, "data:") {
            mimeType, data := parseDataURL(ref)
            parts = append(parts, map[string]interface{}{
                "inline_data": map[string]interface{}{
                    "mime_type": mimeType,
                    "data":      data,
                },
            })
        }
    }

    // 构建 generationConfig
    genConfig := map[string]interface{}{
        "responseModalities": []string{"TEXT", "IMAGE"},
    }
    if imageSize != "" {
        genConfig["imageSize"] = imageSize
    }

    body := map[string]interface{}{
        "contents": []map[string]interface{}{
            {
                "parts": parts,
            },
        },
        "generationConfig": genConfig,
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Content-Type":    "application/json",
            "x-goog-api-key":  config.APIKey,
        },
        Body: body,
    }, nil
}

func (a *GeminiImageAdapter) ParseGenerateResponse(body json.RawMessage) (*ImageGenResponse, error) {
    var resp struct {
        Candidates []struct {
            Content struct {
                Parts []struct {
                    Text       string `json:"text"`
                    InlineData *struct {
                        MimeType string `json:"mimeType"`
                        Data     string `json:"data"`
                    } `json:"inlineData"`
                } `json:"parts"`
            } `json:"content"`
        } `json:"candidates"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    // Gemini 同步返回 base64 数据，无 URL
    return &ImageGenResponse{
        IsAsync:  false,
        ImageURL: "", // 标记需要 base64 处理
    }, nil
}

func (a *GeminiImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
    return nil, fmt.Errorf("gemini does not support async polling")
}

func (a *GeminiImageAdapter) ParsePollResponse(body json.RawMessage) (*ImagePollResponse, error) {
    return nil, fmt.Errorf("gemini does not support async polling")
}

func (a *GeminiImageAdapter) ExtractImageBase64(body json.RawMessage) (*Base64Image, error) {
    var resp struct {
        Candidates []struct {
            Content struct {
                Parts []struct {
                    InlineData *struct {
                        MimeType string `json:"mimeType"`
                        Data     string `json:"data"`
                    } `json:"inlineData"`
                } `json:"parts"`
            } `json:"content"`
        } `json:"candidates"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    for _, candidate := range resp.Candidates {
        for _, part := range candidate.Content.Parts {
            if part.InlineData != nil && part.InlineData.Data != "" {
                return &Base64Image{
                    Data:     part.InlineData.Data,
                    MimeType: part.InlineData.MimeType,
                }, nil
            }
        }
    }
    return nil, nil
}

// computeAspectRatio 使用 GCD 简化宽高比
func computeAspectRatio(w, h int) string {
    g := gcd(w, h)
    return fmt.Sprintf("%d:%d", w/g, h/g)
}

// computeImageSize 根据较大边确定 Gemini imageSize 级别
func computeImageSize(w, h int) string {
    max := w
    if h > w {
        max = h
    }
    switch {
    case max <= 512:
        return "512"
    case max <= 1024:
        return "1K"
    case max <= 2048:
        return "2K"
    default:
        return "4K"
    }
}

func gcd(a, b int) int {
    for b != 0 {
        a, b = b, a%b
    }
    return a
}

// parseDataURL 解析 data:mime;base64,xxx 格式
func parseDataURL(dataURL string) (mimeType, data string) {
    if !strings.HasPrefix(dataURL, "data:") {
        return "", dataURL
    }
    rest := dataURL[5:]
    idx := strings.Index(rest, ",")
    if idx == -1 {
        return "", dataURL
    }
    meta := rest[:idx]
    data = rest[idx+1:]
    // 提取 MIME 类型
    if semiIdx := strings.Index(meta, ";"); semiIdx != -1 {
        mimeType = meta[:semiIdx]
    } else {
        mimeType = meta
    }
    return mimeType, data
}
```

---

## 10. VolcEngine 图片适配器

### 10.1 internal/adapter/volcengine_image.go

对应 TS 版 `backend/src/services/adapters/volcengine-image.ts`。

**关键特征：**
- POST `/api/v3/images/generations`
- 使用 `doubao-seedream` 系列模型
- `size` 解析为 `width`/`height` 分开传入
- 支持异步（返回 `task_id`）和同步

```go
package adapter

import (
    "encoding/json"
    "fmt"
)

// VolcEngineImageAdapter 火山引擎（字节跳动）图片生成适配器
type VolcEngineImageAdapter struct{}

func (a *VolcEngineImageAdapter) Provider() string { return "volcengine" }

func (a *VolcEngineImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/api/v3", "/images/generations")

    width, height := parseSize(record.Size, 1024, 1024)

    body := map[string]interface{}{
        "model":  record.Model,
        "prompt": record.Prompt,
        "width":  width,
        "height": height,
    }

    // 参考图
    if len(record.ReferenceImages) > 0 {
        body["reference_images"] = record.ReferenceImages
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
            "Content-Type":  "application/json",
        },
        Body: body,
    }, nil
}

func (a *VolcEngineImageAdapter) ParseGenerateResponse(body json.RawMessage) (*ImageGenResponse, error) {
    var resp struct {
        Data []struct {
            URL string `json:"url"`
        } `json:"data"`
        TaskID string `json:"task_id"`
        Status string `json:"status"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    // 同步模式
    if len(resp.Data) > 0 && resp.Data[0].URL != "" {
        return &ImageGenResponse{
            IsAsync:  false,
            ImageURL: resp.Data[0].URL,
        }, nil
    }

    // 异步模式
    if resp.TaskID != "" {
        return &ImageGenResponse{
            IsAsync: true,
            TaskID:  resp.TaskID,
        }, nil
    }

    return nil, fmt.Errorf("volcengine image: no url or task_id")
}

func (a *VolcEngineImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/api/v3", "/images/generations/tasks/"+taskID)
    return &ProviderRequest{
        URL:    url,
        Method: "GET",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
        },
    }, nil
}

func (a *VolcEngineImageAdapter) ParsePollResponse(body json.RawMessage) (*ImagePollResponse, error) {
    var resp struct {
        Status string `json:"status"`
        Data   []struct {
            URL string `json:"url"`
        } `json:"data"`
        Error struct {
            Message string `json:"message"`
        } `json:"error"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    result := &ImagePollResponse{}
    switch strings.ToLower(resp.Status) {
    case "succeeded", "success":
        result.Status = "completed"
        if len(resp.Data) > 0 {
            result.ImageURL = resp.Data[0].URL
        }
    case "failed":
        result.Status = "failed"
        result.Error = resp.Error.Message
        if result.Error == "" {
            result.Error = "volcengine image generation failed"
        }
    default:
        result.Status = "processing"
    }
    return result, nil
}

func (a *VolcEngineImageAdapter) ExtractImageBase64(body json.RawMessage) (*Base64Image, error) {
    return nil, nil
}
```

---

## 11. VolcEngine 视频适配器

### 11.1 internal/adapter/volcengine_video.go

对应 TS 版 `backend/src/services/adapters/volcengine-video.ts`。

**关键特征：**
- POST `/api/v3/contents/generations/tasks`
- 使用 `doubao-seedance` 系列模型
- Content 数组格式（与 MiniMax 视频类似）
- 时长限制 **4-12 秒**（`normalizeDuration`）
- 轮询 `/api/v3/contents/generations/tasks/{taskId}`

```go
package adapter

import (
    "encoding/json"
    "fmt"
    "strings"
)

// VolcEngineVideoAdapter 火山引擎视频生成适配器
type VolcEngineVideoAdapter struct{}

func (a *VolcEngineVideoAdapter) Provider() string { return "volcengine" }

func (a *VolcEngineVideoAdapter) BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/api/v3", "/contents/generations/tasks")

    duration := normalizeDuration(record.Duration, 4, 12)

    // 构建 content 数组
    content := []map[string]interface{}{
        {"type": "text", "text": record.Prompt},
    }

    refMode := record.ReferenceMode
    if refMode == "" {
        refMode = "none"
    }

    switch refMode {
    case "single":
        if record.ImageURL != "" {
            content = append(content, map[string]interface{}{
                "type":      "image_url",
                "image_url": map[string]string{"url": record.ImageURL},
            })
        }
    case "first_last":
        if record.FirstFrameURL != "" {
            content = append(content, map[string]interface{}{
                "type":      "image_url",
                "image_url": map[string]string{"url": record.FirstFrameURL},
            })
        }
        if record.LastFrameURL != "" {
            content = append(content, map[string]interface{}{
                "type":      "image_url",
                "image_url": map[string]string{"url": record.LastFrameURL},
            })
        }
    case "multiple":
        refs := parseJSONStringArray(record.ReferenceImageURLs)
        for _, refURL := range refs {
            content = append(content, map[string]interface{}{
                "type":      "image_url",
                "image_url": map[string]string{"url": refURL},
            })
        }
    }

    body := map[string]interface{}{
        "model": record.Model,
        "content": content,
        "duration": duration,
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
            "Content-Type":  "application/json",
        },
        Body: body,
    }, nil
}

func (a *VolcEngineVideoAdapter) ParseGenerateResponse(body json.RawMessage) (*VideoGenResponse, error) {
    var resp struct {
        ID     string `json:"id"`
        Status string `json:"status"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    if resp.ID != "" {
        return &VideoGenResponse{IsAsync: true, TaskID: resp.ID}, nil
    }
    return nil, fmt.Errorf("volcengine video: no task id")
}

func (a *VolcEngineVideoAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/api/v3", "/contents/generations/tasks/"+taskID)
    return &ProviderRequest{
        URL:    url,
        Method: "GET",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
        },
    }, nil
}

func (a *VolcEngineVideoAdapter) ParsePollResponse(body json.RawMessage) (*VideoPollResponse, error) {
    var resp struct {
        Status  string `json:"status"`
        Content struct {
            VideoURL string `json:"video_url"`
        } `json:"content"`
        Error struct {
            Message string `json:"message"`
        } `json:"error"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    result := &VideoPollResponse{}
    switch strings.ToLower(resp.Status) {
    case "succeeded", "success":
        result.Status = "completed"
        result.VideoURL = resp.Content.VideoURL
    case "failed":
        result.Status = "failed"
        result.Error = resp.Error.Message
        if result.Error == "" {
            result.Error = "volcengine video generation failed"
        }
    default:
        result.Status = "processing"
    }
    return result, nil
}

// normalizeDuration 将时长限制在 [min, max] 范围内
func normalizeDuration(d, minDur, maxDur int) int {
    if d < minDur {
        return minDur
    }
    if d > maxDur {
        return maxDur
    }
    return d
}
```

---

## 12. Vidu 视频适配器

### 12.1 internal/adapter/vidu_video.go

对应 TS 版 `backend/src/services/adapters/vidu-video.ts`。

**关键特征：**
- POST `/ent/v2/img2video`
- 使用 `Token` 认证头（不是 `Bearer`）
- **没有轮询端点**，完全依赖 **Webhook 回调**
- `parseCallbackState` 静态方法解析 Webhook 状态

```go
package adapter

import (
    "encoding/json"
    "fmt"
)

// ViduVideoAdapter Vidu 视频生成适配器（Webhook 模式）
type ViduVideoAdapter struct{}

func (a *ViduVideoAdapter) Provider() string { return "vidu" }

func (a *ViduVideoAdapter) BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/ent/v2", "/img2video")

    body := map[string]interface{}{
        "model":    record.Model,
        "prompt":   record.Prompt,
        "duration": record.Duration,
    }

    // 参考图
    if record.ImageURL != "" {
        body["image"] = record.ImageURL
    }
    if record.FirstFrameURL != "" {
        body["first_frame"] = record.FirstFrameURL
    }
    if record.LastFrameURL != "" {
        body["last_frame"] = record.LastFrameURL
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Token":        config.APIKey, // Vidu 使用 Token 头（不是 Bearer）
            "Content-Type": "application/json",
        },
        Body: body,
    }, nil
}

func (a *ViduVideoAdapter) ParseGenerateResponse(body json.RawMessage) (*VideoGenResponse, error) {
    var resp struct {
        ID     string `json:"id"`
        State  string `json:"state"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    if resp.ID != "" {
        return &VideoGenResponse{IsAsync: true, TaskID: resp.ID}, nil
    }
    return nil, fmt.Errorf("vidu: no task id in response")
}

func (a *ViduVideoAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
    // Vidu 没有轮询端点，返回一个占位 URL（不会被实际调用）
    return &ProviderRequest{
        URL:    "https://vidu.no-poll-endpoint.fake/" + taskID,
        Method: "GET",
        Headers: map[string]string{
            "Token": config.APIKey,
        },
    }, nil
}

func (a *ViduVideoAdapter) ParsePollResponse(body json.RawMessage) (*VideoPollResponse, error) {
    // Vidu 不使用轮询，始终返回 processing
    return &VideoPollResponse{Status: "processing"}, nil
}

// ParseCallbackState 解析 Webhook 回调状态（供 webhook handler 调用）
func ParseCallbackState(state string) (status string) {
    switch state {
    case "success":
        return "completed"
    case "failed":
        return "failed"
    default:
        return "processing"
    }
}
```

---

## 13. Ali 图片适配器

### 13.1 internal/adapter/ali_image.go

对应 TS 版 `backend/src/services/adapters/ali-image.ts`。

**关键特征：**
- POST `/api/v1/services/aigc/image-generation/generation`
- 使用 `wan2.6-t2i` 模型
- DashScope 异步模式：`X-DashScope-Async: enable` 头
- Size 格式转换：`"1920x1080"` → `"1696*960"`（Ali 特定格式）
- 轮询 `/api/v1/tasks/{taskId}`
- 状态映射：`PENDING → RUNNING → SUCCEEDED / FAILED`

```go
package adapter

import (
    "encoding/json"
    "fmt"
    "strings"
)

// AliImageAdapter 阿里云通义万相图片生成适配器
type AliImageAdapter struct{}

func (a *AliImageImageAdapter) Provider() string { return "ali" }

func (a *AliImageAdapter) Provider() string { return "ali" }

func (a *AliImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/api/v1", "/services/aigc/image-generation/generation")

    model := record.Model
    if model == "" {
        model = "wan2.6-t2i"
    }

    // 转换 size 格式：1920x1080 → 1696*960
    aliSize := convertToAliSize(record.Size)

    body := map[string]interface{}{
        "model": model,
        "input": map[string]interface{}{
            "prompt": record.Prompt,
        },
        "parameters": map[string]interface{}{
            "size": aliSize,
            "n":    1,
        },
    }

    // 参考图
    if len(record.ReferenceImages) > 0 {
        body["parameters"].(map[string]interface{})["ref_images"] = record.ReferenceImages
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Authorization":       "Bearer " + config.APIKey,
            "Content-Type":        "application/json",
            "X-DashScope-Async":   "enable", // DashScope 异步模式
        },
        Body: body,
    }, nil
}

func (a *AliImageAdapter) ParseGenerateResponse(body json.RawMessage) (*ImageGenResponse, error) {
    var resp struct {
        Output struct {
            TaskID     string `json:"task_id"`
            TaskStatus string `json:"task_status"`
        } `json:"output"`
        Data struct {
            Results []struct {
                URL string `json:"url"`
            } `json:"results"`
        } `json:"data"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    // 如果 DashScope 直接返回了结果（同步）
    if len(resp.Data.Results) > 0 && resp.Data.Results[0].URL != "" {
        return &ImageGenResponse{
            IsAsync:  false,
            ImageURL: resp.Data.Results[0].URL,
        }, nil
    }

    // 异步模式
    if resp.Output.TaskID != "" {
        return &ImageGenResponse{
            IsAsync: true,
            TaskID:  resp.Output.TaskID,
        }, nil
    }

    return nil, fmt.Errorf("ali image: no task_id or results")
}

func (a *AliImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/api/v1", "/tasks/"+taskID)
    return &ProviderRequest{
        URL:    url,
        Method: "GET",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
        },
    }, nil
}

func (a *AliImageAdapter) ParsePollResponse(body json.RawMessage) (*ImagePollResponse, error) {
    var resp struct {
        Output struct {
            TaskStatus string `json:"task_status"`
        } `json:"output"`
        Data struct {
            Results []struct {
                URL string `json:"url"`
            } `json:"results"`
        } `json:"data"`
        Message string `json:"message"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    result := &ImagePollResponse{}
    switch resp.Output.TaskStatus {
    case "SUCCEEDED":
        result.Status = "completed"
        if len(resp.Data.Results) > 0 {
            result.ImageURL = resp.Data.Results[0].URL
        }
    case "FAILED":
        result.Status = "failed"
        result.Error = resp.Message
        if result.Error == "" {
            result.Error = "ali image generation failed"
        }
    default: // PENDING, RUNNING
        result.Status = "processing"
    }
    return result, nil
}

func (a *AliImageAdapter) ExtractImageBase64(body json.RawMessage) (*Base64Image, error) {
    return nil, nil
}

// convertToAliSize 将标准 size 格式转为阿里格式
// "1920x1080" → "1696*960"
// 阿里对尺寸有特定要求，需要做映射
func convertToAliSize(size string) string {
    w, h := parseSize(size, 1024, 1024)
    // 阿里支持的尺寸需要按 64 对齐
    w = (w / 64) * 64
    h = (h / 64) * 64
    if w == 0 { w = 1024 }
    if h == 0 { h = 1024 }
    return fmt.Sprintf("%d*%d", w, h)
}
```

---

## 14. Ali 视频适配器

### 14.1 internal/adapter/ali_video.go

对应 TS 版 `backend/src/services/adapters/ali-video.ts`。

**关键特征：**
- POST `/api/v1/services/aigc/video-generation/video-synthesis`
- 使用 `wan2.6-i2v-flash` 模型
- 支持首帧、尾帧模式
- 分辨率按宽高比映射：`16:9 → 1080P`，`9:16 / 1:1 → 720P`
- 同样使用 DashScope 异步模式

```go
package adapter

import (
    "encoding/json"
    "fmt"
    "strings"
)

// AliVideoAdapter 阿里云通义万相视频生成适配器
type AliVideoAdapter struct{}

func (a *AliVideoAdapter) Provider() string { return "ali" }

func (a *AliVideoAdapter) BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/api/v1", "/services/aigc/video-generation/video-synthesis")

    model := record.Model
    if model == "" {
        model = "wan2.6-i2v-flash"
    }

    // 分辨率按宽高比映射
    resolution := "1080P"
    if record.AspectRatio == "9:16" || record.AspectRatio == "1:1" {
        resolution = "720P"
    }

    input := map[string]interface{}{
        "prompt":     record.Prompt,
        "resolution": resolution,
    }

    // 参考图
    if record.FirstFrameURL != "" {
        input["first_frame"] = record.FirstFrameURL
    }
    if record.LastFrameURL != "" {
        input["last_frame"] = record.LastFrameURL
    }
    if record.ImageURL != "" {
        input["img_url"] = record.ImageURL
    }

    body := map[string]interface{}{
        "model": model,
        "input": input,
        "parameters": map[string]interface{}{
            "duration": record.Duration,
        },
    }

    return &ProviderRequest{
        URL:    url,
        Method: "POST",
        Headers: map[string]string{
            "Authorization":     "Bearer " + config.APIKey,
            "Content-Type":      "application/json",
            "X-DashScope-Async": "enable",
        },
        Body: body,
    }, nil
}

func (a *AliVideoAdapter) ParseGenerateResponse(body json.RawMessage) (*VideoGenResponse, error) {
    var resp struct {
        Output struct {
            TaskID     string `json:"task_id"`
            TaskStatus string `json:"task_status"`
            VideoURL   string `json:"video_url"`
        } `json:"output"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    if resp.Output.VideoURL != "" {
        return &VideoGenResponse{IsAsync: false, VideoURL: resp.Output.VideoURL}, nil
    }

    if resp.Output.TaskID != "" {
        return &VideoGenResponse{IsAsync: true, TaskID: resp.Output.TaskID}, nil
    }

    return nil, fmt.Errorf("ali video: no task_id or video_url")
}

func (a *AliVideoAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
    url := JoinProviderURL(config.BaseURL, "/api/v1", "/tasks/"+taskID)
    return &ProviderRequest{
        URL:    url,
        Method: "GET",
        Headers: map[string]string{
            "Authorization": "Bearer " + config.APIKey,
        },
    }, nil
}

func (a *AliVideoAdapter) ParsePollResponse(body json.RawMessage) (*VideoPollResponse, error) {
    var resp struct {
        Output struct {
            TaskStatus string `json:"task_status"`
            VideoURL   string `json:"video_url"`
        } `json:"output"`
        Message string `json:"message"`
    }
    if err := json.Unmarshal(body, &resp); err != nil {
        return nil, err
    }

    result := &VideoPollResponse{}
    switch resp.Output.TaskStatus {
    case "SUCCEEDED":
        result.Status = "completed"
        result.VideoURL = resp.Output.VideoURL
    case "FAILED":
        result.Status = "failed"
        result.Error = resp.Message
        if result.Error == "" {
            result.Error = "ali video generation failed"
        }
    default:
        result.Status = "processing"
    }
    return result, nil
}
```

---

## 15. 通用辅助函数

### 15.1 internal/adapter/helpers.go

```go
package adapter

import (
    "encoding/json"
    "strconv"
    "strings"
)

// parseSize 将 "1920x1080" 解析为 (1920, 1080)
func parseSize(size string, defaultW, defaultH int) (int, int) {
    if size == "" {
        return defaultW, defaultH
    }
    parts := strings.SplitN(strings.ToLower(size), "x", 2)
    if len(parts) != 2 {
        // 尝试 * 分隔符（Ali 格式）
        parts = strings.SplitN(size, "*", 2)
    }
    if len(parts) != 2 {
        return defaultW, defaultH
    }
    w, errW := strconv.Atoi(strings.TrimSpace(parts[0]))
    h, errH := strconv.Atoi(strings.TrimSpace(parts[1]))
    if errW != nil || errH != nil {
        return defaultW, defaultH
    }
    return w, h
}

// simplifyRatio 简化宽高比（用于 --ratio 参数）
func simplifyRatio(w, h int) (int, int) {
    g := gcd(w, h)
    return w / g, h / g
}

// parseJSONStringArray 解析 JSON 字符串数组
func parseJSONStringArray(jsonStr string) []string {
    if jsonStr == "" {
        return nil
    }
    var arr []string
    if err := json.Unmarshal([]byte(jsonStr), &arr); err != nil {
        return nil
    }
    return arr
}
```

---

## 16. Phase 2 验收标准

| 验收项 | 预期结果 |
|--------|----------|
| 所有 13 个 adapter 文件编译通过 | `go build ./internal/adapter/...` 无错误 |
| 注册表返回正确 adapter | `GetImageAdapter("minimax")` 返回 `*MiniMaxImageAdapter` |
| 未知 provider 回退 | `GetImageAdapter("unknown")` 返回 MiniMax |
| MiniMax Image 同步模式 | `ParseGenerateResponse` 正确解析 `image_url` |
| MiniMax Image 异步模式 | `ParseGenerateResponse` 返回 `task_id` |
| MiniMax Video content 数组 | `BuildGenerateRequest` 构建正确的 `content[]` 格式 |
| MiniMax TTS hex 解码 | `ParseResponse` 返回 hex 编码音频 |
| OpenAI Image base64 | `ExtractImageBase64` 正确提取 `b64_json` |
| Gemini base64 | `ExtractImageBase64` 从 `inlineData.data` 提取 |
| VolcEngine 时长限制 | `normalizeDuration(3, 4, 12)` → 4 |
| Vidu 无轮询 | `BuildPollRequest` 返回占位 URL |
| Ali DashScope 异步头 | `BuildGenerateRequest` 包含 `X-DashScope-Async: enable` |
| Ali size 转换 | `"1920x1080"` → `"1920*1080"`（64 对齐后） |
| URL Builder | 各种 base+prefix+path 组合拼接正确 |

---

## 17. 与 TS 版的对照表

| TS 文件 | Go 文件 | 说明 |
|---------|---------|------|
| `adapters/types.ts` | `adapter/types.go` | 接口定义 |
| `adapters/registry.ts` | `adapter/registry.go` | 注册表 |
| `adapters/url.ts` | `adapter/url_builder.go` | URL 构建 |
| `adapters/minimax-image.ts` | `adapter/minimax_image.go` | MiniMax 图片 |
| `adapters/minimax-video.ts` | `adapter/minimax_video.go` | MiniMax 视频 |
| `adapters/minimax-tts.ts` | `adapter/minimax_tts.go` | MiniMax TTS |
| `adapters/openai-image.ts` | `adapter/openai_image.go` | OpenAI 图片 |
| `adapters/gemini-image.ts` | `adapter/gemini_image.go` | Gemini 图片 |
| `adapters/volcengine-image.ts` | `adapter/volcengine_image.go` | 火山引擎图片 |
| `adapters/volcengine-video.ts` | `adapter/volcengine_video.go` | 火山引擎视频 |
| `adapters/vidu-video.ts` | `adapter/vidu_video.go` | Vidu 视频 |
| `adapters/ali-image.ts` | `adapter/ali_image.go` | 阿里云图片 |
| `adapters/ali-video.ts` | `adapter/ali_video.go` | 阿里云视频 |
| — | `adapter/helpers.go` | 新增：通用辅助函数 |