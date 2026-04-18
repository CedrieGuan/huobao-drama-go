// Package adapter implements the OpenAI (DALL-E) image generation adapter.
//
// Corresponding TypeScript source:
//
//	backend/src/services/adapters/openai-image.ts
//
// Key characteristics:
//   - POST /v1/images/generations
//   - Default model: dall-e-3
//   - Supports URL and b64_json response formats
//   - Synchronous by default; async task mode via task_id/id
//   - Chatfire reuses the same format
package adapter

import (
	"encoding/json"
	"fmt"
)

// OpenAIImageAdapter implements ImageProviderAdapter for OpenAI DALL-E and
// compatible providers (e.g. Chatfire).
type OpenAIImageAdapter struct{}

func init() {
	RegisterImageAdapter("openai", &OpenAIImageAdapter{})
}

func (a *OpenAIImageAdapter) Provider() string { return "openai" }

// BuildGenerateRequest constructs the HTTP request for OpenAI image generation.
// Default size is "1024x1024" and response_format is "url".
func (a *OpenAIImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/v1", "/images/generations")

	model := record.Model
	if model == "" {
		model = "dall-e-3"
	}

	size := record.Size
	if size == "" {
		size = "1024x1024"
	}

	body := map[string]interface{}{
		"model":           model,
		"prompt":          record.Prompt,
		"size":            size,
		"n":               1,
		"response_format": "url",
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
// Sync mode: data[0].url or data[0].b64_json present → { IsAsync: false }
func (a *OpenAIImageAdapter) ParseGenerateResponse(raw json.RawMessage) (*ImageGenResponse, error) {
	// Check flat async format first: { task_id, id }
	var flat struct {
		TaskID string `json:"task_id"`
		ID     string `json:"id"`
	}
	if err := json.Unmarshal(raw, &flat); err != nil {
		return nil, fmt.Errorf("openai image: unmarshal flat: %w", err)
	}

	if flat.TaskID != "" || flat.ID != "" {
		return &ImageGenResponse{
			IsAsync: true,
			TaskID:  firstNonEmpty(flat.TaskID, flat.ID),
		}, nil
	}

	// Sync mode: data[0].url or data[0].b64_json
	var withData struct {
		Data []struct {
			URL     string `json:"url"`
			B64JSON string `json:"b64_json"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &withData); err != nil {
		return nil, fmt.Errorf("openai image: unmarshal data: %w", err)
	}

	if len(withData.Data) == 0 {
		return nil, fmt.Errorf("openai image: no data in response")
	}

	item := withData.Data[0]
	if item.URL != "" {
		return &ImageGenResponse{
			IsAsync:  false,
			ImageURL: item.URL,
		}, nil
	}

	if item.B64JSON != "" {
		// Base64 mode — caller should use ExtractImageBase64 to retrieve data
		return &ImageGenResponse{IsAsync: false}, nil
	}

	return nil, fmt.Errorf("openai image: no url or b64_json in response")
}

// BuildPollRequest builds the GET request to poll an async image task.
func (a *OpenAIImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/v1", "/images/task/"+taskID)

	return &ProviderRequest{
		URL:    endpoint,
		Method: "GET",
		Headers: map[string]string{
			"Authorization": "Bearer " + config.APIKey,
		},
	}, nil
}

// ParsePollResponse maps OpenAI status strings to the canonical set.
func (a *OpenAIImageAdapter) ParsePollResponse(raw json.RawMessage) (*ImagePollResponse, error) {
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
		return nil, fmt.Errorf("openai image poll: unmarshal: %w", err)
	}

	result := &ImagePollResponse{}

	switch resp.Status {
	case "completed", "succeeded":
		result.Status = "completed"
		result.ImageURL = firstNonEmpty(resp.ImageURL, func() string {
			if len(resp.Data) > 0 {
				return resp.Data[0].URL
			}
			return ""
		}())
	case "failed", "error":
		result.Status = "failed"
		result.Error = firstNonEmpty(resp.Error.Message, "openai image generation failed")
	default:
		result.Status = normalizePollStatus(resp.Status)
	}

	return result, nil
}

// ExtractImageBase64 extracts base64 image data when response_format was "b64_json".
// Returns nil when the response contains URLs instead.
func (a *OpenAIImageAdapter) ExtractImageBase64(raw json.RawMessage) (*Base64Image, error) {
	var resp struct {
		Data []struct {
			B64JSON string `json:"b64_json"`
		} `json:"data"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("openai image base64: unmarshal: %w", err)
	}

	if len(resp.Data) > 0 && resp.Data[0].B64JSON != "" {
		return &Base64Image{
			Data:     resp.Data[0].B64JSON,
			MimeType: "image/png",
		}, nil
	}

	return nil, nil
}
