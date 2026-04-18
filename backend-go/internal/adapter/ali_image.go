// Package adapter implements the Alibaba Cloud (DashScope) image generation adapter.
//
// Corresponding TypeScript source:
//
//	backend/src/services/adapters/ali-image.ts
//
// Key characteristics:
//   - POST /api/v1/services/aigc/image-generation/generation
//   - DashScope async mode via X-DashScope-Async: enable header
//   - Default model: wan2.6-t2i
//   - Size is normalized via aspect ratio buckets (not pixel-exact)
//   - Request body uses input.messages format with user message
//   - Poll endpoint: GET /api/v1/tasks/{taskId}
//   - Status mapping: PENDING / RUNNING → SUCCEEDED / FAILED
package adapter

import (
	"encoding/json"
	"fmt"
	"math/rand"
)

// AliImageAdapter implements ImageProviderAdapter for Alibaba Cloud DashScope.
type AliImageAdapter struct{}

func init() {
	RegisterImageAdapter("ali", &AliImageAdapter{})
}

func (a *AliImageAdapter) Provider() string { return "ali" }

// BuildGenerateRequest constructs the HTTP request for Ali DashScope image generation.
//
// The request uses the DashScope input.messages format. Size is normalized to
// Ali-specific dimension buckets based on aspect ratio, and the X-DashScope-Async
// header forces asynchronous task creation.
func (a *AliImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/api/v1", "/services/aigc/image-generation/generation")

	model := record.Model
	if model == "" {
		model = "wan2.6-t2i"
	}

	aliSize := aliNormalizeSize(record.Size)

	parameters := map[string]interface{}{
		"size":            aliSize,
		"n":               1,
		"negative_prompt": "",
		"prompt_extend":   true,
		"watermark":       false,
	}

	// Seed: omit when reference images are provided
	if len(record.ReferenceImages) == 0 {
		parameters["seed"] = rand.Int63()
	}

	// Reference images
	if len(record.ReferenceImages) > 0 {
		parameters["ref_images"] = record.ReferenceImages
	}

	body := map[string]interface{}{
		"model": model,
		"input": map[string]interface{}{
			"messages": []map[string]interface{}{
				{
					"role": "user",
					"content": []map[string]interface{}{
						{"text": record.Prompt},
					},
				},
			},
		},
		"parameters": parameters,
	}

	return &ProviderRequest{
		URL:    endpoint,
		Method: "POST",
		Headers: map[string]string{
			"Authorization":     "Bearer " + config.APIKey,
			"Content-Type":      "application/json",
			"X-DashScope-Async": "enable",
		},
		Body: body,
	}, nil
}

// ParseGenerateResponse determines whether the response is sync or async.
//
// Async mode: output.task_status == "PENDING" and output.task_id present
// Sync mode: output.choices[0].message.content[0].image present
func (a *AliImageAdapter) ParseGenerateResponse(raw json.RawMessage) (*ImageGenResponse, error) {
	var resp struct {
		Output struct {
			TaskID     string `json:"task_id"`
			TaskStatus string `json:"task_status"`
			Choices    []struct {
				Message struct {
					Content []struct {
						Image string `json:"image"`
					} `json:"content"`
				} `json:"message"`
			} `json:"choices"`
		} `json:"output"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("ali image: unmarshal response: %w", err)
	}

	// Async mode: DashScope returns PENDING with task_id
	if resp.Output.TaskID != "" {
		return &ImageGenResponse{
			IsAsync: true,
			TaskID:  resp.Output.TaskID,
		}, nil
	}

	// Sync mode: direct result in choices
	if len(resp.Output.Choices) > 0 &&
		len(resp.Output.Choices[0].Message.Content) > 0 &&
		resp.Output.Choices[0].Message.Content[0].Image != "" {
		return &ImageGenResponse{
			IsAsync:  false,
			ImageURL: resp.Output.Choices[0].Message.Content[0].Image,
		}, nil
	}

	return nil, fmt.Errorf("ali image: no task_id or results in response")
}

// BuildPollRequest builds the GET request to poll an async Ali DashScope task.
func (a *AliImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
	endpoint := JoinProviderURL(config.BaseURL, "/api/v1", "/tasks/"+taskID)

	return &ProviderRequest{
		URL:    endpoint,
		Method: "GET",
		Headers: map[string]string{
			"Authorization": "Bearer " + config.APIKey,
		},
	}, nil
}

// ParsePollResponse maps Ali DashScope task statuses to the canonical set:
//
//	SUCCEEDED  → "completed"
//	FAILED     → "failed"
//	PENDING    → "processing"
//	RUNNING    → "processing"
func (a *AliImageAdapter) ParsePollResponse(raw json.RawMessage) (*ImagePollResponse, error) {
	var resp struct {
		Output struct {
			TaskStatus string `json:"task_status"`
			Choices    []struct {
				Message struct {
					Content []struct {
						Image string `json:"image"`
					} `json:"content"`
				} `json:"message"`
			} `json:"choices"`
		} `json:"output"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("ali image poll: unmarshal: %w", err)
	}

	result := &ImagePollResponse{}

	switch resp.Output.TaskStatus {
	case "SUCCEEDED":
		result.Status = "completed"
		if len(resp.Output.Choices) > 0 &&
			len(resp.Output.Choices[0].Message.Content) > 0 {
			result.ImageURL = resp.Output.Choices[0].Message.Content[0].Image
		}
	case "FAILED":
		result.Status = "failed"
		result.Error = firstNonEmpty(resp.Message, "ali image generation failed")
	case "PENDING", "RUNNING":
		result.Status = "processing"
	default:
		result.Status = "pending"
	}

	return result, nil
}

// ExtractImageBase64 returns nil — Ali DashScope returns URLs, not base64 data.
func (a *AliImageAdapter) ExtractImageBase64(_ json.RawMessage) (*Base64Image, error) {
	return nil, nil
}

// aliNormalizeSize converts a standard size string (e.g. "1920x1080") to an
// Ali DashScope-compatible size string using aspect ratio buckets.
//
// Mapping rules (matching TS normalizeSize):
//
//	aspect > 1.7  → "1696*960"  (landscape / 16:9)
//	aspect < 0.8  → "960*1696"  (portrait / 9:16)
//	otherwise     → "1280*1280" (square / 1:1)
//
// Returns "1280*1280" if the input is empty or unparseable.
func aliNormalizeSize(size string) string {
	w, h := parseSize(size, 0, 0)
	if w == 0 || h == 0 {
		return "1280*1280"
	}

	aspect := float64(w) / float64(h)

	switch {
	case aspect > 1.7:
		return "1696*960"
	case aspect < 0.8:
		return "960*1696"
	default:
		return "1280*1280"
	}
}
