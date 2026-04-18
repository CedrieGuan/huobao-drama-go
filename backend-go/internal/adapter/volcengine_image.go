// Package adapter implements the VolcEngine (ByteDance) image generation adapter.
//
// Corresponding TypeScript source:
//
//	backend/src/services/adapters/volcengine-image.ts
//
// Key characteristics:
//   - POST /api/v3/images/generations
//   - Default model: doubao-seedream-5-0-lite
//   - Size is split into separate width/height fields
//   - Supports sync (data[0].url) and async (task_id/id) modes
//   - Poll: GET /api/v3/images/generations/{taskId}
//   - No base64 support
package adapter

import (
	"encoding/json"
	"fmt"
	"strings"
)

// VolcEngineImageAdapter implements ImageProviderAdapter for VolcEngine (ByteDance).
type VolcEngineImageAdapter struct{}

func init() {
	RegisterImageAdapter("volcengine", &VolcEngineImageAdapter{})
}

func (a *VolcEngineImageAdapter) Provider() string { return "volcengine" }

// BuildGenerateRequest constructs the HTTP request for VolcEngine image generation.
// The size string is parsed into separate width and height integer fields.
func (a *VolcEngineImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/api/v3", "/images/generations")

	model := record.Model
	if model == "" {
		model = config.Model
	}
	if model == "" {
		model = "doubao-seedream-5-0-lite"
	}

	width, height := parseSize(record.Size, 1024, 1024)

	body := map[string]interface{}{
		"model":  model,
		"prompt": record.Prompt,
		"width":  width,
		"height": height,
	}

	// Reference images
	if len(record.ReferenceImages) > 0 {
		body["reference_images"] = record.ReferenceImages
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
// Async mode: task_id or id present → { IsAsync: true, TaskID: ... }
// Sync mode: data[0].url or top-level url present → { IsAsync: false, ImageURL: ... }
func (a *VolcEngineImageAdapter) ParseGenerateResponse(raw json.RawMessage) (*ImageGenResponse, error) {
	var resp struct {
		TaskID string `json:"task_id"`
		ID     string `json:"id"`
		URL    string `json:"url"`
		Data   []struct {
			URL string `json:"url"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("volcengine image: unmarshal: %w", err)
	}

	// Async: task_id or id field present
	taskID := firstNonEmpty(resp.TaskID, resp.ID)
	if taskID != "" {
		return &ImageGenResponse{
			IsAsync: true,
			TaskID:  taskID,
		}, nil
	}

	// Sync: try data[0].url first, then top-level url
	if len(resp.Data) > 0 && resp.Data[0].URL != "" {
		return &ImageGenResponse{
			IsAsync:  false,
			ImageURL: resp.Data[0].URL,
		}, nil
	}

	if resp.URL != "" {
		return &ImageGenResponse{
			IsAsync:  false,
			ImageURL: resp.URL,
		}, nil
	}

	return nil, fmt.Errorf("volcengine image: no url or task_id in response")
}

// BuildPollRequest builds the GET request to poll an async image task.
func (a *VolcEngineImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/api/v3", "/images/generations/"+taskID)

	return &ProviderRequest{
		URL:    endpoint,
		Method: "GET",
		Headers: map[string]string{
			"Authorization": "Bearer " + config.APIKey,
		},
	}, nil
}

// ParsePollResponse maps VolcEngine status strings to the canonical set.
//
// Status values: "succeeded" → completed, "failed" → failed, else → processing.
func (a *VolcEngineImageAdapter) ParsePollResponse(raw json.RawMessage) (*ImagePollResponse, error) {
	var resp struct {
		Status   string `json:"status"`
		ImageURL string `json:"image_url"`
		Data     []struct {
			URL string `json:"url"`
		} `json:"data"`
		Error struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("volcengine image poll: unmarshal: %w", err)
	}

	result := &ImagePollResponse{}

	switch strings.ToLower(resp.Status) {
	case "succeeded", "success":
		result.Status = "completed"
		// Image URL may be at data[0].url or image_url
		if len(resp.Data) > 0 && resp.Data[0].URL != "" {
			result.ImageURL = resp.Data[0].URL
		} else {
			result.ImageURL = resp.ImageURL
		}
	case "failed", "error":
		result.Status = "failed"
		result.Error = firstNonEmpty(resp.Error.Message, "volcengine image generation failed")
	default:
		result.Status = normalizePollStatus(resp.Status)
	}

	return result, nil
}

// ExtractImageBase64 returns nil — VolcEngine always provides URLs, not base64 data.
func (a *VolcEngineImageAdapter) ExtractImageBase64(_ json.RawMessage) (*Base64Image, error) {
	return nil, nil
}
