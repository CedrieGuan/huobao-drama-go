package adapter

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// doAdapterRequest sends a ProviderRequest via http.DefaultClient and returns
// the raw HTTP response together with the fully-read response body.
func doAdapterRequest(t *testing.T, req *ProviderRequest) (*http.Response, []byte) {
	t.Helper()
	var bodyReader io.Reader
	if req.Body != nil {
		b, err := json.Marshal(req.Body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
		bodyReader = bytes.NewReader(b)
	}
	httpReq, err := http.NewRequest(req.Method, req.URL, bodyReader)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	for k, v := range req.Headers {
		httpReq.Header.Set(k, v)
	}
	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		t.Fatalf("do request: %v", err)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	resp.Body.Close()
	return resp, body
}

// =================================================================
// MiniMax Image
// =================================================================

func TestRoundTrip_MiniMaxImage_Sync(t *testing.T) {
	mockResp := `{"data":[{"url":"https://mock.test/sync-img.png"}]}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-minimax-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-minimax-key")
		}
		if got := r.Header.Get("Content-Type"); got != "application/json" {
			t.Errorf("Content-Type = %q, want %q", got, "application/json")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &MiniMaxImageAdapter{}
	config := &AIConfig{
		Provider: "minimax",
		BaseURL:  srv.URL,
		APIKey:   "test-minimax-key",
		Model:    "test-model",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "test-model",
		Prompt: "a sunset",
		Size:   "1920x1080",
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
	if result.ImageURL != "https://mock.test/sync-img.png" {
		t.Errorf("ImageURL = %q, want %q", result.ImageURL, "https://mock.test/sync-img.png")
	}
}

func TestRoundTrip_MiniMaxImage_Async(t *testing.T) {
	mockResp := `{"task_id":"task-minimax-img-001"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-minimax-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-minimax-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &MiniMaxImageAdapter{}
	config := &AIConfig{
		Provider: "minimax",
		BaseURL:  srv.URL,
		APIKey:   "test-minimax-key",
		Model:    "test-model",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "test-model",
		Prompt: "a sunset",
		Size:   "1920x1080",
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
	if result.TaskID != "task-minimax-img-001" {
		t.Errorf("TaskID = %q, want %q", result.TaskID, "task-minimax-img-001")
	}
}

func TestRoundTrip_MiniMaxImage_Poll(t *testing.T) {
	mockResp := `{"status":"completed","image_url":"https://mock.test/poll-img.png"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("method = %q, want GET", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-minimax-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-minimax-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &MiniMaxImageAdapter{}
	config := &AIConfig{
		Provider: "minimax",
		BaseURL:  srv.URL,
		APIKey:   "test-minimax-key",
		Model:    "test-model",
	}

	req, err := a.BuildPollRequest(config, "task-minimax-img-001")
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
	if result.ImageURL != "https://mock.test/poll-img.png" {
		t.Errorf("ImageURL = %q, want %q", result.ImageURL, "https://mock.test/poll-img.png")
	}
}

// =================================================================
// OpenAI Image
// =================================================================

func TestRoundTrip_OpenAIImage_URLMode(t *testing.T) {
	mockResp := `{"data":[{"url":"https://mock.test/openai-img.png"}]}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-openai-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-openai-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &OpenAIImageAdapter{}
	config := &AIConfig{
		Provider: "openai",
		BaseURL:  srv.URL,
		APIKey:   "test-openai-key",
		Model:    "dall-e-3",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "dall-e-3",
		Prompt: "a sunset",
		Size:   "1024x1024",
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
	if result.ImageURL != "https://mock.test/openai-img.png" {
		t.Errorf("ImageURL = %q, want %q", result.ImageURL, "https://mock.test/openai-img.png")
	}
}

func TestRoundTrip_OpenAIImage_B64Mode(t *testing.T) {
	mockResp := `{"data":[{"b64_json":"iVBORw0KGgo="}]}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-openai-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-openai-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &OpenAIImageAdapter{}
	config := &AIConfig{
		Provider: "openai",
		BaseURL:  srv.URL,
		APIKey:   "test-openai-key",
		Model:    "dall-e-3",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "dall-e-3",
		Prompt: "a sunset",
		Size:   "1024x1024",
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

	// Verify ExtractImageBase64 returns the expected data.
	b64, err := a.ExtractImageBase64(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ExtractImageBase64: %v", err)
	}
	if b64 == nil {
		t.Fatal("ExtractImageBase64 returned nil, want non-nil")
	}
	if b64.Data != "iVBORw0KGgo=" {
		t.Errorf("Data = %q, want %q", b64.Data, "iVBORw0KGgo=")
	}
	if b64.MimeType != "image/png" {
		t.Errorf("MimeType = %q, want %q", b64.MimeType, "image/png")
	}
}

func TestRoundTrip_OpenAIImage_Async(t *testing.T) {
	mockResp := `{"task_id":"task-openai-001"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-openai-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-openai-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &OpenAIImageAdapter{}
	config := &AIConfig{
		Provider: "openai",
		BaseURL:  srv.URL,
		APIKey:   "test-openai-key",
		Model:    "dall-e-3",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "dall-e-3",
		Prompt: "a sunset",
		Size:   "1024x1024",
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
}

func TestRoundTrip_OpenAIImage_Poll(t *testing.T) {
	mockResp := `{"status":"completed","data":[{"url":"https://mock.test/openai-poll.png"}]}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("method = %q, want GET", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-openai-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-openai-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &OpenAIImageAdapter{}
	config := &AIConfig{
		Provider: "openai",
		BaseURL:  srv.URL,
		APIKey:   "test-openai-key",
		Model:    "dall-e-3",
	}

	req, err := a.BuildPollRequest(config, "task-openai-001")
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
	if result.ImageURL != "https://mock.test/openai-poll.png" {
		t.Errorf("ImageURL = %q, want %q", result.ImageURL, "https://mock.test/openai-poll.png")
	}
}

// =================================================================
// Gemini Image
// =================================================================

func TestRoundTrip_GeminiImage_SyncBase64(t *testing.T) {
	mockResp := `{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"base64datahere"}}]}}]}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("x-goog-api-key"); got != "test-gemini-key" {
			t.Errorf("x-goog-api-key = %q, want %q", got, "test-gemini-key")
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-gemini-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-gemini-key")
		}
		if !strings.Contains(r.URL.Path, ":generateContent") {
			t.Errorf("path = %q, want to contain :generateContent", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &GeminiImageAdapter{}
	config := &AIConfig{
		Provider: "gemini",
		BaseURL:  srv.URL,
		APIKey:   "test-gemini-key",
		Model:    "gemini-2.5-flash-image",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "gemini-2.5-flash-image",
		Prompt: "a cat",
		Size:   "1024x1024",
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

	// Verify ExtractImageBase64 returns the expected data.
	b64, err := a.ExtractImageBase64(json.RawMessage(body))
	if err != nil {
		t.Fatalf("ExtractImageBase64: %v", err)
	}
	if b64 == nil {
		t.Fatal("ExtractImageBase64 returned nil, want non-nil")
	}
	if b64.Data != "base64datahere" {
		t.Errorf("Data = %q, want %q", b64.Data, "base64datahere")
	}
	if b64.MimeType != "image/png" {
		t.Errorf("MimeType = %q, want %q", b64.MimeType, "image/png")
	}
}

func TestRoundTrip_GeminiImage_Error(t *testing.T) {
	mockResp := `{"error":{"message":"API key invalid"}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &GeminiImageAdapter{}
	config := &AIConfig{
		Provider: "gemini",
		BaseURL:  srv.URL,
		APIKey:   "test-gemini-key",
		Model:    "gemini-2.5-flash-image",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "gemini-2.5-flash-image",
		Prompt: "a cat",
		Size:   "1024x1024",
	}

	req, err := a.BuildGenerateRequest(config, record)
	if err != nil {
		t.Fatalf("BuildGenerateRequest: %v", err)
	}
	_, body := doAdapterRequest(t, req)

	_, err = a.ParseGenerateResponse(json.RawMessage(body))
	if err == nil {
		t.Fatal("ParseGenerateResponse returned nil error, want error containing 'API key invalid'")
	}
	if !strings.Contains(err.Error(), "API key invalid") {
		t.Errorf("error = %q, want to contain %q", err.Error(), "API key invalid")
	}
}

// =================================================================
// VolcEngine Image
// =================================================================

func TestRoundTrip_VolcEngineImage_Sync(t *testing.T) {
	mockResp := `{"data":[{"url":"https://mock.test/volc-img.png"}]}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-volc-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-volc-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &VolcEngineImageAdapter{}
	config := &AIConfig{
		Provider: "volcengine",
		BaseURL:  srv.URL,
		APIKey:   "test-volc-key",
		Model:    "doubao-seedream-5-0-lite",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "test-model",
		Prompt: "a sunset",
		Size:   "1920x1080",
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
	if result.ImageURL != "https://mock.test/volc-img.png" {
		t.Errorf("ImageURL = %q, want %q", result.ImageURL, "https://mock.test/volc-img.png")
	}
}

func TestRoundTrip_VolcEngineImage_Async(t *testing.T) {
	mockResp := `{"task_id":"task-volc-img-001"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-volc-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-volc-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &VolcEngineImageAdapter{}
	config := &AIConfig{
		Provider: "volcengine",
		BaseURL:  srv.URL,
		APIKey:   "test-volc-key",
		Model:    "doubao-seedream-5-0-lite",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "test-model",
		Prompt: "a sunset",
		Size:   "1920x1080",
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
	if result.TaskID != "task-volc-img-001" {
		t.Errorf("TaskID = %q, want %q", result.TaskID, "task-volc-img-001")
	}
}

func TestRoundTrip_VolcEngineImage_PollSucceeded(t *testing.T) {
	mockResp := `{"status":"succeeded","data":[{"url":"https://mock.test/volc-poll.png"}]}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("method = %q, want GET", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-volc-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-volc-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &VolcEngineImageAdapter{}
	config := &AIConfig{
		Provider: "volcengine",
		BaseURL:  srv.URL,
		APIKey:   "test-volc-key",
		Model:    "doubao-seedream-5-0-lite",
	}

	req, err := a.BuildPollRequest(config, "task-volc-img-001")
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
	if result.ImageURL != "https://mock.test/volc-poll.png" {
		t.Errorf("ImageURL = %q, want %q", result.ImageURL, "https://mock.test/volc-poll.png")
	}
}

func TestRoundTrip_VolcEngineImage_PollFailed(t *testing.T) {
	mockResp := `{"status":"failed","error":{"message":"NSFW content"}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("method = %q, want GET", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-volc-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-volc-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &VolcEngineImageAdapter{}
	config := &AIConfig{
		Provider: "volcengine",
		BaseURL:  srv.URL,
		APIKey:   "test-volc-key",
		Model:    "doubao-seedream-5-0-lite",
	}

	req, err := a.BuildPollRequest(config, "task-volc-img-001")
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
	if !strings.Contains(result.Error, "NSFW content") {
		t.Errorf("Error = %q, want to contain %q", result.Error, "NSFW content")
	}
}

// =================================================================
// Ali Image
// =================================================================

func TestRoundTrip_AliImage_Async(t *testing.T) {
	mockResp := `{"output":{"task_id":"task-ali-img-001","task_status":"PENDING"}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-ali-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-ali-key")
		}
		if got := r.Header.Get("X-DashScope-Async"); got != "enable" {
			t.Errorf("X-DashScope-Async = %q, want %q", got, "enable")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &AliImageAdapter{}
	config := &AIConfig{
		Provider: "ali",
		BaseURL:  srv.URL,
		APIKey:   "test-ali-key",
		Model:    "wan2.6-t2i",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "wan2.6-t2i",
		Prompt: "a sunset",
		Size:   "1920x1080",
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
	if result.TaskID != "task-ali-img-001" {
		t.Errorf("TaskID = %q, want %q", result.TaskID, "task-ali-img-001")
	}
}

func TestRoundTrip_AliImage_Sync(t *testing.T) {
	mockResp := `{"output":{"choices":[{"message":{"content":[{"image":"https://mock.test/ali-img.png"}]}}]}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-ali-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-ali-key")
		}
		if got := r.Header.Get("X-DashScope-Async"); got != "enable" {
			t.Errorf("X-DashScope-Async = %q, want %q", got, "enable")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &AliImageAdapter{}
	config := &AIConfig{
		Provider: "ali",
		BaseURL:  srv.URL,
		APIKey:   "test-ali-key",
		Model:    "wan2.6-t2i",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "wan2.6-t2i",
		Prompt: "a sunset",
		Size:   "1920x1080",
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
	if result.ImageURL != "https://mock.test/ali-img.png" {
		t.Errorf("ImageURL = %q, want %q", result.ImageURL, "https://mock.test/ali-img.png")
	}
}

func TestRoundTrip_AliImage_PollSucceeded(t *testing.T) {
	mockResp := `{"output":{"task_status":"SUCCEEDED","choices":[{"message":{"content":[{"image":"https://mock.test/ali-poll.png"}]}}]}}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("method = %q, want GET", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-ali-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-ali-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &AliImageAdapter{}
	config := &AIConfig{
		Provider: "ali",
		BaseURL:  srv.URL,
		APIKey:   "test-ali-key",
		Model:    "wan2.6-t2i",
	}

	req, err := a.BuildPollRequest(config, "task-ali-img-001")
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
	if result.ImageURL != "https://mock.test/ali-poll.png" {
		t.Errorf("ImageURL = %q, want %q", result.ImageURL, "https://mock.test/ali-poll.png")
	}
}

func TestRoundTrip_AliImage_PollFailed(t *testing.T) {
	mockResp := `{"output":{"task_status":"FAILED"},"message":"content violation"}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "GET" {
			t.Errorf("method = %q, want GET", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-ali-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-ali-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &AliImageAdapter{}
	config := &AIConfig{
		Provider: "ali",
		BaseURL:  srv.URL,
		APIKey:   "test-ali-key",
		Model:    "wan2.6-t2i",
	}

	req, err := a.BuildPollRequest(config, "task-ali-img-001")
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
	if !strings.Contains(result.Error, "content violation") {
		t.Errorf("Error = %q, want to contain %q", result.Error, "content violation")
	}
}

// =================================================================
// Chatfire Image
// =================================================================

func TestRoundTrip_ChatfireImage_URLMode(t *testing.T) {
	mockResp := `{"data":[{"url":"https://mock.test/chatfire-img.png"}]}`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			t.Errorf("method = %q, want POST", r.Method)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer test-chatfire-key" {
			t.Errorf("Authorization = %q, want %q", got, "Bearer test-chatfire-key")
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(mockResp))
	}))
	defer srv.Close()

	a := &ChatfireImageAdapter{}
	config := &AIConfig{
		Provider: "chatfire",
		BaseURL:  srv.URL,
		APIKey:   "test-chatfire-key",
		Model:    "chatfire-model",
	}
	record := &ImageGenRecord{
		ID:     1,
		Model:  "chatfire-model",
		Prompt: "a sunset",
		Size:   "1024x1024",
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
	if result.ImageURL != "https://mock.test/chatfire-img.png" {
		t.Errorf("ImageURL = %q, want %q", result.ImageURL, "https://mock.test/chatfire-img.png")
	}
}
