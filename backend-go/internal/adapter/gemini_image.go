// Package adapter implements the Google Gemini image generation adapter.
//
// Corresponding TypeScript source:
//
//	backend/src/services/adapters/gemini-image.ts
//
// Key characteristics:
//   - Google REST API format: contents[].parts[]
//   - Model name embedded in URL path: /models/{model}:generateContent
//   - Dual authentication: ?key= query param + x-goog-api-key header + Authorization: Bearer
//   - Returns base64-encoded images via inlineData.data (no URL)
//   - Size is converted to aspectRatio (via GCD) and imageSize (512/1K/2K/4K)
//   - Reference images passed as inline_data parts (data: URI parsed)
//   - Synchronous only — no async polling
package adapter

import (
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
)

// GeminiImageAdapter implements ImageProviderAdapter for Google Gemini.
type GeminiImageAdapter struct{}

func init() {
	RegisterImageAdapter("gemini", &GeminiImageAdapter{})
}

func (a *GeminiImageAdapter) Provider() string { return "gemini" }

// BuildGenerateRequest constructs the HTTP request for Gemini image generation.
//
// The request uses the Google REST API style with the model name in the URL path,
// and generationConfig.responseModalities set to ["IMAGE", "TEXT"].
func (a *GeminiImageAdapter) BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error) {
	// Normalize model name: ensure "models/" prefix
	modelName := record.Model
	if modelName == "" {
		modelName = config.Model
	}
	if modelName == "" {
		modelName = "gemini-2.5-flash-image"
	}
	if !strings.HasPrefix(modelName, "models/") {
		modelName = "models/" + modelName
	}

	endpoint := fmt.Sprintf("/%s:generateContent", modelName)
	rawURL := JoinProviderURL(config.BaseURL, "/v1beta", endpoint)

	// Append API key as query parameter if not already present
	if !strings.Contains(rawURL, "key=") {
		parsed, err := url.Parse(rawURL)
		if err != nil {
			return nil, fmt.Errorf("gemini: parse url: %w", err)
		}
		q := parsed.Query()
		q.Set("key", config.APIKey)
		parsed.RawQuery = q.Encode()
		rawURL = parsed.String()
	}

	// Build parts array: reference images first, then text prompt
	parts := make([]map[string]interface{}, 0)

	for _, ref := range record.ReferenceImages {
		if strings.HasPrefix(ref, "data:") {
			mimeType, data := parseDataURL(ref)
			if mimeType != "" && data != "" {
				parts = append(parts, map[string]interface{}{
					"inline_data": map[string]interface{}{
						"mime_type": mimeType,
						"data":      data,
					},
				})
			}
		}
	}

	prompt := record.Prompt
	if prompt == "" {
		prompt = "Generate an image"
	}
	parts = append(parts, map[string]interface{}{
		"text": prompt,
	})

	// Parse size into aspectRatio and imageSize
	aspectRatio := geminiAspectRatio(record.Size)
	imageSize := geminiImageSize(record.Size)

	imageConfig := map[string]interface{}{}
	if aspectRatio != "" {
		imageConfig["aspectRatio"] = aspectRatio
	}
	if imageSize != "" {
		imageConfig["imageSize"] = imageSize
	}

	genConfig := map[string]interface{}{
		"responseModalities": []string{"IMAGE", "TEXT"},
	}
	if len(imageConfig) > 0 {
		genConfig["imageConfig"] = imageConfig
	}

	body := map[string]interface{}{
		"contents": []map[string]interface{}{
			{"parts": parts},
		},
		"generationConfig": genConfig,
	}

	return &ProviderRequest{
		URL:    rawURL,
		Method: "POST",
		Headers: map[string]string{
			"Content-Type":    "application/json",
			"x-goog-api-key":  config.APIKey,
			"Authorization":   "Bearer " + config.APIKey,
		},
		Body: body,
	}, nil
}

// ParseGenerateResponse parses the Gemini generateContent response.
//
// Gemini returns results synchronously. Images are base64-encoded in
// candidates[].content.parts[].inlineData.data. It also checks finishReason
// for early termination.
func (a *GeminiImageAdapter) ParseGenerateResponse(raw json.RawMessage) (*ImageGenResponse, error) {
	var resp struct {
		Candidates []struct {
			FinishReason string `json:"finishReason"`
			FinishMessage string `json:"finishMessage"`
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
		TaskID string `json:"task_id"`
		ID     string `json:"id"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}

	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, fmt.Errorf("gemini: unmarshal response: %w", err)
	}

	// Check for API-level error
	if resp.Error != nil && resp.Error.Message != "" {
		return nil, fmt.Errorf("gemini: %s", resp.Error.Message)
	}

	// Check finishReason for non-standard stops
	if len(resp.Candidates) > 0 {
		reason := resp.Candidates[0].FinishReason
		if reason != "" && reason != "STOP" && reason != "MAX_TOKENS" {
			msg := resp.Candidates[0].FinishMessage
			if msg == "" {
				msg = fmt.Sprintf("Gemini generation stopped: %s", reason)
			}
			return nil, fmt.Errorf("gemini: %s", msg)
		}
	}

	// Check for inline image data (sync base64 result)
	b64, _ := a.ExtractImageBase64(raw)
	if b64 != nil {
		return &ImageGenResponse{IsAsync: false}, nil
	}

	// Check for URL-based result
	imgURL := a.extractImageURL(raw)
	if imgURL != "" {
		return &ImageGenResponse{IsAsync: false, ImageURL: imgURL}, nil
	}

	// Async fallback (unlikely for Gemini but handle gracefully)
	taskID := firstNonEmpty(resp.TaskID, resp.ID)
	if taskID != "" {
		return &ImageGenResponse{IsAsync: true, TaskID: taskID}, nil
	}

	return nil, fmt.Errorf("gemini: no image data in response")
}

// BuildPollRequest returns an error — Gemini is synchronous and does not support polling.
func (a *GeminiImageAdapter) BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error) {
	// Gemini doesn't normally support polling, but build a minimal request
	// in case the API evolves to support async tasks.
	endpoint := fmt.Sprintf("/%s", taskID)
	rawURL := JoinProviderURL(config.BaseURL, "/v1beta", endpoint)

	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, fmt.Errorf("gemini: parse poll url: %w", err)
	}
	q := parsed.Query()
	q.Set("key", config.APIKey)
	parsed.RawQuery = q.Encode()

	return &ProviderRequest{
		URL:    parsed.String(),
		Method: "GET",
		Headers: map[string]string{
			"x-goog-api-key": config.APIKey,
			"Authorization":  "Bearer " + config.APIKey,
		},
	}, nil
}

// ParsePollResponse parses a poll response. Gemini is synchronous, so this
// returns completed status if any image data is found.
func (a *GeminiImageAdapter) ParsePollResponse(raw json.RawMessage) (*ImagePollResponse, error) {
	// Gemini is synchronous; if we end up here, treat as completed
	b64, _ := a.ExtractImageBase64(raw)
	if b64 != nil {
		return &ImagePollResponse{Status: "completed"}, nil
	}
	return &ImagePollResponse{Status: "completed"}, nil
}

// ExtractImageBase64 extracts the base64-encoded image from the Gemini response.
// Checks both camelCase (inlineData) and snake_case (inline_data) field names.
func (a *GeminiImageAdapter) ExtractImageBase64(raw json.RawMessage) (*Base64Image, error) {
	var resp struct {
		Data []struct {
			B64JSON string `json:"b64_json"`
		} `json:"data"`
		Candidates []struct {
			Content struct {
				Parts []struct {
					InlineData *struct {
						MimeType string `json:"mimeType"`
						Data     string `json:"data"`
					} `json:"inlineData"`
					InlineDataSnake *struct {
						MimeType string `json:"mime_type"`
						Data     string `json:"data"`
					} `json:"inline_data"`
				} `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
	}

	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, nil
	}

	// Check OpenAI-style b64_json first (unlikely for Gemini but safe)
	if len(resp.Data) > 0 && resp.Data[0].B64JSON != "" {
		return &Base64Image{
			Data:     resp.Data[0].B64JSON,
			MimeType: "image/png",
		}, nil
	}

	// Check candidates[].content.parts[].inlineData / inline_data
	for _, candidate := range resp.Candidates {
		for _, part := range candidate.Content.Parts {
			if part.InlineData != nil && part.InlineData.Data != "" {
				mimeType := part.InlineData.MimeType
				if mimeType == "" {
					mimeType = "image/png"
				}
				return &Base64Image{
					Data:     part.InlineData.Data,
					MimeType: mimeType,
				}, nil
			}
			if part.InlineDataSnake != nil && part.InlineDataSnake.Data != "" {
				mimeType := part.InlineDataSnake.MimeType
				if mimeType == "" {
					mimeType = "image/png"
				}
				return &Base64Image{
					Data:     part.InlineDataSnake.Data,
					MimeType: mimeType,
				}, nil
			}
		}
	}

	return nil, nil
}

// extractImageURL tries to extract a URL from the response body (non-standard for Gemini).
func (a *GeminiImageAdapter) extractImageURL(raw json.RawMessage) string {
	var resp struct {
		Data     []struct{ URL string `json:"url"` } `json:"data"`
		ImageURL string `json:"image_url"`
		URL      string `json:"url"`
	}
	if json.Unmarshal(raw, &resp) != nil {
		return ""
	}
	if len(resp.Data) > 0 && resp.Data[0].URL != "" {
		return resp.Data[0].URL
	}
	return firstNonEmpty(resp.ImageURL, resp.URL)
}

// geminiAspectRatio converts a size string like "1920x1080" to an aspect ratio
// string like "16:9" using GCD simplification. Returns "16:9" if parsing fails.
func geminiAspectRatio(size string) string {
	w, h := parseSize(size, 0, 0)
	if w == 0 || h == 0 {
		return "16:9"
	}
	g := gcd(w, h)
	return fmt.Sprintf("%d:%d", w/g, h/g)
}

// geminiImageSize maps the width to a Gemini imageSize bucket:
//
//	< 512 → "512", < 1024 → "1K", < 2048 → "2K", ≥ 2048 → "4K"
//
// Returns "1K" if size is empty or unparseable.
func geminiImageSize(size string) string {
	w, _ := parseSize(size, 0, 0)
	if w <= 0 {
		return "1K"
	}
	switch {
	case w >= 2048:
		return "4K"
	case w >= 1024:
		return "2K"
	case w >= 512:
		return "1K"
	default:
		return "512"
	}
}

// parseDataURL splits a "data:mime/type;base64,XXXX" string into its MIME type
// and base64 data components. Returns empty strings if the input is not a valid
// data URL.
func parseDataURL(dataURL string) (mimeType, data string) {
	if !strings.HasPrefix(dataURL, "data:") {
		return "", dataURL
	}
	rest := dataURL[5:]
	idx := strings.Index(rest, ",")
	if idx == -1 {
		// No comma: treat the entire rest as MIME metadata,
		// return the original input as the data fallback.
		return rest, dataURL
	}
	meta := rest[:idx]
	data = rest[idx+1:]

	// Extract MIME type (everything before the first semicolon)
	if semiIdx := strings.Index(meta, ";"); semiIdx != -1 {
		mimeType = meta[:semiIdx]
	} else {
		mimeType = meta
	}
	return mimeType, data
}
