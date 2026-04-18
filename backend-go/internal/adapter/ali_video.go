// Package adapter implements the Alibaba Cloud (DashScope) video generation adapter.
//
// Corresponding TypeScript source:
//
//	backend/src/services/adapters/ali-video.ts
//
// Key characteristics:
//   - POST /api/v1/services/aigc/video-generation/video-synthesis
//   - Default model: wan2.6-i2v-flash
//   - DashScope async mode (responds with task_id + PENDING status)
//   - No X-DashScope-Async header needed (unlike the image adapter)
//   - Supports first frame + last frame reference images
//   - Resolution mapped from aspect ratio: 16:9 → 1080P, 9:16/1:1 → 720P
//   - Poll endpoint: GET /api/v1/tasks/{taskId}
//   - Status values: PENDING → RUNNING → SUCCEEDED / FAILED
package adapter

import (
	"encoding/json"
	"fmt"
	"math/rand"
)

// AliVideoAdapter implements VideoProviderAdapter for Alibaba Cloud DashScope
// video generation.
type AliVideoAdapter struct{}

func init() {
	RegisterVideoAdapter("ali", &AliVideoAdapter{})
}

func (a *AliVideoAdapter) Provider() string { return "ali" }

// BuildGenerateRequest constructs the HTTP request for Ali video generation.
//
// The request uses DashScope format with input.prompt, input.img_url,
// input.last_img_url, and parameters for resolution, duration, etc.
func (a *AliVideoAdapter) BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/api/v1", "/services/aigc/video-generation/video-synthesis")

	model := record.Model
	if model == "" {
		model = "wan2.6-i2v-flash"
	}

	// Map aspect ratio to Ali resolution string
	resolution := aliVideoResolution(record.AspectRatio)

	duration := record.Duration
	if duration <= 0 {
		duration = 5
	}

	input := map[string]interface{}{
		"prompt": record.Prompt,
	}

	// Reference images: first frame (also used as single reference)
	if record.ImageURL != "" {
		input["img_url"] = record.ImageURL
	} else if record.FirstFrameURL != "" {
		input["img_url"] = record.FirstFrameURL
	}

	// Last frame for first_last reference mode
	if record.LastFrameURL != "" {
		input["last_img_url"] = record.LastFrameURL
	}

	parameters := map[string]interface{}{
		"resolution": resolution,
		"duration":   duration,
		"watermark":  false,
		"seed":       rand.Int63(),
	}

	body := map[string]interface{}{
		"model":      model,
		"input":      input,
		"parameters": parameters,
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

// ParseGenerateResponse determines whether the response is sync or async.
//
// Async: output.task_status is "PENDING" and output.task_id is present.
// Sync: output.video_url is present directly.
func (a *AliVideoAdapter) ParseGenerateResponse(raw json.RawMessage) (*VideoGenResponse, error) {
	var resp struct {
		Output struct {
			TaskID     string `json:"task_id"`
			TaskStatus string `json:"task_status"`
			VideoURL   string `json:"video_url"`
		} `json:"output"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("ali video: unmarshal response: %w", err)
	}

	// Sync mode: video_url returned directly
	if resp.Output.VideoURL != "" {
		return &VideoGenResponse{
			IsAsync:  false,
			VideoURL: resp.Output.VideoURL,
		}, nil
	}

	// Async mode: task_id with PENDING status
	if resp.Output.TaskID != "" {
		return &VideoGenResponse{
			IsAsync: true,
			TaskID:  resp.Output.TaskID,
		}, nil
	}

	return nil, fmt.Errorf("ali video: no task_id or video_url in response")
}

// BuildPollRequest builds the GET request to poll an async Ali video task.
func (a *AliVideoAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/api/v1", "/tasks/"+taskID)

	return &ProviderRequest{
		URL:    endpoint,
		Method: "GET",
		Headers: map[string]string{
			"Authorization": "Bearer " + config.APIKey,
		},
	}, nil
}

// ParsePollResponse maps DashScope task_status values to the canonical set:
//
//	SUCCEEDED → "completed"
//	FAILED    → "failed"
//	PENDING/RUNNING → "processing"
//	other     → "pending"
func (a *AliVideoAdapter) ParsePollResponse(raw json.RawMessage) (*VideoPollResponse, error) {
	var resp struct {
		Output struct {
			TaskStatus string `json:"task_status"`
			VideoURL   string `json:"video_url"`
		} `json:"output"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("ali video poll: unmarshal: %w", err)
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
	case "PENDING", "RUNNING":
		result.Status = "processing"
	default:
		result.Status = "pending"
	}

	return result, nil
}

// aliVideoResolution maps an aspect ratio string to Ali's resolution parameter.
//
//	"9:16" or "1:1" → "720P"
//	"16:9" (default) → "1080P"
func aliVideoResolution(aspectRatio string) string {
	switch aspectRatio {
	case "9:16", "1:1":
		return "720P"
	default:
		return "1080P"
	}
}
