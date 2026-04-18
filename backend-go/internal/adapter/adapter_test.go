package adapter

import (
	"encoding/json"
	"strings"
	"testing"
)

// ========== Test Helpers ==========

func testAIConfig() *AIConfig {
	return &AIConfig{
		Provider: "test",
		BaseURL:  "https://api.example.com",
		APIKey:   "test-api-key",
		Model:    "test-model",
	}
}

func testImageRecord() *ImageGenRecord {
	return &ImageGenRecord{
		ID:              1,
		Model:           "test-img-model",
		Prompt:          "a beautiful sunset",
		Size:            "1920x1080",
		FrameType:       "landscape",
		ReferenceImages: []string{"https://ref.test/1.jpg"},
	}
}

func testVideoRecord() *VideoGenRecord {
	return &VideoGenRecord{
		ID:                 2,
		Model:              "test-vid-model",
		Prompt:             "a cat walking",
		ReferenceMode:      "single",
		ImageURL:           "https://ref.test/img.jpg",
		FirstFrameURL:      "https://ref.test/first.jpg",
		LastFrameURL:       "https://ref.test/last.jpg",
		ReferenceImageURLs: `["https://ref.test/a.jpg","https://ref.test/b.jpg"]`,
		Duration:           5,
		AspectRatio:        "16:9",
	}
}

func rawJSON(v interface{}) json.RawMessage {
	b, _ := json.Marshal(v)
	return b
}

// verifyBasicRequest checks common request properties.
func verifyBasicRequest(t *testing.T, req *ProviderRequest, wantMethod, authPrefix string) {
	t.Helper()
	if req.Method != wantMethod {
		t.Errorf("Method = %q, want %q", req.Method, wantMethod)
	}
	if authPrefix != "" {
		auth := req.Headers["Authorization"]
		if !strings.HasPrefix(auth, authPrefix) {
			t.Errorf("Authorization = %q, want prefix %q", auth, authPrefix)
		}
	}
}

// ========== MiniMax Image ==========

func TestMiniMaxImageAdapter_Provider(t *testing.T) {
	a := &MiniMaxImageAdapter{}
	if got := a.Provider(); got != "minimax" {
		t.Errorf("Provider() = %q, want %q", got, "minimax")
	}
}

func TestMiniMaxImageAdapter_BuildGenerateRequest(t *testing.T) {
	a := &MiniMaxImageAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), testImageRecord())
	if err != nil {
		t.Fatalf("BuildGenerateRequest error: %v", err)
	}
	verifyBasicRequest(t, req, "POST", "Bearer ")

	if !strings.Contains(req.URL, "/v1/image_generation") {
		t.Errorf("URL = %q, want to contain /v1/image_generation", req.URL)
	}

	body := req.Body.(map[string]interface{})
	if body["prompt"] != "a beautiful sunset" {
		t.Errorf("body.prompt = %v, want %q", body["prompt"], "a beautiful sunset")
	}
	if body["n"] != 1 {
		t.Errorf("body.n = %v, want 1", body["n"])
	}
	if body["aspect_ratio"] != "1920/1080" {
		t.Errorf("body.aspect_ratio = %v, want %q", body["aspect_ratio"], "1920/1080")
	}
	// Reference images should be under "image"
	if imgs, ok := body["image"].([]string); !ok || len(imgs) != 1 {
		t.Errorf("body.image = %v, want 1-element []string", body["image"])
	}
}

func TestMiniMaxImageAdapter_ParseGenerateResponse_Sync(t *testing.T) {
	a := &MiniMaxImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"data": []map[string]interface{}{
			{"url": "https://img.test/result.png"},
		},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("ParseGenerateResponse error: %v", err)
	}
	if got.IsAsync {
		t.Error("IsAsync = true, want false")
	}
	if got.ImageURL != "https://img.test/result.png" {
		t.Errorf("ImageURL = %q, want %q", got.ImageURL, "https://img.test/result.png")
	}
}

func TestMiniMaxImageAdapter_ParseGenerateResponse_Async(t *testing.T) {
	a := &MiniMaxImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"task_id": "task-123",
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("ParseGenerateResponse error: %v", err)
	}
	if !got.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if got.TaskID != "task-123" {
		t.Errorf("TaskID = %q, want %q", got.TaskID, "task-123")
	}
}

func TestMiniMaxImageAdapter_ParseGenerateResponse_ByDataURL(t *testing.T) {
	a := &MiniMaxImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"url": "https://img.test/top-level.png",
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("ParseGenerateResponse error: %v", err)
	}
	if got.IsAsync {
		t.Error("IsAsync = true, want false")
	}
	if got.ImageURL != "https://img.test/top-level.png" {
		t.Errorf("ImageURL = %q, want %q", got.ImageURL, "https://img.test/top-level.png")
	}
}

func TestMiniMaxImageAdapter_BuildPollRequest(t *testing.T) {
	a := &MiniMaxImageAdapter{}
	req, err := a.BuildPollRequest(testAIConfig(), "task-123")
	if err != nil {
		t.Fatalf("BuildPollRequest error: %v", err)
	}
	verifyBasicRequest(t, req, "GET", "Bearer ")
	if !strings.Contains(req.URL, "/v1/image_generation/task/task-123") {
		t.Errorf("URL = %q, want to contain /v1/image_generation/task/task-123", req.URL)
	}
}

func TestMiniMaxImageAdapter_ParsePollResponse(t *testing.T) {
	tests := []struct {
		name       string
		json       interface{}
		wantStatus string
		wantURL    string
		wantError  string
	}{
		{
			"completed",
			map[string]interface{}{"status": "completed", "image_url": "https://img.test/1.png"},
			"completed", "https://img.test/1.png", "",
		},
		{
			"success_alias",
			map[string]interface{}{"status": "success"},
			"completed", "", "",
		},
		{
			"failed",
			map[string]interface{}{"status": "failed", "error_msg": "bad request"},
			"failed", "", "bad request",
		},
		{
			"processing",
			map[string]interface{}{"status": "processing"},
			"processing", "", "",
		},
		{
			"data_wrapper",
			map[string]interface{}{
				"data": map[string]interface{}{
					"image_url": "https://img.test/wrapped.png",
				},
			},
			"completed", "https://img.test/wrapped.png", "",
		},
	}
	a := &MiniMaxImageAdapter{}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := a.ParsePollResponse(rawJSON(tt.json))
			if err != nil {
				t.Fatalf("ParsePollResponse error: %v", err)
			}
			if got.Status != tt.wantStatus {
				t.Errorf("Status = %q, want %q", got.Status, tt.wantStatus)
			}
			if got.ImageURL != tt.wantURL {
				t.Errorf("ImageURL = %q, want %q", got.ImageURL, tt.wantURL)
			}
			if got.Error != tt.wantError {
				t.Errorf("Error = %q, want %q", got.Error, tt.wantError)
			}
		})
	}
}

func TestMiniMaxImageAdapter_ExtractImageBase64(t *testing.T) {
	a := &MiniMaxImageAdapter{}
	got, err := a.ExtractImageBase64(nil)
	if err != nil {
		t.Fatalf("ExtractImageBase64 error: %v", err)
	}
	if got != nil {
		t.Error("ExtractImageBase64 = non-nil, want nil (MiniMax returns URLs)")
	}
}

func TestMiniMaxImageAdapter_ParseGenerateResponse_Error(t *testing.T) {
	a := &MiniMaxImageAdapter{}
	resp := rawJSON(map[string]interface{}{})
	_, err := a.ParseGenerateResponse(resp)
	if err == nil {
		t.Fatal("expected error for empty response")
	}
}

// ========== MiniMax Video ==========

func TestMiniMaxVideoAdapter_Provider(t *testing.T) {
	a := &MiniMaxVideoAdapter{}
	if got := a.Provider(); got != "minimax" {
		t.Errorf("Provider() = %q, want %q", got, "minimax")
	}
}

func TestMiniMaxVideoAdapter_BuildGenerateRequest(t *testing.T) {
	a := &MiniMaxVideoAdapter{}
	record := testVideoRecord()
	req, err := a.BuildGenerateRequest(testAIConfig(), record)
	if err != nil {
		t.Fatalf("BuildGenerateRequest error: %v", err)
	}
	verifyBasicRequest(t, req, "POST", "Bearer ")

	if !strings.Contains(req.URL, "/v1/video_generation") {
		t.Errorf("URL = %q, want to contain /v1/video_generation", req.URL)
	}

	body := req.Body.(map[string]interface{})
	content, ok := body["content"].([]map[string]interface{})
	if !ok {
		t.Fatalf("body.content type = %T, want []map[string]interface{}", body["content"])
	}
	if len(content) < 2 {
		t.Fatalf("len(content) = %d, want >= 2 (text + image)", len(content))
	}
	// First part: text with --ratio and --dur
	textPart := content[0]
	if textPart["type"] != "text" {
		t.Errorf("content[0].type = %v, want %q", textPart["type"], "text")
	}
	textStr, _ := textPart["text"].(string)
	if !strings.Contains(textStr, "--ratio 16:9") {
		t.Errorf("text = %q, want to contain --ratio 16:9", textStr)
	}
	if !strings.Contains(textStr, "--dur 5") {
		t.Errorf("text = %q, want to contain --dur 5", textStr)
	}
	// Second part: image_url (single mode)
	imgPart := content[1]
	if imgPart["type"] != "image_url" {
		t.Errorf("content[1].type = %v, want %q", imgPart["type"], "image_url")
	}
	if imgPart["role"] != "reference_image" {
		t.Errorf("content[1].role = %v, want %q", imgPart["role"], "reference_image")
	}
}

func TestMiniMaxVideoAdapter_BuildGenerateRequest_FirstLast(t *testing.T) {
	a := &MiniMaxVideoAdapter{}
	record := &VideoGenRecord{
		Prompt:        "test",
		ReferenceMode: "first_last",
		FirstFrameURL: "https://ref.test/first.jpg",
		LastFrameURL:  "https://ref.test/last.jpg",
		Duration:      5,
		AspectRatio:   "16:9",
	}
	req, err := a.BuildGenerateRequest(testAIConfig(), record)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	content := body["content"].([]map[string]interface{})
	// text + first_frame + last_frame = 3
	if len(content) != 3 {
		t.Errorf("len(content) = %d, want 3 for first_last mode", len(content))
	}
	if content[1]["role"] != "first_frame" {
		t.Errorf("content[1].role = %v, want first_frame", content[1]["role"])
	}
	if content[2]["role"] != "last_frame" {
		t.Errorf("content[2].role = %v, want last_frame", content[2]["role"])
	}
}

func TestMiniMaxVideoAdapter_BuildGenerateRequest_Multiple(t *testing.T) {
	a := &MiniMaxVideoAdapter{}
	record := &VideoGenRecord{
		Prompt:             "test",
		ReferenceMode:      "multiple",
		ReferenceImageURLs: `["https://a.jpg","https://b.jpg","https://c.jpg"]`,
		Duration:           5,
		AspectRatio:        "16:9",
	}
	req, err := a.BuildGenerateRequest(testAIConfig(), record)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	content := body["content"].([]map[string]interface{})
	// text + 3 images = 4
	if len(content) != 4 {
		t.Errorf("len(content) = %d, want 4 for multiple mode", len(content))
	}
}

func TestMiniMaxVideoAdapter_ParseGenerateResponse_Async(t *testing.T) {
	a := &MiniMaxVideoAdapter{}
	resp := rawJSON(map[string]interface{}{"task_id": "vid-task-1"})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !got.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if got.TaskID != "vid-task-1" {
		t.Errorf("TaskID = %q, want %q", got.TaskID, "vid-task-1")
	}
}

func TestMiniMaxVideoAdapter_ParseGenerateResponse_Sync(t *testing.T) {
	a := &MiniMaxVideoAdapter{}
	resp := rawJSON(map[string]interface{}{
		"video_url": "https://vid.test/1.mp4",
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.IsAsync {
		t.Error("IsAsync = true, want false")
	}
	if got.VideoURL != "https://vid.test/1.mp4" {
		t.Errorf("VideoURL = %q, want %q", got.VideoURL, "https://vid.test/1.mp4")
	}
}

func TestMiniMaxVideoAdapter_ParseGenerateResponse_NestedData(t *testing.T) {
	a := &MiniMaxVideoAdapter{}
	resp := rawJSON(map[string]interface{}{
		"data": map[string]interface{}{"id": "nested-task-1"},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !got.IsAsync || got.TaskID != "nested-task-1" {
		t.Errorf("got IsAsync=%v TaskID=%q, want true/nested-task-1", got.IsAsync, got.TaskID)
	}
}

func TestMiniMaxVideoAdapter_ParsePollResponse(t *testing.T) {
	a := &MiniMaxVideoAdapter{}

	t.Run("completed", func(t *testing.T) {
		resp := rawJSON(map[string]interface{}{
			"data": map[string]interface{}{
				"status":    "success",
				"video_url": "https://vid.test/done.mp4",
			},
		})
		got, err := a.ParsePollResponse(resp)
		if err != nil {
			t.Fatalf("error: %v", err)
		}
		if got.Status != "completed" {
			t.Errorf("Status = %q, want %q", got.Status, "completed")
		}
		if got.VideoURL != "https://vid.test/done.mp4" {
			t.Errorf("VideoURL = %q, want %q", got.VideoURL, "https://vid.test/done.mp4")
		}
	})

	t.Run("failed", func(t *testing.T) {
		// Adapter reads error from top-level "error" / "error_msg", not nested in data.
		resp := rawJSON(map[string]interface{}{
			"status": "failed",
			"error":  "timeout",
		})
		got, err := a.ParsePollResponse(resp)
		if err != nil {
			t.Fatalf("error: %v", err)
		}
		if got.Status != "failed" {
			t.Errorf("Status = %q, want %q", got.Status, "failed")
		}
		if got.Error != "timeout" {
			t.Errorf("Error = %q, want %q", got.Error, "timeout")
		}
	})
}

// ========== MiniMax TTS ==========

func TestMiniMaxTTSAdapter_Provider(t *testing.T) {
	a := &MiniMaxTTSAdapter{}
	if got := a.Provider(); got != "minimax" {
		t.Errorf("Provider() = %q, want %q", got, "minimax")
	}
}

func TestMiniMaxTTSAdapter_BuildGenerateRequest(t *testing.T) {
	a := &MiniMaxTTSAdapter{}
	params := map[string]interface{}{
		"text":    "Hello world",
		"voice":   "voice-123",
		"speed":   1.2,
		"emotion": "sad",
	}
	req, err := a.BuildGenerateRequest(testAIConfig(), params)
	if err != nil {
		t.Fatalf("BuildGenerateRequest error: %v", err)
	}
	verifyBasicRequest(t, req, "POST", "Bearer ")

	if !strings.Contains(req.URL, "/v1/t2a_v2") {
		t.Errorf("URL = %q, want to contain /v1/t2a_v2", req.URL)
	}

	body := req.Body.(map[string]interface{})
	if body["text"] != "Hello world" {
		t.Errorf("body.text = %v, want %q", body["text"], "Hello world")
	}

	vs, ok := body["voice_setting"].(map[string]interface{})
	if !ok {
		t.Fatalf("body.voice_setting type = %T", body["voice_setting"])
	}
	if vs["emotion"] != "sad" {
		t.Errorf("voice_setting.emotion = %v, want %q", vs["emotion"], "sad")
	}
	if vs["speed"] != 1.2 {
		t.Errorf("voice_setting.speed = %v, want 1.2", vs["speed"])
	}
	if vs["voice_id"] != "voice-123" {
		t.Errorf("voice_setting.voice_id = %v, want %q", vs["voice_id"], "voice-123")
	}

	as, ok := body["audio_setting"].(map[string]interface{})
	if !ok {
		t.Fatalf("body.audio_setting type = %T", body["audio_setting"])
	}
	if as["format"] != "mp3" {
		t.Errorf("audio_setting.format = %v, want %q", as["format"], "mp3")
	}
	if as["sample_rate"] != 32000 {
		t.Errorf("audio_setting.sample_rate = %v, want 32000", as["sample_rate"])
	}
}

func TestMiniMaxTTSAdapter_BuildGenerateRequest_Defaults(t *testing.T) {
	a := &MiniMaxTTSAdapter{}
	params := map[string]interface{}{
		"text":  "test",
		"voice": "v1",
	}
	req, err := a.BuildGenerateRequest(testAIConfig(), params)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	if body["model"] != "speech-2.8-hd" {
		t.Errorf("model = %v, want %q", body["model"], "speech-2.8-hd")
	}
	vs := body["voice_setting"].(map[string]interface{})
	if vs["speed"] != 1.0 {
		t.Errorf("default speed = %v, want 1.0", vs["speed"])
	}
	if vs["emotion"] != "happy" {
		t.Errorf("default emotion = %v, want %q", vs["emotion"], "happy")
	}
}

func TestMiniMaxTTSAdapter_ParseResponse(t *testing.T) {
	a := &MiniMaxTTSAdapter{}
	resp := rawJSON(map[string]interface{}{
		"base_resp": map[string]interface{}{"status_code": 0},
		"data": map[string]interface{}{
			"audio": "aabbccddhex",
			"extra_info": map[string]interface{}{
				"audio_length":      5000,
				"audio_sample_rate": 32000,
				"bitrate":           128000,
				"audio_format":      "mp3",
				"audio_channel":     1,
			},
		},
	})
	got, err := a.ParseResponse(resp)
	if err != nil {
		t.Fatalf("ParseResponse error: %v", err)
	}
	if got.AudioHex != "aabbccddhex" {
		t.Errorf("AudioHex = %q, want %q", got.AudioHex, "aabbccddhex")
	}
	if got.AudioLength != 5000 {
		t.Errorf("AudioLength = %d, want 5000", got.AudioLength)
	}
	if got.SampleRate != 32000 {
		t.Errorf("SampleRate = %d, want 32000", got.SampleRate)
	}
	if got.Bitrate != 128000 {
		t.Errorf("Bitrate = %d, want 128000", got.Bitrate)
	}
	if got.Format != "mp3" {
		t.Errorf("Format = %q, want %q", got.Format, "mp3")
	}
	if got.Channel != 1 {
		t.Errorf("Channel = %d, want 1", got.Channel)
	}
}

func TestMiniMaxTTSAdapter_ParseResponse_Error(t *testing.T) {
	a := &MiniMaxTTSAdapter{}
	resp := rawJSON(map[string]interface{}{
		"base_resp": map[string]interface{}{"status_code": 1001, "status_msg": "quota exceeded"},
	})
	_, err := a.ParseResponse(resp)
	if err == nil {
		t.Fatal("expected error for non-zero status_code")
	}
	if !strings.Contains(err.Error(), "quota exceeded") {
		t.Errorf("error = %q, want to contain %q", err.Error(), "quota exceeded")
	}
}

func TestMiniMaxTTSAdapter_ParseResponse_NoAudio(t *testing.T) {
	a := &MiniMaxTTSAdapter{}
	resp := rawJSON(map[string]interface{}{
		"base_resp": map[string]interface{}{"status_code": 0},
		"data":      map[string]interface{}{},
	})
	_, err := a.ParseResponse(resp)
	if err == nil {
		t.Fatal("expected error for empty audio")
	}
}

// ========== OpenAI Image ==========

func TestOpenAIImageAdapter_Provider(t *testing.T) {
	a := &OpenAIImageAdapter{}
	if got := a.Provider(); got != "openai" {
		t.Errorf("Provider() = %q, want %q", got, "openai")
	}
}

func TestOpenAIImageAdapter_BuildGenerateRequest(t *testing.T) {
	a := &OpenAIImageAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), testImageRecord())
	if err != nil {
		t.Fatalf("BuildGenerateRequest error: %v", err)
	}
	verifyBasicRequest(t, req, "POST", "Bearer ")

	if !strings.Contains(req.URL, "/v1/images/generations") {
		t.Errorf("URL = %q, want to contain /v1/images/generations", req.URL)
	}

	body := req.Body.(map[string]interface{})
	if body["response_format"] != "url" {
		t.Errorf("body.response_format = %v, want %q", body["response_format"], "url")
	}
	if body["size"] != "1920x1080" {
		t.Errorf("body.size = %v, want %q", body["size"], "1920x1080")
	}
}

func TestOpenAIImageAdapter_BuildGenerateRequest_Defaults(t *testing.T) {
	a := &OpenAIImageAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), &ImageGenRecord{Prompt: "test"})
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	if body["model"] != "dall-e-3" {
		t.Errorf("default model = %v, want dall-e-3", body["model"])
	}
	if body["size"] != "1024x1024" {
		t.Errorf("default size = %v, want 1024x1024", body["size"])
	}
}

func TestOpenAIImageAdapter_ParseGenerateResponse_URL(t *testing.T) {
	a := &OpenAIImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"data": []map[string]interface{}{
			{"url": "https://img.openai/1.png"},
		},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.IsAsync {
		t.Error("IsAsync = true, want false")
	}
	if got.ImageURL != "https://img.openai/1.png" {
		t.Errorf("ImageURL = %q, want %q", got.ImageURL, "https://img.openai/1.png")
	}
}

func TestOpenAIImageAdapter_ParseGenerateResponse_B64(t *testing.T) {
	a := &OpenAIImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"data": []map[string]interface{}{
			{"b64_json": "iVBORw0KGgo..."},
		},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.IsAsync {
		t.Error("IsAsync = true, want false")
	}
	if got.ImageURL != "" {
		t.Errorf("ImageURL = %q, want empty for b64 mode", got.ImageURL)
	}
}

func TestOpenAIImageAdapter_ParseGenerateResponse_Async(t *testing.T) {
	a := &OpenAIImageAdapter{}
	resp := rawJSON(map[string]interface{}{"task_id": "oai-task-1"})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !got.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if got.TaskID != "oai-task-1" {
		t.Errorf("TaskID = %q, want %q", got.TaskID, "oai-task-1")
	}
}

func TestOpenAIImageAdapter_BuildPollRequest(t *testing.T) {
	a := &OpenAIImageAdapter{}
	req, err := a.BuildPollRequest(testAIConfig(), "oai-task-1")
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !strings.Contains(req.URL, "/v1/images/task/oai-task-1") {
		t.Errorf("URL = %q, want to contain /v1/images/task/oai-task-1", req.URL)
	}
}

func TestOpenAIImageAdapter_ParsePollResponse(t *testing.T) {
	a := &OpenAIImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"status": "completed",
		"data":   []map[string]interface{}{{"url": "https://oai.test/done.png"}},
	})
	got, err := a.ParsePollResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "completed" {
		t.Errorf("Status = %q, want %q", got.Status, "completed")
	}
	if got.ImageURL != "https://oai.test/done.png" {
		t.Errorf("ImageURL = %q, want %q", got.ImageURL, "https://oai.test/done.png")
	}
}

func TestOpenAIImageAdapter_ExtractImageBase64(t *testing.T) {
	a := &OpenAIImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"data": []map[string]interface{}{
			{"b64_json": "base64data123"},
		},
	})
	got, err := a.ExtractImageBase64(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got == nil {
		t.Fatal("ExtractImageBase64 = nil, want non-nil")
	}
	if got.Data != "base64data123" {
		t.Errorf("Data = %q, want %q", got.Data, "base64data123")
	}
	if got.MimeType != "image/png" {
		t.Errorf("MimeType = %q, want %q", got.MimeType, "image/png")
	}
}

func TestOpenAIImageAdapter_ExtractImageBase64_NoB64(t *testing.T) {
	a := &OpenAIImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"data": []map[string]interface{}{
			{"url": "https://oai.test/img.png"},
		},
	})
	got, err := a.ExtractImageBase64(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got != nil {
		t.Error("ExtractImageBase64 should return nil when no b64_json present")
	}
}

// ========== Chatfire Image ==========

func TestChatfireImageAdapter_Provider(t *testing.T) {
	a := &ChatfireImageAdapter{}
	if got := a.Provider(); got != "chatfire" {
		t.Errorf("Provider() = %q, want %q", got, "chatfire")
	}
}

func TestChatfireImageAdapter_BuildGenerateRequest(t *testing.T) {
	a := &ChatfireImageAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), testImageRecord())
	if err != nil {
		t.Fatalf("BuildGenerateRequest error: %v", err)
	}
	// Should reuse OpenAI endpoint
	if !strings.Contains(req.URL, "/v1/images/generations") {
		t.Errorf("URL = %q, want to contain /v1/images/generations", req.URL)
	}
}

// ========== Gemini Image ==========

func TestGeminiImageAdapter_Provider(t *testing.T) {
	a := &GeminiImageAdapter{}
	if got := a.Provider(); got != "gemini" {
		t.Errorf("Provider() = %q, want %q", got, "gemini")
	}
}

func TestGeminiImageAdapter_BuildGenerateRequest(t *testing.T) {
	a := &GeminiImageAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), &ImageGenRecord{
		Prompt: "mountain landscape",
		Size:   "1024x768",
	})
	if err != nil {
		t.Fatalf("BuildGenerateRequest error: %v", err)
	}
	verifyBasicRequest(t, req, "POST", "Bearer ")

	if !strings.Contains(req.URL, ":generateContent") {
		t.Errorf("URL = %q, want to contain :generateContent", req.URL)
	}
	if !strings.Contains(req.URL, "key=") {
		t.Errorf("URL = %q, want to contain key= query param", req.URL)
	}
	if req.Headers["x-goog-api-key"] != "test-api-key" {
		t.Errorf("x-goog-api-key = %q, want %q", req.Headers["x-goog-api-key"], "test-api-key")
	}

	body := req.Body.(map[string]interface{})
	gc := body["generationConfig"].(map[string]interface{})
	modes := gc["responseModalities"].([]string)
	if len(modes) != 2 || modes[0] != "IMAGE" || modes[1] != "TEXT" {
		t.Errorf("responseModalities = %v, want [IMAGE TEXT]", modes)
	}
}

func TestGeminiImageAdapter_BuildGenerateRequest_ModelInPath(t *testing.T) {
	a := &GeminiImageAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), &ImageGenRecord{
		Model:  "gemini-2.5-flash-image",
		Prompt: "test",
	})
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !strings.Contains(req.URL, "models/gemini-2.5-flash-image") {
		t.Errorf("URL = %q, want to contain models/gemini-2.5-flash-image", req.URL)
	}
}

func TestGeminiImageAdapter_BuildGenerateRequest_ReferenceImages(t *testing.T) {
	a := &GeminiImageAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), &ImageGenRecord{
		Prompt:          "test",
		ReferenceImages: []string{"data:image/png;base64,abc123", "data:image/jpeg;base64,xyz789"},
	})
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	contents := body["contents"].([]map[string]interface{})
	parts := contents[0]["parts"].([]map[string]interface{})
	// 2 inline_data parts + 1 text part = 3
	if len(parts) != 3 {
		t.Errorf("len(parts) = %d, want 3", len(parts))
	}
	// inline_data parts come before text
	if _, ok := parts[0]["inline_data"]; !ok {
		t.Error("first part should have inline_data")
	}
	if _, ok := parts[2]["text"]; !ok {
		t.Error("last part should have text")
	}
}

func TestGeminiImageAdapter_ParseGenerateResponse_Base64(t *testing.T) {
	a := &GeminiImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"candidates": []map[string]interface{}{
			{
				"finishReason": "STOP",
				"content": map[string]interface{}{
					"parts": []map[string]interface{}{
						{
							"inlineData": map[string]interface{}{
								"mimeType": "image/png",
								"data":     "base64gemini==",
							},
						},
					},
				},
			},
		},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.IsAsync {
		t.Error("IsAsync = true, want false")
	}
}

func TestGeminiImageAdapter_ParseGenerateResponse_Error(t *testing.T) {
	a := &GeminiImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"candidates": []map[string]interface{}{
			{
				"finishReason":  "SAFETY",
				"finishMessage": "Blocked for safety",
			},
		},
	})
	_, err := a.ParseGenerateResponse(resp)
	if err == nil {
		t.Fatal("expected error for SAFETY finish reason")
	}
	if !strings.Contains(err.Error(), "Blocked for safety") {
		t.Errorf("error = %q, want to contain %q", err.Error(), "Blocked for safety")
	}
}

func TestGeminiImageAdapter_ParseGenerateResponse_APIError(t *testing.T) {
	a := &GeminiImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"error": map[string]interface{}{"message": "API key invalid"},
	})
	_, err := a.ParseGenerateResponse(resp)
	if err == nil {
		t.Fatal("expected error for API error")
	}
	if !strings.Contains(err.Error(), "API key invalid") {
		t.Errorf("error = %q, want to contain API key invalid", err.Error())
	}
}

func TestGeminiImageAdapter_ExtractImageBase64_CamelCase(t *testing.T) {
	a := &GeminiImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"candidates": []map[string]interface{}{
			{
				"content": map[string]interface{}{
					"parts": []map[string]interface{}{
						{
							"inlineData": map[string]interface{}{
								"mimeType": "image/png",
								"data":     "abc123base64",
							},
						},
					},
				},
			},
		},
	})
	got, err := a.ExtractImageBase64(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got == nil {
		t.Fatal("ExtractImageBase64 = nil, want non-nil")
	}
	if got.Data != "abc123base64" {
		t.Errorf("Data = %q, want %q", got.Data, "abc123base64")
	}
	if got.MimeType != "image/png" {
		t.Errorf("MimeType = %q, want %q", got.MimeType, "image/png")
	}
}

func TestGeminiImageAdapter_ExtractImageBase64_SnakeCase(t *testing.T) {
	a := &GeminiImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"candidates": []map[string]interface{}{
			{
				"content": map[string]interface{}{
					"parts": []map[string]interface{}{
						{
							"inline_data": map[string]interface{}{
								"mime_type": "image/jpeg",
								"data":      "snake_case_data",
							},
						},
					},
				},
			},
		},
	})
	got, err := a.ExtractImageBase64(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got == nil {
		t.Fatal("ExtractImageBase64 = nil, want non-nil for snake_case")
	}
	if got.MimeType != "image/jpeg" {
		t.Errorf("MimeType = %q, want %q", got.MimeType, "image/jpeg")
	}
}

// ========== VolcEngine Image ==========

func TestVolcEngineImageAdapter_Provider(t *testing.T) {
	a := &VolcEngineImageAdapter{}
	if got := a.Provider(); got != "volcengine" {
		t.Errorf("Provider() = %q, want %q", got, "volcengine")
	}
}

func TestVolcEngineImageAdapter_BuildGenerateRequest(t *testing.T) {
	a := &VolcEngineImageAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), testImageRecord())
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	verifyBasicRequest(t, req, "POST", "Bearer ")
	if !strings.Contains(req.URL, "/api/v3/images/generations") {
		t.Errorf("URL = %q, want to contain /api/v3/images/generations", req.URL)
	}
	body := req.Body.(map[string]interface{})
	if body["width"] != 1920 {
		t.Errorf("width = %v, want 1920", body["width"])
	}
	if body["height"] != 1080 {
		t.Errorf("height = %v, want 1080", body["height"])
	}
}

func TestVolcEngineImageAdapter_BuildGenerateRequest_DefaultModel(t *testing.T) {
	a := &VolcEngineImageAdapter{}
	// Use a config with empty Model so the adapter falls through to its hardcoded default.
	cfg := &AIConfig{
		Provider: "test",
		BaseURL:  "https://api.example.com",
		APIKey:   "test-api-key",
		Model:    "", // empty — adapter must use its own default
	}
	req, err := a.BuildGenerateRequest(cfg, &ImageGenRecord{Prompt: "test", Size: "1024x1024"})
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	if body["model"] != "doubao-seedream-5-0-lite" {
		t.Errorf("model = %v, want doubao-seedream-5-0-lite", body["model"])
	}
}

func TestVolcEngineImageAdapter_ParseGenerateResponse_Sync(t *testing.T) {
	a := &VolcEngineImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"data": []map[string]interface{}{
			{"url": "https://volc.test/img.png"},
		},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.IsAsync {
		t.Error("IsAsync = true, want false")
	}
	if got.ImageURL != "https://volc.test/img.png" {
		t.Errorf("ImageURL = %q, want %q", got.ImageURL, "https://volc.test/img.png")
	}
}

func TestVolcEngineImageAdapter_ParseGenerateResponse_Async(t *testing.T) {
	a := &VolcEngineImageAdapter{}
	resp := rawJSON(map[string]interface{}{"task_id": "volc-task-1"})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !got.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if got.TaskID != "volc-task-1" {
		t.Errorf("TaskID = %q, want %q", got.TaskID, "volc-task-1")
	}
}

func TestVolcEngineImageAdapter_ParseGenerateResponse_TopLevelURL(t *testing.T) {
	a := &VolcEngineImageAdapter{}
	resp := rawJSON(map[string]interface{}{"url": "https://volc.test/top.png"})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.ImageURL != "https://volc.test/top.png" {
		t.Errorf("ImageURL = %q, want %q", got.ImageURL, "https://volc.test/top.png")
	}
}

func TestVolcEngineImageAdapter_ParsePollResponse_Succeeded(t *testing.T) {
	a := &VolcEngineImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"status": "succeeded",
		"data":   []map[string]interface{}{{"url": "https://volc.test/done.png"}},
	})
	got, err := a.ParsePollResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "completed" {
		t.Errorf("Status = %q, want %q", got.Status, "completed")
	}
	if got.ImageURL != "https://volc.test/done.png" {
		t.Errorf("ImageURL = %q, want %q", got.ImageURL, "https://volc.test/done.png")
	}
}

func TestVolcEngineImageAdapter_ParsePollResponse_Failed(t *testing.T) {
	a := &VolcEngineImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"status": "failed",
		"error":  map[string]interface{}{"message": "content violation"},
	})
	got, err := a.ParsePollResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "failed" {
		t.Errorf("Status = %q, want %q", got.Status, "failed")
	}
	if got.Error != "content violation" {
		t.Errorf("Error = %q, want %q", got.Error, "content violation")
	}
}

func TestVolcEngineImageAdapter_ExtractImageBase64(t *testing.T) {
	a := &VolcEngineImageAdapter{}
	got, err := a.ExtractImageBase64(nil)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got != nil {
		t.Error("should return nil (VolcEngine returns URLs)")
	}
}

// ========== VolcEngine Video ==========

func TestVolcEngineVideoAdapter_Provider(t *testing.T) {
	a := &VolcEngineVideoAdapter{}
	if got := a.Provider(); got != "volcengine" {
		t.Errorf("Provider() = %q, want %q", got, "volcengine")
	}
}

func TestVolcEngineVideoAdapter_BuildGenerateRequest(t *testing.T) {
	a := &VolcEngineVideoAdapter{}
	record := testVideoRecord()
	req, err := a.BuildGenerateRequest(testAIConfig(), record)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	verifyBasicRequest(t, req, "POST", "Bearer ")
	if !strings.Contains(req.URL, "/api/v3/contents/generations/tasks") {
		t.Errorf("URL = %q, want to contain /api/v3/contents/generations/tasks", req.URL)
	}
	body := req.Body.(map[string]interface{})
	if body["generate_audio"] != true {
		t.Error("generate_audio = false, want true")
	}
	if body["watermark"] != false {
		t.Error("watermark = true, want false")
	}
	if body["ratio"] != "16:9" {
		t.Errorf("ratio = %v, want %q", body["ratio"], "16:9")
	}
	if body["duration"] != 5 {
		t.Errorf("duration = %v, want 5", body["duration"])
	}
}

func TestVolcEngineVideoAdapter_BuildGenerateRequest_DefaultModel(t *testing.T) {
	a := &VolcEngineVideoAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), &VideoGenRecord{Duration: 5, AspectRatio: "16:9"})
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	if body["model"] != "doubao-seedance-1-5-pro-251215" {
		t.Errorf("model = %v, want doubao-seedance-1-5-pro-251215", body["model"])
	}
}

func TestVolcEngineVideoAdapter_DurationClamp(t *testing.T) {
	tests := []struct {
		input int
		want  int
	}{
		{0, 5},   // default
		{2, 4},   // below min → clamped to 4
		{15, 12}, // above max → clamped to 12
		{8, 8},   // within range
	}
	a := &VolcEngineVideoAdapter{}
	for _, tt := range tests {
		t.Run(string(rune('0'+tt.input)), func(t *testing.T) {
			record := &VideoGenRecord{Duration: tt.input, AspectRatio: "16:9"}
			req, err := a.BuildGenerateRequest(testAIConfig(), record)
			if err != nil {
				t.Fatalf("error: %v", err)
			}
			body := req.Body.(map[string]interface{})
			if body["duration"] != tt.want {
				t.Errorf("duration %d → %v, want %d", tt.input, body["duration"], tt.want)
			}
		})
	}
}

func TestVolcEngineVideoAdapter_ParseGenerateResponse(t *testing.T) {
	a := &VolcEngineVideoAdapter{}
	resp := rawJSON(map[string]interface{}{"id": "volc-vid-1"})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !got.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if got.TaskID != "volc-vid-1" {
		t.Errorf("TaskID = %q, want %q", got.TaskID, "volc-vid-1")
	}
}

func TestVolcEngineVideoAdapter_ParsePollResponse_Succeeded(t *testing.T) {
	a := &VolcEngineVideoAdapter{}
	resp := rawJSON(map[string]interface{}{
		"status": "succeeded",
		"content": map[string]interface{}{
			"video_url": "https://volc.test/video.mp4",
		},
	})
	got, err := a.ParsePollResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "completed" {
		t.Errorf("Status = %q, want %q", got.Status, "completed")
	}
	if got.VideoURL != "https://volc.test/video.mp4" {
		t.Errorf("VideoURL = %q, want %q", got.VideoURL, "https://volc.test/video.mp4")
	}
}

func TestVolcEngineVideoAdapter_ParsePollResponse_Failed(t *testing.T) {
	a := &VolcEngineVideoAdapter{}
	resp := rawJSON(map[string]interface{}{
		"status": "failed",
		"error":  map[string]interface{}{"message": "timeout"},
	})
	got, err := a.ParsePollResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "failed" {
		t.Errorf("Status = %q, want failed", got.Status)
	}
	if got.Error != "timeout" {
		t.Errorf("Error = %q, want timeout", got.Error)
	}
}

// ========== Vidu Video ==========

func TestViduVideoAdapter_Provider(t *testing.T) {
	a := &ViduVideoAdapter{}
	if got := a.Provider(); got != "vidu" {
		t.Errorf("Provider() = %q, want %q", got, "vidu")
	}
}

func TestViduVideoAdapter_BuildGenerateRequest(t *testing.T) {
	a := &ViduVideoAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), testVideoRecord())
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	// Vidu uses "Token" not "Bearer"
	auth := req.Headers["Authorization"]
	if !strings.HasPrefix(auth, "Token ") {
		t.Errorf("Authorization = %q, want prefix %q", auth, "Token ")
	}
	if !strings.Contains(req.URL, "/ent/v2/img2video") {
		t.Errorf("URL = %q, want to contain /ent/v2/img2video", req.URL)
	}
	body := req.Body.(map[string]interface{})
	images, ok := body["images"].([]string)
	if !ok || len(images) != 1 {
		t.Errorf("images = %v, want 1-element []string", body["images"])
	}
}

func TestViduVideoAdapter_BuildGenerateRequest_DefaultModel(t *testing.T) {
	a := &ViduVideoAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), &VideoGenRecord{Duration: 5})
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	if body["model"] != "viduq3-turbo" {
		t.Errorf("model = %v, want viduq3-turbo", body["model"])
	}
}

func TestViduVideoAdapter_ParseGenerateResponse(t *testing.T) {
	a := &ViduVideoAdapter{}
	resp := rawJSON(map[string]interface{}{"task_id": "vidu-task-1"})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !got.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if got.TaskID != "vidu-task-1" {
		t.Errorf("TaskID = %q, want %q", got.TaskID, "vidu-task-1")
	}
}

func TestViduVideoAdapter_BuildPollRequest_NoRealEndpoint(t *testing.T) {
	a := &ViduVideoAdapter{}
	req, err := a.BuildPollRequest(testAIConfig(), "task-1")
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !strings.HasPrefix(req.URL, "vidu://") {
		t.Errorf("URL = %q, want vidu:// placeholder", req.URL)
	}
}

func TestViduVideoAdapter_ParsePollResponse_AlwaysProcessing(t *testing.T) {
	a := &ViduVideoAdapter{}
	got, err := a.ParsePollResponse(rawJSON(map[string]interface{}{}))
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "processing" {
		t.Errorf("Status = %q, want %q (Vidu uses webhooks)", got.Status, "processing")
	}
}

func TestParseCallbackState(t *testing.T) {
	tests := []struct {
		name       string
		json       interface{}
		wantStatus string
		wantURL    string
		wantErr    bool
	}{
		{
			"success",
			map[string]interface{}{"state": "success", "video_url": "https://vidu.test/done.mp4"},
			"completed", "https://vidu.test/done.mp4", false,
		},
		{
			"failed",
			map[string]interface{}{"state": "failed"},
			"failed", "", false,
		},
		{
			"unknown_state_treated_as_failed",
			map[string]interface{}{"state": "pending"},
			"failed", "", false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseCallbackState(rawJSON(tt.json))
			if (err != nil) != tt.wantErr {
				t.Fatalf("error = %v, wantErr %v", err, tt.wantErr)
			}
			if got.Status != tt.wantStatus {
				t.Errorf("Status = %q, want %q", got.Status, tt.wantStatus)
			}
			if got.VideoURL != tt.wantURL {
				t.Errorf("VideoURL = %q, want %q", got.VideoURL, tt.wantURL)
			}
		})
	}
}

// ========== Ali Image ==========

func TestAliImageAdapter_Provider(t *testing.T) {
	a := &AliImageAdapter{}
	if got := a.Provider(); got != "ali" {
		t.Errorf("Provider() = %q, want %q", got, "ali")
	}
}

func TestAliImageAdapter_BuildGenerateRequest(t *testing.T) {
	a := &AliImageAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), testImageRecord())
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	verifyBasicRequest(t, req, "POST", "Bearer ")

	if req.Headers["X-DashScope-Async"] != "enable" {
		t.Errorf("X-DashScope-Async = %q, want %q", req.Headers["X-DashScope-Async"], "enable")
	}
	if !strings.Contains(req.URL, "/services/aigc/image-generation/generation") {
		t.Errorf("URL = %q, want to contain image-generation path", req.URL)
	}

	body := req.Body.(map[string]interface{})
	input := body["input"].(map[string]interface{})
	msgs := input["messages"].([]map[string]interface{})
	if len(msgs) == 0 {
		t.Fatal("input.messages is empty")
	}
	if msgs[0]["role"] != "user" {
		t.Errorf("messages[0].role = %v, want user", msgs[0]["role"])
	}

	params := body["parameters"].(map[string]interface{})
	// 1920/1080 ≈ 1.78 > 1.7 → landscape bucket
	if params["size"] != "1696*960" {
		t.Errorf("parameters.size = %v, want %q (landscape bucket)", params["size"], "1696*960")
	}
	if params["watermark"] != false {
		t.Error("watermark = true, want false")
	}
}

func TestAliImageAdapter_BuildGenerateRequest_SizeBuckets(t *testing.T) {
	tests := []struct {
		size string
		want string
	}{
		{"1920x1080", "1696*960"},  // aspect ~1.78 > 1.7 → landscape
		{"1080x1920", "960*1696"},  // aspect ~0.56 < 0.8 → portrait
		{"1024x1024", "1280*1280"}, // aspect 1.0 → square
		{"", "1280*1280"},          // empty → default square
	}
	a := &AliImageAdapter{}
	for _, tt := range tests {
		t.Run(tt.size, func(t *testing.T) {
			req, err := a.BuildGenerateRequest(testAIConfig(), &ImageGenRecord{
				Prompt: "test",
				Size:   tt.size,
			})
			if err != nil {
				t.Fatalf("error: %v", err)
			}
			body := req.Body.(map[string]interface{})
			params := body["parameters"].(map[string]interface{})
			if params["size"] != tt.want {
				t.Errorf("size %q → %v, want %q", tt.size, params["size"], tt.want)
			}
		})
	}
}

func TestAliImageAdapter_ParseGenerateResponse_Async(t *testing.T) {
	a := &AliImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"output": map[string]interface{}{
			"task_id":     "ali-task-1",
			"task_status": "PENDING",
		},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !got.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if got.TaskID != "ali-task-1" {
		t.Errorf("TaskID = %q, want %q", got.TaskID, "ali-task-1")
	}
}

func TestAliImageAdapter_ParseGenerateResponse_Sync(t *testing.T) {
	a := &AliImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"output": map[string]interface{}{
			"choices": []map[string]interface{}{
				{
					"message": map[string]interface{}{
						"content": []map[string]interface{}{
							{"image": "https://ali.test/sync.png"},
						},
					},
				},
			},
		},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.IsAsync {
		t.Error("IsAsync = true, want false")
	}
	if got.ImageURL != "https://ali.test/sync.png" {
		t.Errorf("ImageURL = %q, want %q", got.ImageURL, "https://ali.test/sync.png")
	}
}

func TestAliImageAdapter_ParsePollResponse_Succeeded(t *testing.T) {
	a := &AliImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"output": map[string]interface{}{
			"task_status": "SUCCEEDED",
			"choices": []map[string]interface{}{
				{
					"message": map[string]interface{}{
						"content": []map[string]interface{}{
							{"image": "https://ali.test/img.png"},
						},
					},
				},
			},
		},
	})
	got, err := a.ParsePollResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "completed" {
		t.Errorf("Status = %q, want %q", got.Status, "completed")
	}
	if got.ImageURL != "https://ali.test/img.png" {
		t.Errorf("ImageURL = %q, want %q", got.ImageURL, "https://ali.test/img.png")
	}
}

func TestAliImageAdapter_ParsePollResponse_Failed(t *testing.T) {
	a := &AliImageAdapter{}
	resp := rawJSON(map[string]interface{}{
		"output":  map[string]interface{}{"task_status": "FAILED"},
		"message": "internal error",
	})
	got, err := a.ParsePollResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "failed" {
		t.Errorf("Status = %q, want %q", got.Status, "failed")
	}
	if got.Error != "internal error" {
		t.Errorf("Error = %q, want %q", got.Error, "internal error")
	}
}

func TestAliImageAdapter_ParsePollResponse_Processing(t *testing.T) {
	a := &AliImageAdapter{}
	for _, status := range []string{"PENDING", "RUNNING"} {
		t.Run(status, func(t *testing.T) {
			resp := rawJSON(map[string]interface{}{
				"output": map[string]interface{}{"task_status": status},
			})
			got, err := a.ParsePollResponse(resp)
			if err != nil {
				t.Fatalf("error: %v", err)
			}
			if got.Status != "processing" {
				t.Errorf("Status for %q = %q, want %q", status, got.Status, "processing")
			}
		})
	}
}

func TestAliImageAdapter_ExtractImageBase64(t *testing.T) {
	a := &AliImageAdapter{}
	got, err := a.ExtractImageBase64(nil)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got != nil {
		t.Error("should return nil (Ali returns URLs)")
	}
}

// ========== Ali Video ==========

func TestAliVideoAdapter_Provider(t *testing.T) {
	a := &AliVideoAdapter{}
	if got := a.Provider(); got != "ali" {
		t.Errorf("Provider() = %q, want %q", got, "ali")
	}
}

func TestAliVideoAdapter_BuildGenerateRequest(t *testing.T) {
	a := &AliVideoAdapter{}
	record := testVideoRecord()
	req, err := a.BuildGenerateRequest(testAIConfig(), record)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	verifyBasicRequest(t, req, "POST", "Bearer ")
	if !strings.Contains(req.URL, "/services/aigc/video-generation/video-synthesis") {
		t.Errorf("URL = %q, want to contain video-synthesis path", req.URL)
	}

	body := req.Body.(map[string]interface{})
	input := body["input"].(map[string]interface{})
	if input["img_url"] != "https://ref.test/img.jpg" {
		t.Errorf("input.img_url = %v, want %q", input["img_url"], "https://ref.test/img.jpg")
	}

	params := body["parameters"].(map[string]interface{})
	if params["resolution"] != "1080P" {
		t.Errorf("resolution = %v, want %q", params["resolution"], "1080P")
	}
	if params["duration"] != 5 {
		t.Errorf("duration = %v, want 5", params["duration"])
	}
}

func TestAliVideoAdapter_BuildGenerateRequest_FirstLastFrame(t *testing.T) {
	a := &AliVideoAdapter{}
	record := &VideoGenRecord{
		Prompt:        "test",
		FirstFrameURL: "https://ref.test/first.jpg",
		LastFrameURL:  "https://ref.test/last.jpg",
		Duration:      5,
		AspectRatio:   "16:9",
	}
	req, err := a.BuildGenerateRequest(testAIConfig(), record)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	input := body["input"].(map[string]interface{})
	if input["img_url"] != "https://ref.test/first.jpg" {
		t.Errorf("img_url (first frame) = %v, want first.jpg", input["img_url"])
	}
	if input["last_img_url"] != "https://ref.test/last.jpg" {
		t.Errorf("last_img_url = %v, want last.jpg", input["last_img_url"])
	}
}

func TestAliVideoAdapter_BuildGenerateRequest_DefaultModel(t *testing.T) {
	a := &AliVideoAdapter{}
	req, err := a.BuildGenerateRequest(testAIConfig(), &VideoGenRecord{Duration: 5, AspectRatio: "16:9"})
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	body := req.Body.(map[string]interface{})
	if body["model"] != "wan2.6-i2v-flash" {
		t.Errorf("model = %v, want wan2.6-i2v-flash", body["model"])
	}
}

func TestAliVideoAdapter_ParseGenerateResponse_Async(t *testing.T) {
	a := &AliVideoAdapter{}
	resp := rawJSON(map[string]interface{}{
		"output": map[string]interface{}{
			"task_id":     "ali-vid-1",
			"task_status": "PENDING",
		},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if !got.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if got.TaskID != "ali-vid-1" {
		t.Errorf("TaskID = %q, want %q", got.TaskID, "ali-vid-1")
	}
}

func TestAliVideoAdapter_ParseGenerateResponse_Sync(t *testing.T) {
	a := &AliVideoAdapter{}
	resp := rawJSON(map[string]interface{}{
		"output": map[string]interface{}{
			"video_url": "https://ali.test/sync.mp4",
		},
	})
	got, err := a.ParseGenerateResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.IsAsync {
		t.Error("IsAsync = true, want false")
	}
	if got.VideoURL != "https://ali.test/sync.mp4" {
		t.Errorf("VideoURL = %q, want %q", got.VideoURL, "https://ali.test/sync.mp4")
	}
}

func TestAliVideoAdapter_ParsePollResponse_Succeeded(t *testing.T) {
	a := &AliVideoAdapter{}
	resp := rawJSON(map[string]interface{}{
		"output": map[string]interface{}{
			"task_status": "SUCCEEDED",
			"video_url":   "https://ali.test/video.mp4",
		},
	})
	got, err := a.ParsePollResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "completed" {
		t.Errorf("Status = %q, want %q", got.Status, "completed")
	}
	if got.VideoURL != "https://ali.test/video.mp4" {
		t.Errorf("VideoURL = %q, want %q", got.VideoURL, "https://ali.test/video.mp4")
	}
}

func TestAliVideoAdapter_ParsePollResponse_Failed(t *testing.T) {
	a := &AliVideoAdapter{}
	resp := rawJSON(map[string]interface{}{
		"output":  map[string]interface{}{"task_status": "FAILED"},
		"message": "timeout",
	})
	got, err := a.ParsePollResponse(resp)
	if err != nil {
		t.Fatalf("error: %v", err)
	}
	if got.Status != "failed" {
		t.Errorf("Status = %q, want failed", got.Status)
	}
	if got.Error != "timeout" {
		t.Errorf("Error = %q, want timeout", got.Error)
	}
}

func TestAliVideoAdapter_ResolutionMapping(t *testing.T) {
	tests := []struct {
		ratio string
		want  string
	}{
		{"16:9", "1080P"},
		{"9:16", "720P"},
		{"1:1", "720P"},
		{"", "1080P"},
	}
	a := &AliVideoAdapter{}
	for _, tt := range tests {
		t.Run(tt.ratio, func(t *testing.T) {
			record := &VideoGenRecord{AspectRatio: tt.ratio, Duration: 5}
			req, err := a.BuildGenerateRequest(testAIConfig(), record)
			if err != nil {
				t.Fatalf("error: %v", err)
			}
			body := req.Body.(map[string]interface{})
			params := body["parameters"].(map[string]interface{})
			if params["resolution"] != tt.want {
				t.Errorf("resolution for %q = %v, want %q", tt.ratio, params["resolution"], tt.want)
			}
		})
	}
}
