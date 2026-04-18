// Package adapter provides AI provider adapter interfaces and implementations
// for image generation, video generation, and TTS services.
package adapter

import "encoding/json"

// ========== Common Types ==========

// ProviderRequest is the unified HTTP request structure sent to AI providers.
type ProviderRequest struct {
	URL     string            `json:"url"`
	Method  string            `json:"method"`
	Headers map[string]string `json:"headers"`
	Body    interface{}       `json:"body,omitempty"`
}

// AIConfig holds the AI service configuration retrieved from the database.
type AIConfig struct {
	Provider string
	BaseURL  string
	APIKey   string
	Model    string
}

// ImageGenRecord represents an image generation record read from the database.
type ImageGenRecord struct {
	ID              int64
	Model           string
	Prompt          string
	Size            string
	FrameType       string
	ReferenceImages []string // normalized reference image list
}

// VideoGenRecord represents a video generation record read from the database.
type VideoGenRecord struct {
	ID                 int64
	Model              string
	Prompt             string
	ReferenceMode      string // none / single / first_last / multiple
	ImageURL           string // normalized
	FirstFrameURL      string // normalized
	LastFrameURL       string // normalized
	ReferenceImageURLs string // JSON array string, normalized
	Duration           int
	AspectRatio        string
}

// ========== Response Types ==========

// ImageGenResponse is the parsed result from an image generation API call.
type ImageGenResponse struct {
	IsAsync  bool
	TaskID   string
	ImageURL string
}

// ImagePollResponse is the parsed result from an image generation poll request.
type ImagePollResponse struct {
	Status   string // pending / processing / completed / failed
	ImageURL string
	Error    string
}

// VideoGenResponse is the parsed result from a video generation API call.
type VideoGenResponse struct {
	IsAsync  bool
	TaskID   string
	VideoURL string
}

// VideoPollResponse is the parsed result from a video generation poll request.
type VideoPollResponse struct {
	Status   string // pending / processing / completed / failed
	VideoURL string
	Error    string
}

// Base64Image holds a base64-encoded image and its MIME type.
type Base64Image struct {
	Data     string
	MimeType string
}

// TTSResponse is the parsed result from a TTS API call.
type TTSResponse struct {
	AudioHex    string // hex-encoded audio data
	AudioLength int    // audio duration in milliseconds
	SampleRate  int
	Bitrate     int
	Format      string // mp3 / wav
	Channel     int
}

// ========== Adapter Interfaces ==========

// ImageProviderAdapter is the interface for image generation provider adapters.
type ImageProviderAdapter interface {
	// Provider returns the provider identifier string.
	Provider() string

	// BuildGenerateRequest builds the HTTP request for image generation.
	BuildGenerateRequest(config *AIConfig, record *ImageGenRecord) (*ProviderRequest, error)

	// ParseGenerateResponse parses the generation response and determines sync/async mode.
	ParseGenerateResponse(body json.RawMessage) (*ImageGenResponse, error)

	// BuildPollRequest builds the HTTP request for polling an async task.
	BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error)

	// ParsePollResponse parses the poll response for task status.
	ParsePollResponse(body json.RawMessage) (*ImagePollResponse, error)

	// ExtractImageBase64 extracts base64 image data from the response body.
	// Returns nil if the provider returns URLs instead of base64 data.
	ExtractImageBase64(body json.RawMessage) (*Base64Image, error)
}

// VideoProviderAdapter is the interface for video generation provider adapters.
type VideoProviderAdapter interface {
	// Provider returns the provider identifier string.
	Provider() string

	// BuildGenerateRequest builds the HTTP request for video generation.
	BuildGenerateRequest(config *AIConfig, record *VideoGenRecord) (*ProviderRequest, error)

	// ParseGenerateResponse parses the generation response and determines sync/async mode.
	ParseGenerateResponse(body json.RawMessage) (*VideoGenResponse, error)

	// BuildPollRequest builds the HTTP request for polling an async task.
	BuildPollRequest(config *AIConfig, taskID string) (*ProviderRequest, error)

	// ParsePollResponse parses the poll response for task status.
	ParsePollResponse(body json.RawMessage) (*VideoPollResponse, error)
}

// TTSProviderAdapter is the interface for TTS (text-to-speech) provider adapters.
type TTSProviderAdapter interface {
	// Provider returns the provider identifier string.
	Provider() string

	// BuildGenerateRequest builds the HTTP request for TTS generation.
	BuildGenerateRequest(config *AIConfig, params map[string]interface{}) (*ProviderRequest, error)

	// ParseResponse parses the TTS API response.
	ParseResponse(body json.RawMessage) (*TTSResponse, error)
}
