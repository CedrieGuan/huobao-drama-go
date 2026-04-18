// Package adapter implements the VolcEngine (火山引擎/ByteDance) video generation adapter.
//
// Corresponding TypeScript source:
//
//	backend/src/services/adapters/volcengine-video.ts
//
// Key characteristics:
//   - POST /api/v3/contents/generations/tasks
//   - Default model: doubao-seedance-1-5-pro-251215
//   - Content array format (text + image_url entries)
//   - Duration clamped to [4, 12] seconds, defaults to 5
//   - Async only: response returns task ID, poll for result
//   - generate_audio: true, watermark: false in request body
//   - Ratio field from aspectRatio, defaults to "adaptive"
package adapter

import (
	"encoding/json"
	"fmt"
)

// VolcEngineVideoAdapter implements VideoProviderAdapter for VolcEngine video generation.
type VolcEngineVideoAdapter struct{}

func init() {
	RegisterVideoAdapter("volcengine", &VolcEngineVideoAdapter{})
}

func (a *VolcEngineVideoAdapter) Provider() string { return "volcengine" }

// BuildGenerateRequest constructs the HTTP request for VolcEngine video generation.
//
// The request uses a content[] array with text prompt and optional image references.
// Duration is clamped to the 4–12 second range. The body includes generate_audio and
// watermark flags.
func (a *VolcEngineVideoAdapter) BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/api/v3", "/contents/generations/tasks")

	model := record.Model
	if model == "" {
		model = "doubao-seedance-1-5-pro-251215"
	}

	duration := clampDuration(record.Duration, 4, 12, 5)

	// Build content array
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
				"role":      "first_frame",
			})
		}
		if record.LastFrameURL != "" {
			content = append(content, map[string]interface{}{
				"type":      "image_url",
				"image_url": map[string]string{"url": record.LastFrameURL},
				"role":      "last_frame",
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

	ratio := record.AspectRatio
	if ratio == "" {
		ratio = "adaptive"
	}

	body := map[string]interface{}{
		"model":          model,
		"content":        content,
		"ratio":          ratio,
		"duration":       duration,
		"generate_audio": true,
		"watermark":      false,
	}

	return &ProviderRequest{
		URL:    endpoint,
		Method: "POST",
		Headers: map[string]string{
			"Authorization": "Bearer " + config.APIKey,
			"Content-Type":  "application/json",
		},
		Body: body,
	}, nil
}

// ParseGenerateResponse extracts the task ID from the VolcEngine response.
// VolcEngine video generation is always async.
func (a *VolcEngineVideoAdapter) ParseGenerateResponse(raw json.RawMessage) (*VideoGenResponse, error) {
	var resp struct {
		ID       string `json:"id"`
		VideoURL string `json:"video_url"`
		Content  *struct {
			VideoURL string `json:"video_url"`
		} `json:"content"`
		Data *struct {
			VideoURL string `json:"video_url"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("volcengine video: unmarshal generate response: %w", err)
	}

	// Async: task ID
	if resp.ID != "" {
		return &VideoGenResponse{IsAsync: true, TaskID: resp.ID}, nil
	}

	// Sync fallback (unlikely for VolcEngine video)
	videoURL := resp.VideoURL
	if resp.Content != nil && resp.Content.VideoURL != "" {
		videoURL = resp.Content.VideoURL
	}
	if resp.Data != nil && resp.Data.VideoURL != "" {
		videoURL = resp.Data.VideoURL
	}
	if videoURL != "" {
		return &VideoGenResponse{IsAsync: false, VideoURL: videoURL}, nil
	}

	return nil, fmt.Errorf("volcengine video: no task id in response")
}

// BuildPollRequest constructs the GET request to poll a VolcEngine video task.
func (a *VolcEngineVideoAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/api/v3", "/contents/generations/tasks/"+taskID)

	return &ProviderRequest{
		URL:    endpoint,
		Method: "GET",
		Headers: map[string]string{
			"Authorization": "Bearer " + config.APIKey,
		},
	}, nil
}

// ParsePollResponse maps VolcEngine status strings to the canonical set:
//
//	succeeded → "completed"
//	failed    → "failed"
//	other     → "processing"
func (a *VolcEngineVideoAdapter) ParsePollResponse(raw json.RawMessage) (*VideoPollResponse, error) {
	var resp struct {
		Status   string `json:"status"`
		VideoURL string `json:"video_url"`
		Content  *struct {
			VideoURL string `json:"video_url"`
		} `json:"content"`
		Data *struct {
			VideoURL string `json:"video_url"`
		} `json:"data"`
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("volcengine video: unmarshal poll response: %w", err)
	}

	result := &VideoPollResponse{}

	switch resp.Status {
	case "succeeded", "success":
		result.Status = "completed"
		// Try multiple response body locations for the video URL
		videoURL := resp.VideoURL
		if resp.Content != nil && resp.Content.VideoURL != "" {
			videoURL = resp.Content.VideoURL
		}
		if resp.Data != nil && resp.Data.VideoURL != "" {
			videoURL = resp.Data.VideoURL
		}
		result.VideoURL = videoURL
	case "failed", "error":
		result.Status = "failed"
		result.Error = firstNonEmpty(resp.Error.Message, "volcengine video generation failed")
	default:
		result.Status = normalizePollStatus(resp.Status)
	}

	return result, nil
}

// clampDuration constrains a duration value to [minDur, maxDur].
// If the input d is zero or negative, defVal is returned.
func clampDuration(d, minDur, maxDur, defVal int) int {
	if d <= 0 {
		return defVal
	}
	if d < minDur {
		return minDur
	}
	if d > maxDur {
		return maxDur
	}
	return d
}
