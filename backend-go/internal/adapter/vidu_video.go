// Package adapter implements the Vidu video generation adapter.
//
// Corresponding TypeScript source:
//
//	backend/src/services/adapters/vidu-video.ts
//
// Key characteristics:
//   - POST /ent/v2/img2video (no required prefix in base URL)
//   - Authentication via "Authorization: Token {key}" (NOT Bearer)
//   - Default model: viduq3-turbo
//   - **No polling endpoint** — entirely Webhook-driven
//   - BuildPollRequest returns a placeholder URL; real status comes via callback
//   - ParseCallbackState is exported for use by the webhook handler
package adapter

import (
	"encoding/json"
	"fmt"
)

// ViduVideoAdapter implements VideoProviderAdapter for Vidu video generation.
// Vidu is webhook-only: after submitting a generation request, status updates
// arrive via an HTTP callback rather than through polling.
type ViduVideoAdapter struct{}

func init() {
	RegisterVideoAdapter("vidu", &ViduVideoAdapter{})
}

func (a *ViduVideoAdapter) Provider() string { return "vidu" }

// BuildGenerateRequest constructs the HTTP request for Vidu video generation.
//
// The request body includes the model, prompt, an images array (populated
// according to the reference mode), optional duration, and a resolution field
// mapped from the aspect ratio.
//
// Authentication uses the "Token" scheme (not Bearer).
func (a *ViduVideoAdapter) BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error) {
	// Vidu uses an empty required prefix — the full path is in the endpoint
	endpoint := JoinProviderURL(config.BaseURL, "", "/ent/v2/img2video")

	model := record.Model
	if model == "" {
		model = "viduq3-turbo"
	}

	body := map[string]interface{}{
		"model":  model,
		"prompt": record.Prompt,
	}

	// Build images array based on reference mode
	images := make([]string, 0)
	refMode := record.ReferenceMode
	if refMode == "" {
		refMode = "none"
	}

	switch refMode {
	case "single":
		if record.ImageURL != "" {
			images = append(images, record.ImageURL)
		}
	case "first_last":
		if record.FirstFrameURL != "" {
			images = append(images, record.FirstFrameURL)
		}
		if record.LastFrameURL != "" {
			images = append(images, record.LastFrameURL)
		}
	case "multiple":
		refs := parseJSONStringArray(record.ReferenceImageURLs)
		images = append(images, refs...)
	}

	if len(images) > 0 {
		body["images"] = images
	}

	// Optional duration
	if record.Duration > 0 {
		body["duration"] = record.Duration
	}

	// Map aspect ratio to Vidu resolution
	if record.AspectRatio != "" {
		body["resolution"] = viduResolution(record.AspectRatio)
	}

	return &ProviderRequest{
		URL:    endpoint,
		Method: "POST",
		Headers: map[string]string{
			"Authorization": "Token " + config.APIKey,
			"Content-Type":  "application/json",
		},
		Body: body,
	}, nil
}

// ParseGenerateResponse parses the initial Vidu response.
//
// Vidu returns a task_id for async tracking (the actual result arrives via
// webhook). A top-level video_url indicates an unlikely sync completion.
func (a *ViduVideoAdapter) ParseGenerateResponse(raw json.RawMessage) (*VideoGenResponse, error) {
	var resp struct {
		TaskID   string `json:"task_id"`
		VideoURL string `json:"video_url"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("vidu: unmarshal response: %w", err)
	}

	if resp.TaskID != "" {
		return &VideoGenResponse{IsAsync: true, TaskID: resp.TaskID}, nil
	}

	if resp.VideoURL != "" {
		return &VideoGenResponse{IsAsync: false, VideoURL: resp.VideoURL}, nil
	}

	return nil, fmt.Errorf("vidu: no task_id or video_url in response")
}

// BuildPollRequest returns a placeholder request — Vidu does not expose a
// polling endpoint. The caller should not invoke this; real status updates
// arrive through the Webhook callback handled by ParseCallbackState.
func (a *ViduVideoAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
	return &ProviderRequest{
		URL:    "vidu://no-polling-endpoint/" + taskID,
		Method: "GET",
		Headers: map[string]string{
			"Authorization": "Token " + config.APIKey,
		},
	}, nil
}

// ParsePollResponse always returns "processing" — Vidu status is updated
// exclusively through Webhook callbacks, not polling.
func (a *ViduVideoAdapter) ParsePollResponse(_ json.RawMessage) (*VideoPollResponse, error) {
	return &VideoPollResponse{Status: "processing"}, nil
}

// ParseCallbackState interprets a Vidu Webhook callback body and returns the
// canonical status and video URL. This function is called by the webhook
// handler, not by the polling machinery.
//
// Expected callback JSON:
//
//	{ "state": "success", "video_url": "https://..." }
//	{ "state": "failed" }
//
// State mapping:
//   - "success" → "completed" (with VideoURL)
//   - "failed"  → "failed"
//   - anything else → "failed" with "Unknown state" error
func ParseCallbackState(raw json.RawMessage) (*VideoPollResponse, error) {
	var cb struct {
		State    string `json:"state"`
		VideoURL string `json:"video_url"`
	}
	if err := json.Unmarshal(raw, &cb); err != nil {
		return nil, fmt.Errorf("vidu callback: unmarshal: %w", err)
	}

	switch cb.State {
	case "success":
		return &VideoPollResponse{
			Status:   "completed",
			VideoURL: cb.VideoURL,
		}, nil
	case "failed":
		return &VideoPollResponse{
			Status: "failed",
			Error:  "vidu video generation failed",
		}, nil
	default:
		return &VideoPollResponse{
			Status: "failed",
			Error:  fmt.Sprintf("vidu: unknown callback state: %s", cb.State),
		}, nil
	}
}

// viduResolution maps an aspect ratio string to a Vidu resolution value.
// Vidu currently supports "720p" for all standard aspect ratios.
func viduResolution(aspectRatio string) string {
	switch aspectRatio {
	case "16:9", "9:16", "1:1":
		return "720p"
	default:
		return "720p"
	}
}
