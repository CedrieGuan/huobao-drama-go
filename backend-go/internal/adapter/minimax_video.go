package adapter

import (
	"encoding/json"
	"fmt"
)

// MiniMaxVideoAdapter implements VideoProviderAdapter for MiniMax video generation.
//
// API style: POST /v1/video_generation with OpenAI Chat Completions content[] array format.
// Prompt includes --ratio and --dur tags. Three reference modes are supported:
// single, first_last, and multiple.
//
// Corresponds to TS: backend/src/services/adapters/minimax-video.ts
type MiniMaxVideoAdapter struct{}

func init() {
	RegisterVideoAdapter("minimax", &MiniMaxVideoAdapter{})
}

func (a *MiniMaxVideoAdapter) Provider() string { return "minimax" }

func (a *MiniMaxVideoAdapter) BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error) {
	url := JoinProviderURL(config.BaseURL, "/v1", "/video_generation")

	// Build prompt text with --ratio and --dur tags
	promptText := record.Prompt
	if promptText == "" {
		promptText = " "
	}
	ratio := record.AspectRatio
	if ratio == "" {
		ratio = "16:9"
	}
	dur := record.Duration
	if dur <= 0 {
		dur = 5
	}
	promptText = fmt.Sprintf("%s  --ratio %s  --dur %d", promptText, ratio, dur)

	// Build content array (OpenAI Chat Completions format)
	content := []map[string]interface{}{
		{"type": "text", "text": promptText},
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
				"role":      "reference_image",
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
				"role":      "reference_image",
			})
		}
	}

	model := record.Model
	if model == "" {
		model = config.Model
	}

	body := map[string]interface{}{
		"model":   model,
		"content": content,
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
		TaskID   string `json:"task_id"`
		ID       string `json:"id"`
		VideoURL string `json:"video_url"`
		Data     *struct {
			ID       string `json:"id"`
			VideoURL string `json:"video_url"`
		} `json:"data"`
		Content *struct {
			VideoURL string `json:"video_url"`
		} `json:"content"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("minimax video: parse generate response: %w", err)
	}

	// Async mode: task_id found at top level or nested in data
	taskID := firstNonEmpty(resp.TaskID, resp.ID)
	if resp.Data != nil {
		taskID = firstNonEmpty(taskID, resp.Data.ID)
	}
	if taskID != "" {
		return &VideoGenResponse{IsAsync: true, TaskID: taskID}, nil
	}

	// Sync mode: video_url found at various locations
	videoURL := resp.VideoURL
	if resp.Data != nil && resp.Data.VideoURL != "" {
		videoURL = resp.Data.VideoURL
	}
	if resp.Content != nil && resp.Content.VideoURL != "" {
		videoURL = resp.Content.VideoURL
	}
	if videoURL != "" {
		return &VideoGenResponse{IsAsync: false, VideoURL: videoURL}, nil
	}

	return nil, fmt.Errorf("minimax video: no task_id or video_url in response")
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
		Status   string `json:"status"`
		State    string `json:"state"`
		ErrorMsg string `json:"error_msg"`
		Error    string `json:"error"`
		VideoURL string `json:"video_url"`
		Data     *struct {
			Status   string `json:"status"`
			VideoURL string `json:"video_url"`
		} `json:"data"`
		Content *struct {
			VideoURL string `json:"video_url"`
		} `json:"content"`
	}
	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("minimax video: parse poll response: %w", err)
	}

	// Normalize status from top level or nested data
	status := firstNonEmpty(resp.Status, resp.State)
	if resp.Data != nil && resp.Data.Status != "" {
		status = resp.Data.Status
	}

	result := &VideoPollResponse{}

	switch {
	case status == "completed" || status == "succeeded" || status == "success" || status == "Done":
		result.Status = "completed"
		result.VideoURL = firstNonEmpty(
			resp.VideoURL,
			func() string {
				if resp.Data != nil {
					return resp.Data.VideoURL
				}
				return ""
			}(),
			func() string {
				if resp.Content != nil {
					return resp.Content.VideoURL
				}
				return ""
			}(),
		)
	case status == "failed" || status == "error":
		result.Status = "failed"
		result.Error = firstNonEmpty(resp.ErrorMsg, resp.Error, "video generation failed")
	default:
		result.Status = normalizePollStatus(status)
	}

	return result, nil
}
