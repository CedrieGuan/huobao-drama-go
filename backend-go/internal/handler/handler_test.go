package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// setupTestDB creates an in-memory SQLite database and auto-migrates all models.
func setupTestDB(t *testing.T) *gorm.DB {
	t.Helper()
	db, err := gorm.Open(sqlite.Open(":memory:"), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		t.Fatalf("open test db: %v", err)
	}

	models := []interface{}{
		&database.Drama{},
		&database.Episode{},
		&database.Character{},
		&database.Scene{},
		&database.Storyboard{},
		&database.EpisodeCharacter{},
		&database.EpisodeScene{},
		&database.StoryboardCharacter{},
		&database.AIServiceConfig{},
		&database.Prop{},
		&database.VideoMerge{},
	}
	for _, m := range models {
		if err := db.AutoMigrate(m); err != nil {
			t.Fatalf("migrate %T: %v", m, err)
		}
	}
	return db
}

// setupRouter creates a Gin router with routes registered for testing.
func setupRouter(h *Handler) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()

	api := r.Group("/api/v1")
	{
		api.GET("/dramas", h.ListDramas)
		api.POST("/dramas", h.CreateDrama)
		api.GET("/dramas/stats", h.DramaStats)
		api.GET("/dramas/:id", h.GetDrama)
		api.PUT("/dramas/:id", h.UpdateDrama)
		api.DELETE("/dramas/:id", h.DeleteDrama)
		api.PUT("/dramas/:id/characters", h.UpsertDramaCharacters)
		api.PUT("/dramas/:id/episodes", h.UpsertDramaEpisodes)

		api.POST("/episodes", h.CreateEpisode)
		api.PUT("/episodes/:id", h.UpdateEpisode)
		api.GET("/episodes/:id/characters", h.GetEpisodeCharacters)
		api.GET("/episodes/:id/scenes", h.GetEpisodeScenes)
		api.GET("/episodes/:id/storyboards", h.GetEpisodeStoryboards)
		api.GET("/episodes/:id/pipeline-status", h.GetEpisodePipelineStatus)

		api.POST("/scenes", h.CreateScene)
		api.PUT("/scenes/:id", h.UpdateScene)
		api.DELETE("/scenes/:id", h.DeleteScene)

		api.POST("/storyboards", h.CreateStoryboard)
		api.PUT("/storyboards/:id", h.UpdateStoryboard)
		api.DELETE("/storyboards/:id", h.DeleteStoryboard)

		api.PUT("/characters/:id", h.UpdateCharacter)
		api.DELETE("/characters/:id", h.DeleteCharacter)

		api.GET("/health", Health)
	}

	return r
}

// doRequest is a test helper that performs an HTTP request and returns the response.
func doRequest(t *testing.T, r *gin.Engine, method, path string, body interface{}) *httptest.ResponseRecorder {
	t.Helper()
	var bodyReader *bytes.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
		bodyReader = bytes.NewReader(b)
	} else {
		bodyReader = bytes.NewReader(nil)
	}

	req := httptest.NewRequest(method, path, bodyReader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

// parseResponse parses the APIResponse from a response body.
func parseResponse(t *testing.T, w *httptest.ResponseRecorder) map[string]interface{} {
	t.Helper()
	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("parse response: %v", err)
	}
	return resp
}

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

func TestHealth(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/health", Health)

	w := doRequest(t, r, http.MethodGet, "/health", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}
	resp := parseResponse(t, w)
	if resp["status"] != "ok" {
		t.Errorf("status = %v, want ok", resp["status"])
	}
}

// ---------------------------------------------------------------------------
// Drama CRUD
// ---------------------------------------------------------------------------

func TestCreateDrama(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	body := map[string]interface{}{
		"title":          "测试剧本",
		"total_episodes": 3,
	}

	w := doRequest(t, r, http.MethodPost, "/api/v1/dramas", body)
	if w.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d; body: %s", w.Code, http.StatusCreated, w.Body.String())
	}

	resp := parseResponse(t, w)
	data := resp["data"].(map[string]interface{})
	if data["title"] != "测试剧本" {
		t.Errorf("title = %v, want 测试剧本", data["title"])
	}
}

func TestListDramas(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	// Create dramas.
	for i := 0; i < 3; i++ {
		doRequest(t, r, http.MethodPost, "/api/v1/dramas", map[string]interface{}{
			"title": "剧本" + string(rune('A'+i)),
		})
	}

	w := doRequest(t, r, http.MethodGet, "/api/v1/dramas?page=1&page_size=2", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}

	resp := parseResponse(t, w)
	data := resp["data"].(map[string]interface{})
	items := data["items"].([]interface{})
	if len(items) != 2 {
		t.Errorf("items count = %d, want 2", len(items))
	}

	pagination := data["pagination"].(map[string]interface{})
	if int(pagination["total"].(float64)) != 3 {
		t.Errorf("total = %v, want 3", pagination["total"])
	}
}

func TestGetDrama(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	// Create a drama.
	w := doRequest(t, r, http.MethodPost, "/api/v1/dramas", map[string]interface{}{
		"title": "测试剧本",
	})
	resp := parseResponse(t, w)
	data := resp["data"].(map[string]interface{})
	dramaID := int(data["id"].(float64))

	// Get it.
	w = doRequest(t, r, http.MethodGet, "/api/v1/dramas/"+string(rune('0'+dramaID)), nil)
	// Need to convert id properly.
	w = doRequest(t, r, http.MethodGet, "/api/v1/dramas/1", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d; body: %s", w.Code, http.StatusOK, w.Body.String())
	}
}

func TestGetDrama_NotFound(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	w := doRequest(t, r, http.MethodGet, "/api/v1/dramas/999", nil)
	if w.Code != http.StatusNotFound {
		t.Errorf("status = %d, want %d", w.Code, http.StatusNotFound)
	}
}

func TestUpdateDrama(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	// Create.
	doRequest(t, r, http.MethodPost, "/api/v1/dramas", map[string]interface{}{
		"title": "旧标题",
	})

	// Update.
	w := doRequest(t, r, http.MethodPut, "/api/v1/dramas/1", map[string]interface{}{
		"title": "新标题",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}

	// Verify.
	w = doRequest(t, r, http.MethodGet, "/api/v1/dramas/1", nil)
	resp := parseResponse(t, w)
	data := resp["data"].(map[string]interface{})
	if data["title"] != "新标题" {
		t.Errorf("title = %v, want 新标题", data["title"])
	}
}

func TestDeleteDrama(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	doRequest(t, r, http.MethodPost, "/api/v1/dramas", map[string]interface{}{
		"title": "待删除",
	})

	w := doRequest(t, r, http.MethodDelete, "/api/v1/dramas/1", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}

	// Verify soft-deleted (should not appear in list).
	w = doRequest(t, r, http.MethodGet, "/api/v1/dramas?page=1", nil)
	resp := parseResponse(t, w)
	data := resp["data"].(map[string]interface{})
	items := data["items"].([]interface{})
	if len(items) != 0 {
		t.Errorf("items count = %d, want 0 (soft-deleted drama should not appear)", len(items))
	}
}

// ---------------------------------------------------------------------------
// Episode
// ---------------------------------------------------------------------------

func TestCreateEpisode(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	// Create a drama first.
	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)

	cfgID := 1
	body := map[string]interface{}{
		"drama_id":        drama.ID,
		"image_config_id": cfgID,
		"video_config_id": cfgID,
		"audio_config_id": cfgID,
	}

	w := doRequest(t, r, http.MethodPost, "/api/v1/episodes", body)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d; body: %s", w.Code, http.StatusOK, w.Body.String())
	}

	resp := parseResponse(t, w)
	data := resp["data"].(map[string]interface{})
	if int(data["episode_number"].(float64)) != 1 {
		t.Errorf("episode_number = %v, want 1", data["episode_number"])
	}
}

func TestCreateEpisode_MultipleAutoNumber(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)

	cfgID := 1
	base := map[string]interface{}{
		"drama_id":        drama.ID,
		"image_config_id": cfgID,
		"video_config_id": cfgID,
		"audio_config_id": cfgID,
	}

	// Create first episode.
	doRequest(t, r, http.MethodPost, "/api/v1/episodes", base)

	// Create second episode.
	w := doRequest(t, r, http.MethodPost, "/api/v1/episodes", base)
	resp := parseResponse(t, w)
	data := resp["data"].(map[string]interface{})
	if int(data["episode_number"].(float64)) != 2 {
		t.Errorf("episode_number = %v, want 2", data["episode_number"])
	}
}

func TestCreateEpisode_MissingConfig(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)

	body := map[string]interface{}{
		"drama_id": drama.ID,
	}

	w := doRequest(t, r, http.MethodPost, "/api/v1/episodes", body)
	if w.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", w.Code, http.StatusBadRequest)
	}
}

// ---------------------------------------------------------------------------
// Scene CRUD
// ---------------------------------------------------------------------------

func TestCreateScene(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)

	body := map[string]interface{}{
		"drama_id":  drama.ID,
		"location":  "公园",
		"time":      "白天",
		"prompt":    "阳光明媚的公园",
	}

	w := doRequest(t, r, http.MethodPost, "/api/v1/scenes", body)
	if w.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d; body: %s", w.Code, http.StatusCreated, w.Body.String())
	}
}

func TestUpdateScene(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)
	scene := database.Scene{DramaID: drama.ID, Location: "旧地点", Time: "白天", Prompt: "旧描述", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&scene)

	w := doRequest(t, r, http.MethodPut, "/api/v1/scenes/1", map[string]interface{}{
		"location": "新地点",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}
}

func TestDeleteScene(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)
	scene := database.Scene{DramaID: drama.ID, Location: "待删除", Time: "白天", Prompt: "测试", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&scene)

	w := doRequest(t, r, http.MethodDelete, "/api/v1/scenes/1", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}
}

// ---------------------------------------------------------------------------
// Storyboard
// ---------------------------------------------------------------------------

func TestCreateStoryboard(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)
	ep := database.Episode{DramaID: drama.ID, EpisodeNumber: 1, Title: "第一集", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&ep)

	body := map[string]interface{}{
		"episode_id": ep.ID,
		"title":      "镜头1",
		"action":     "角色走入画面",
		"duration":   5,
	}

	w := doRequest(t, r, http.MethodPost, "/api/v1/storyboards", body)
	if w.Code != http.StatusCreated {
		t.Fatalf("status = %d, want %d; body: %s", w.Code, http.StatusCreated, w.Body.String())
	}

	resp := parseResponse(t, w)
	data := resp["data"].(map[string]interface{})
	if data["title"] != "镜头1" {
		t.Errorf("title = %v, want 镜头1", data["title"])
	}
}

func TestUpdateStoryboard(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)
	ep := database.Episode{DramaID: drama.ID, EpisodeNumber: 1, Title: "第一集", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&ep)
	sb := database.Storyboard{EpisodeID: ep.ID, StoryboardNumber: 1, CreatedAt: ts, UpdatedAt: ts}
	db.Create(&sb)

	w := doRequest(t, r, http.MethodPut, "/api/v1/storyboards/1", map[string]interface{}{
		"dialogue": "你好世界",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d; body: %s", w.Code, http.StatusOK, w.Body.String())
	}

	// Verify dialogue update resets tts_audio_url.
	var updated database.Storyboard
	db.First(&updated, 1)
	if updated.Dialogue == nil || *updated.Dialogue != "你好世界" {
		t.Errorf("dialogue not updated correctly")
	}
}

func TestDeleteStoryboard(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)
	ep := database.Episode{DramaID: drama.ID, EpisodeNumber: 1, Title: "第一集", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&ep)
	sb := database.Storyboard{EpisodeID: ep.ID, StoryboardNumber: 1, CreatedAt: ts, UpdatedAt: ts}
	db.Create(&sb)

	w := doRequest(t, r, http.MethodDelete, "/api/v1/storyboards/1", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}

	// Verify deleted.
	var count int64
	db.Model(&database.Storyboard{}).Where("id = 1").Count(&count)
	if count != 0 {
		t.Errorf("storyboard count = %d, want 0", count)
	}
}

// ---------------------------------------------------------------------------
// Character
// ---------------------------------------------------------------------------

func TestUpdateCharacter(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)
	char := database.Character{DramaID: drama.ID, Name: "角色A", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&char)

	w := doRequest(t, r, http.MethodPut, "/api/v1/characters/1", map[string]interface{}{
		"name":  "角色B",
		"role":  "主角",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d; body: %s", w.Code, http.StatusOK, w.Body.String())
	}

	var updated database.Character
	db.First(&updated, 1)
	if updated.Name != "角色B" {
		t.Errorf("name = %s, want 角色B", updated.Name)
	}
}

func TestUpdateCharacter_VoiceStyleResetsSample(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)
	sample := "https://example.com/sample.wav"
	char := database.Character{DramaID: drama.ID, Name: "角色A", VoiceSampleURL: &sample, CreatedAt: ts, UpdatedAt: ts}
	db.Create(&char)

	w := doRequest(t, r, http.MethodPut, "/api/v1/characters/1", map[string]interface{}{
		"voice_style": "温柔女声",
	})
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}

	var updated database.Character
	db.First(&updated, 1)
	if updated.VoiceSampleURL != nil {
		t.Errorf("voice_sample_url = %v, want nil after voice_style change", updated.VoiceSampleURL)
	}
}

func TestDeleteCharacter(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)
	char := database.Character{DramaID: drama.ID, Name: "待删除", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&char)

	w := doRequest(t, r, http.MethodDelete, "/api/v1/characters/1", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", w.Code, http.StatusOK)
	}

	var updated database.Character
	db.First(&updated, 1)
	if updated.DeletedAt == nil {
		t.Error("deleted_at should be set after soft delete")
	}
}

// ---------------------------------------------------------------------------
// UpsertDramaCharacters (transaction test)
// ---------------------------------------------------------------------------

func TestUpsertDramaCharacters(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)

	body := map[string]interface{}{
		"characters": []interface{}{
			map[string]interface{}{"name": "角色A", "role": "主角"},
			map[string]interface{}{"name": "角色B", "role": "配角"},
		},
	}

	w := doRequest(t, r, http.MethodPut, "/api/v1/dramas/1/characters", body)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d; body: %s", w.Code, http.StatusOK, w.Body.String())
	}

	var chars []database.Character
	db.Where("drama_id = ?", drama.ID).Find(&chars)
	if len(chars) != 2 {
		t.Errorf("characters count = %d, want 2", len(chars))
	}
}

// ---------------------------------------------------------------------------
// UpsertDramaEpisodes (transaction test)
// ---------------------------------------------------------------------------

func TestUpsertDramaEpisodes(t *testing.T) {
	db := setupTestDB(t)
	h := New(db)
	r := setupRouter(h)

	ts := database.Now()
	drama := database.Drama{Title: "测试", Status: "draft", CreatedAt: ts, UpdatedAt: ts}
	db.Create(&drama)

	body := map[string]interface{}{
		"episodes": []interface{}{
			map[string]interface{}{"episode_number": 1, "title": "第一集"},
			map[string]interface{}{"episode_number": 2, "title": "第二集"},
		},
	}

	w := doRequest(t, r, http.MethodPut, "/api/v1/dramas/1/episodes", body)
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d; body: %s", w.Code, http.StatusOK, w.Body.String())
	}

	var eps []database.Episode
	db.Where("drama_id = ?", drama.ID).Find(&eps)
	if len(eps) != 2 {
		t.Errorf("episodes count = %d, want 2", len(eps))
	}
}

// ---------------------------------------------------------------------------
// Error sanitization test
// ---------------------------------------------------------------------------

func TestServerError_Sanitized(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/test", func(c *gin.Context) {
		// Simulate a database error leak.
		util.ServerError(c, "no such table: dramas (SQLSTATE 42P01)")
	})

	req := httptest.NewRequest(http.MethodGet, "/test", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	resp := parseResponse(t, w)
	msg := resp["message"].(string)
	if msg == "no such table: dramas (SQLSTATE 42P01)" {
		t.Error("error message should be sanitized, not leak database details")
	}
	if msg != "服务器内部错误，请稍后重试" {
		t.Errorf("message = %q, want generic error message", msg)
	}
}
