// Package adapter implements the MiniMax image generation adapter.
//
// Corresponding TypeScript source:
//
//	backend/src/services/adapters/minimax-image.ts
//
// Key characteristics:
//   - POST /v1/image_generation (sync or async)
//   - Async poll: GET /v1/image_generation/task/{taskId}
//   - Supports reference images via the "image" field
//   - aspect_ratio expressed as "W/H" (e.g. "16/9")
package adapter

import (
	"encoding/json"
	"fmt"
	"strings"
)

// MiniMaxImageAdapter implements ImageProviderAdapter for the MiniMax provider.
type MiniMaxImageAdapter struct{}

func init() {
	RegisterImageAdapter("minimax", &MiniMaxImageAdapter{})
}

func (a *MiniMaxImageAdapter) Provider() string { return "minimax" }

// BuildGenerateRequest constructs the HTTP request for MiniMax image generation.
// The request body follows the MiniMax API format with model, prompt, size, n,
// optional aspect_ratio, and optional reference images.
func (a *MiniMaxImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/v1", "/image_generation")

	model := record.Model
	if model == "" {
		model = config.Model
	}

	body := map[string]interface{}{
		"model":  model,
		"prompt": record.Prompt,
		"size":   record.Size,
		"n":      1,
	}

	// Reference images: record.ReferenceImages is already a []string
	// (normalised by the service layer). MiniMax expects them under "image".
	if len(record.ReferenceImages) > 0 {
		body["image"] = record.ReferenceImages
	}

	// aspect_ratio: derive from size string (e.g. "1920x1080" → "1920/1080")
	if record.Size != "" {
		parts := strings.SplitN(record.Size, "x", 2)
		if len(parts) == 2 && parts[0] != "" && parts[1] != "" {
			body["aspect_ratio"] = parts[0] + "/" + parts[1]
		}
	}

	return &ProviderRequest{
		URL:    endpoint,
		Method: "POST",
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Authorization": "Bearer " + config.APIKey,
		},
		Body: body,
	}, nil
}

// ParseGenerateResponse determines whether the response is sync or async.
//
// Async mode: task_id or id present → { IsAsync: true, TaskID: ... }
// Sync mode: data[0].url or url present → { IsAsync: false, ImageURL: ... }
func (a *MiniMaxImageAdapter) ParseGenerateResponse(raw json.RawMessage) (*ImageGenResponse, error) {
	// First, try the flat async format: { task_id, id }
	var flat struct {
		TaskID string `json:"task_id"`
		ID     string `json:"id"`
		URL    string `json:"url"`
	}
	if err := json.Unmarshal(raw, &flat); err != nil {
		return nil, fmt.Errorf("minimax image: unmarshal flat: %w", err)
	}

	// Async: task_id or id field present
	if flat.TaskID != "" || flat.ID != "" {
		return &ImageGenResponse{
			IsAsync: true,
			TaskID:  firstNonEmpty(flat.TaskID, flat.ID),
		}, nil
	}

	// Sync: try top-level url
	if flat.URL != "" {
		return &ImageGenResponse{
			IsAsync:  false,
			ImageURL: flat.URL,
		}, nil
	}

	// Sync: try data[0].url format
	var withData struct {
		Data []struct {
			URL string `json:"url"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &withData); err == nil && len(withData.Data) > 0 && withData.Data[0].URL != "" {
		return &ImageGenResponse{
			IsAsync:  false,
			ImageURL: withData.Data[0].URL,
		}, nil
	}

	return nil, fmt.Errorf("minimax image: no image_url or task_id in response")
}

// BuildPollRequest builds the GET request to poll an async image task.
func (a *MiniMaxImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/v1", "/image_generation/task/"+taskID)

	return &ProviderRequest{
		URL:    endpoint,
		Method: "GET",
		Headers: map[string]string{
			"Authorization": "Bearer " + config.APIKey,
		},
	}, nil
}

// ParsePollResponse maps MiniMax status strings to the canonical set:
//
//	completed/succeeded → "completed"
//	failed/error        → "failed"
//	anything else       → "processing"
func (a *MiniMaxImageAdapter) ParsePollResponse(raw json.RawMessage) (*ImagePollResponse, error) {
	// Try flat format first: { status, image_url, error_msg, error, state }
	var flat struct {
		Status   string `json:"status"`
		State    string `json:"state"`
		ImageURL string `json:"image_url"`
		URL      string `json:"url"`
		ErrorMsg string `json:"error_msg"`
		Error    string `json:"error"`
	}
	if err := json.Unmarshal(raw, &flat); err != nil {
		return nil, fmt.Errorf("minimax image poll: unmarshal: %w", err)
	}

	status := firstNonEmpty(flat.Status, flat.State)

	result := &ImagePollResponse{}

	switch status {
	case "completed", "succeeded", "success", "Done":
		result.Status = "completed"
		result.ImageURL = firstNonEmpty(flat.ImageURL, flat.URL)
	case "failed", "error", "Failed":
		result.Status = "failed"
		result.Error = firstNonEmpty(flat.ErrorMsg, flat.Error, "minimax image generation failed")
	default:
		// Could still be inside data wrapper
		if flat.ImageURL != "" || flat.URL != "" {
			// Has a URL but status not marked complete — still processing
			result.Status = "processing"
		} else {
			result.Status = firstNonEmpty(status, "processing")
		}
	}

	// Also try data.image_url / data.url if top-level fields are empty
	if result.ImageURL == "" {
		var withData struct {
			Data struct {
				ImageURL string `json:"image_url"`
				URL      string `json:"url"`
			} `json:"data"`
		}
		if json.Unmarshal(raw, &withData) == nil {
			url := firstNonEmpty(withData.Data.ImageURL, withData.Data.URL)
			if url != "" {
				result.ImageURL = url
				if result.Status != "failed" {
					result.Status = "completed"
				}
			}
		}
	}

	return result, nil
}

// ExtractImageBase64 returns nil — MiniMax always provides URLs, not base64 data.
func (a *MiniMaxImageAdapter) ExtractImageBase64(_ json.RawMessage) (*Base64Image, error) {
	return nil, nil
}
