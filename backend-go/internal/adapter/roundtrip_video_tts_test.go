package adapter

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// NOTE: doAdapterRequest is already defined in roundtrip_image_test.go
// and is accessible from the same package.

// =================================================================
// MiniMax Video
// =================================================================

func TestRoundTrip_MiniMaxVideo_Async(t *testing.T) {
	mockResp := `{"task_id":"task-mm-vid-001"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-mm-vid-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-mm-vid-key")
		}
		if !strings.Contains(r.URL.Path, "/v1/video_generation") {
			t.Errorf("URL path = %q, want to contain /v1/video_generation", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &MiniMaxVideoAdapter{}
	config := &AIConfig{
		Provider: "minimax",
		BaseURL:  srv.URL,
		APIKey:   "test-mm-vid-key",
		Model:    "test-vid-model",
	}
	record := &VideoGenRecord{
		ID:            1,
		Model:         "test-vid-model",
		Prompt:        "a cat walking",
		Duration:      5,
		AspectRatio:   "16:9",
		ReferenceMode: "single",
		ImageURL:      "https://ref.test/img.jpg",
	}

	req, err := a.BuildGenerateRequest(config, record)
	if err != nil {
		t.Fatalf("BuildGenerateRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParseGenerateResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParseGenerateResponse: %v", err)
	}
	if !result.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if result.TaskID != "task-mm-vid-001" {
		t.Errorf("TaskID = %q, want %q", result.TaskID, "task-mm-vid-001")
	}
}

func TestRoundTrip_MiniMaxVideo_PollCompleted(t *testing.T) {
	mockResp := `{"status":"completed","video_url":"https://mock.test/mm-vid.mp4"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("method = %q, want GET", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &MiniMaxVideoAdapter{}
	config := &AIConfig{
		Provider: "minimax",
		BaseURL:  srv.URL,
		APIKey:   "test-mm-vid-key",
	}

	req, err := a.BuildPollRequest(config, "task-mm-vid-001")
	if err != nil {
		t.Fatalf("BuildPollRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParsePollResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParsePollResponse: %v", err)
	}
	if result.Status != "completed" {
		t.Errorf("Status = %q, want %q", result.Status, "completed")
	}
	if result.VideoURL != "https://mock.test/mm-vid.mp4" {
		t.Errorf("VideoURL = %q, want %q", result.VideoURL, "https://mock.test/mm-vid.mp4")
	}
}

func TestRoundTrip_MiniMaxVideo_PollFailed(t *testing.T) {
	mockResp := `{"status":"failed","error_msg":"generation failed"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &MiniMaxVideoAdapter{}
	config := &AIConfig{
		Provider: "minimax",
		BaseURL:  srv.URL,
		APIKey:   "test-mm-vid-key",
	}

	req, err := a.BuildPollRequest(config, "task-mm-vid-001")
	if err != nil {
		t.Fatalf("BuildPollRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParsePollResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParsePollResponse: %v", err)
	}
	if result.Status != "failed" {
		t.Errorf("Status = %q, want %q", result.Status, "failed")
	}
	if !strings.Contains(result.Error, "generation failed") {
		t.Errorf("Error = %q, want to contain %q", result.Error, "generation failed")
	}
}

// =================================================================
// VolcEngine Video
// =================================================================

func TestRoundTrip_VolcEngineVideo_Async(t *testing.T) {
	mockResp := `{"id":"task-volc-vid-001"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if !strings.Contains(r.URL.Path, "/api/v3/contents/generations/tasks") {
			t.Errorf("URL path = %q, want to contain /api/v3/contents/generations/tasks", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &VolcEngineVideoAdapter{}
	config := &AIConfig{
		Provider: "volcengine",
		BaseURL:  srv.URL,
		APIKey:   "test-volc-vid-key",
		Model:    "test-volc-model",
	}
	record := &VideoGenRecord{
		ID:            1,
		Model:         "test-volc-model",
		Prompt:        "a bird flying",
		Duration:      5,
		AspectRatio:   "16:9",
		ReferenceMode: "none",
	}

	req, err := a.BuildGenerateRequest(config, record)
	if err != nil {
		t.Fatalf("BuildGenerateRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParseGenerateResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParseGenerateResponse: %v", err)
	}
	if !result.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if result.TaskID != "task-volc-vid-001" {
		t.Errorf("TaskID = %q, want %q", result.TaskID, "task-volc-vid-001")
	}
}

func TestRoundTrip_VolcEngineVideo_PollSucceeded(t *testing.T) {
	mockResp := `{"status":"succeeded","content":{"video_url":"https://mock.test/volc-vid.mp4"}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("method = %q, want GET", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &VolcEngineVideoAdapter{}
	config := &AIConfig{
		Provider: "volcengine",
		BaseURL:  srv.URL,
		APIKey:   "test-volc-vid-key",
	}

	req, err := a.BuildPollRequest(config, "task-volc-vid-001")
	if err != nil {
		t.Fatalf("BuildPollRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParsePollResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParsePollResponse: %v", err)
	}
	if result.Status != "completed" {
		t.Errorf("Status = %q, want %q", result.Status, "completed")
	}
	if result.VideoURL != "https://mock.test/volc-vid.mp4" {
		t.Errorf("VideoURL = %q, want %q", result.VideoURL, "https://mock.test/volc-vid.mp4")
	}
}

func TestRoundTrip_VolcEngineVideo_PollFailed(t *testing.T) {
	mockResp := `{"status":"failed","error":{"message":"timeout"}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &VolcEngineVideoAdapter{}
	config := &AIConfig{
		Provider: "volcengine",
		BaseURL:  srv.URL,
		APIKey:   "test-volc-vid-key",
	}

	req, err := a.BuildPollRequest(config, "task-volc-vid-001")
	if err != nil {
		t.Fatalf("BuildPollRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParsePollResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParsePollResponse: %v", err)
	}
	if result.Status != "failed" {
		t.Errorf("Status = %q, want %q", result.Status, "failed")
	}
	if !strings.Contains(result.Error, "timeout") {
		t.Errorf("Error = %q, want to contain %q", result.Error, "timeout")
	}
}

// =================================================================
// Vidu Video
// =================================================================

func TestRoundTrip_ViduVideo_Async(t *testing.T) {
	mockResp := `{"task_id":"task-vidu-001"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		// Vidu uses "Token" scheme, NOT "Bearer"
		if got := r.Header.Get("Authorization"); got != "Token test-vidu-key" {
			t.Errorf("Authorization = %q, want %q", got, "Token test-vidu-key")
		}
		if !strings.Contains(r.URL.Path, "/ent/v2/img2video") {
			t.Errorf("URL path = %q, want to contain /ent/v2/img2video", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &ViduVideoAdapter{}
	config := &AIConfig{
		Provider: "vidu",
		BaseURL:  srv.URL,
		APIKey:   "test-vidu-key",
		Model:    "viduq3-turbo",
	}
	record := &VideoGenRecord{
		ID:            1,
		Prompt:        "a dog running",
		Duration:      4,
		AspectRatio:   "16:9",
		ReferenceMode: "single",
		ImageURL:      "https://ref.test/dog.jpg",
	}

	req, err := a.BuildGenerateRequest(config, record)
	if err != nil {
		t.Fatalf("BuildGenerateRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParseGenerateResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParseGenerateResponse: %v", err)
	}
	if !result.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if result.TaskID != "task-vidu-001" {
		t.Errorf("TaskID = %q, want %q", result.TaskID, "task-vidu-001")
	}
}

// =================================================================
// Ali Video
// =================================================================

func TestRoundTrip_AliVideo_Async(t *testing.T) {
	mockResp := `{"output":{"task_id":"task-ali-vid-001","task_status":"PENDING"}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &AliVideoAdapter{}
	config := &AIConfig{
		Provider: "ali",
		BaseURL:  srv.URL,
		APIKey:   "test-ali-key",
		Model:    "test-ali-vid-model",
	}
	record := &VideoGenRecord{
		ID:            1,
		Model:         "test-ali-vid-model",
		Prompt:        "a mountain scene",
		Duration:      5,
		AspectRatio:   "16:9",
		ReferenceMode: "none",
	}

	req, err := a.BuildGenerateRequest(config, record)
	if err != nil {
		t.Fatalf("BuildGenerateRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParseGenerateResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParseGenerateResponse: %v", err)
	}
	if !result.IsAsync {
		t.Error("IsAsync = false, want true")
	}
	if result.TaskID != "task-ali-vid-001" {
		t.Errorf("TaskID = %q, want %q", result.TaskID, "task-ali-vid-001")
	}
}

func TestRoundTrip_AliVideo_Sync(t *testing.T) {
	mockResp := `{"output":{"video_url":"https://mock.test/ali-vid.mp4"}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &AliVideoAdapter{}
	config := &AIConfig{
		Provider: "ali",
		BaseURL:  srv.URL,
		APIKey:   "test-ali-key",
	}
	record := &VideoGenRecord{
		ID:            1,
		Model:         "test-ali-vid-model",
		Prompt:        "a sunset",
		Duration:      5,
		AspectRatio:   "16:9",
		ReferenceMode: "none",
	}

	req, err := a.BuildGenerateRequest(config, record)
	if err != nil {
		t.Fatalf("BuildGenerateRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParseGenerateResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParseGenerateResponse: %v", err)
	}
	if result.IsAsync {
		t.Error("IsAsync = true, want false")
	}
	if result.VideoURL != "https://mock.test/ali-vid.mp4" {
		t.Errorf("VideoURL = %q, want %q", result.VideoURL, "https://mock.test/ali-vid.mp4")
	}
}

func TestRoundTrip_AliVideo_PollSucceeded(t *testing.T) {
	mockResp := `{"output":{"task_status":"SUCCEEDED","video_url":"https://mock.test/ali-vid-poll.mp4"}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("method = %q, want GET", r.Method)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &AliVideoAdapter{}
	config := &AIConfig{
		Provider: "ali",
		BaseURL:  srv.URL,
		APIKey:   "test-ali-key",
	}

	req, err := a.BuildPollRequest(config, "task-ali-vid-001")
	if err != nil {
		t.Fatalf("BuildPollRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParsePollResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParsePollResponse: %v", err)
	}
	if result.Status != "completed" {
		t.Errorf("Status = %q, want %q", result.Status, "completed")
	}
	if result.VideoURL != "https://mock.test/ali-vid-poll.mp4" {
		t.Errorf("VideoURL = %q, want %q", result.VideoURL, "https://mock.test/ali-vid-poll.mp4")
	}
}

func TestRoundTrip_AliVideo_PollFailed(t *testing.T) {
	mockResp := `{"output":{"task_status":"FAILED"},"message":"internal error"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &AliVideoAdapter{}
	config := &AIConfig{
		Provider: "ali",
		BaseURL:  srv.URL,
		APIKey:   "test-ali-key",
	}

	req, err := a.BuildPollRequest(config, "task-ali-vid-001")
	if err != nil {
		t.Fatalf("BuildPollRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParsePollResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParsePollResponse: %v", err)
	}
	if result.Status != "failed" {
		t.Errorf("Status = %q, want %q", result.Status, "failed")
	}
	if !strings.Contains(result.Error, "internal error") {
		t.Errorf("Error = %q, want to contain %q", result.Error, "internal error")
	}
}

// =================================================================
// MiniMax TTS
// =================================================================

func TestRoundTrip_MiniMaxTTS_Success(t *testing.T) {
	mockResp := `{
		"base_resp": {"status_code": 0},
		"data": {
			"audio": "48656c6c6f",
			"extra_info": {
				"audio_length": 5000,
				"audio_sample_rate": 32000,
				"bitrate": 128000,
				"audio_format": "mp3",
				"audio_channel": 1
			}
		}
	}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-tts-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-tts-key")
		}
		if !strings.Contains(r.URL.Path, "/v1/t2a_v2") {
			t.Errorf("URL path = %q, want to contain /v1/t2a_v2", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &MiniMaxTTSAdapter{}
	config := &AIConfig{
		Provider: "minimax",
		BaseURL:  srv.URL,
		APIKey:   "test-tts-key",
		Model:    "speech-2.8-hd",
	}
	params := map[string]interface{}{
		"text":    "Hello world",
		"voice":   "test-voice-001",
		"speed":   1.0,
		"emotion": "happy",
	}

	req, err := a.BuildGenerateRequest(config, params)
	if err != nil {
		t.Fatalf("BuildGenerateRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	result, err := a.ParseResponse(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ParseResponse: %v", err)
	}
	if result.AudioHex != "48656c6c6f" {
		t.Errorf("AudioHex = %q, want %q", result.AudioHex, "48656c6c6f")
	}
	if result.AudioLength != 5000 {
		t.Errorf("AudioLength = %d, want %d", result.AudioLength, 5000)
	}
	if result.SampleRate != 32000 {
		t.Errorf("SampleRate = %d, want %d", result.SampleRate, 32000)
	}
	if result.Format != "mp3" {
		t.Errorf("Format = %q, want %q", result.Format, "mp3")
	}
}

func TestRoundTrip_MiniMaxTTS_Error(t *testing.T) {
	mockResp := `{"base_resp":{"status_code":1001,"status_msg":"invalid voice"}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &MiniMaxTTSAdapter{}
	config := &AIConfig{
		Provider: "minimax",
		BaseURL:  srv.URL,
		APIKey:   "test-tts-key",
	}
	params := map[string]interface{}{
		"text":  "Hello world",
		"voice": "bad-voice",
	}

	req, err := a.BuildGenerateRequest(config, params)
	if err != nil {
		t.Fatalf("BuildGenerateRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	_, err = a.ParseResponse(json.RawMessage(body))
	if err == nil {
		t.Fatal("ParseResponse should return error, got nil")
	}
	if !strings.Contains(err.Error(), "invalid voice") {
		t.Errorf("error = %q, want to contain %q", err.Error(), "invalid voice")
	}
}
