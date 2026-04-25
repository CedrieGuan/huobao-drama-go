package handler

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/adapter"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// POST /api/v1/images — Generate image
// ---------------------------------------------------------------------------

func (h *Handler) GenerateImage(c *gin.Context) {
	var body struct {
		StoryboardID    *int     `json:"storyboard_id"`
		DramaID         *int     `json:"drama_id"`
		SceneID         *int     `json:"scene_id"`
		CharacterID     *int     `json:"character_id"`
		Prompt          string   `json:"prompt"`
		Model           *string  `json:"model"`
		Size            *string  `json:"size"`
		ReferenceImages []string `json:"reference_images"`
		FrameType       *string  `json:"frame_type"`
		ConfigID        *int     `json:"config_id"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}
	if body.Prompt == "" {
		util.BadRequest(c, "prompt is required")
		return
	}

	// Resolve config_id: explicit > episode's image_config_id
	configID := body.ConfigID
	if configID == nil && body.StoryboardID != nil {
		var sb database.Storyboard
		if h.DB.First(&sb, *body.StoryboardID).Error == nil {
			var ep database.Episode
			if h.DB.First(&ep, sb.EpisodeID).Error == nil && ep.ImageConfigID != nil {
				configID = ep.ImageConfigID
			}
		}
	}

	aiConfig, provider, err := h.resolveAIConfig("image", configID)
	if err != nil {
		util.BadRequest(c, err.Error())
		return
	}

	refImagesJSON := "[]"
	if len(body.ReferenceImages) > 0 {
		b, _ := json.Marshal(body.ReferenceImages)
		refImagesJSON = string(b)
	}

	modelVal := ptrStr(body.Model, "")
	sizeVal := ptrStr(body.Size, "1024x1024")
	frameTypeVal := ptrStr(body.FrameType, "")

	ts := database.Now()
	record := database.ImageGeneration{
		StoryboardID:    body.StoryboardID,
		DramaID:         body.DramaID,
		SceneID:         body.SceneID,
		CharacterID:     body.CharacterID,
		FrameType:       body.FrameType,
		Provider:        &provider,
		Prompt:          &body.Prompt,
		Model:           &modelVal,
		Size:            &sizeVal,
		ReferenceImages: &refImagesJSON,
		Status:          strPtr("pending"),
		CreatedAt:       ts,
		UpdatedAt:       ts,
	}
	if err := h.DB.Create(&record).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	// Execute generation in background.
	go h.executeImageGen(record.ID, aiConfig, provider, body.Prompt, modelVal, sizeVal, frameTypeVal, body.ReferenceImages)

	util.Created(c, record)
}

// ---------------------------------------------------------------------------
// GET /api/v1/images/:id
// ---------------------------------------------------------------------------

func (h *Handler) GetImage(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}
	var record database.ImageGeneration
	if err := h.DB.First(&record, id).Error; err != nil {
		util.NotFound(c, "Image generation not found")
		return
	}
	util.Success(c, record)
}

// ---------------------------------------------------------------------------
// GET /api/v1/images — List by storyboard_id or drama_id
// ---------------------------------------------------------------------------

func (h *Handler) ListImages(c *gin.Context) {
	q := h.DB.Model(&database.ImageGeneration{})
	if v := c.Query("storyboard_id"); v != "" {
		q = q.Where("storyboard_id = ?", v)
	}
	if v := c.Query("drama_id"); v != "" {
		q = q.Where("drama_id = ?", v)
	}
	var records []database.ImageGeneration
	if err := q.Order("id DESC").Find(&records).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}
	util.Success(c, records)
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/images/:id
// ---------------------------------------------------------------------------

func (h *Handler) DeleteImage(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}
	h.DB.Delete(&database.ImageGeneration{}, id)
	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// Background image generation
// ---------------------------------------------------------------------------

func (h *Handler) executeImageGen(recordID int, aiConfig *adapter.AIConfig, provider, prompt, model, size, frameType string, refImages []string) {
	adp := adapter.GetImageAdapter(provider)
	if adp == nil {
		h.updateImageRecord(recordID, "failed", "No adapter for provider: "+provider, nil)
		return
	}

	genRecord := &adapter.ImageGenRecord{
		ID:              int64(recordID),
		Model:           model,
		Prompt:          prompt,
		Size:            size,
		FrameType:       frameType,
		ReferenceImages: refImages,
	}

	req, err := adp.BuildGenerateRequest(aiConfig, genRecord)
	if err != nil {
		h.updateImageRecord(recordID, "failed", "Build request: "+err.Error(), nil)
		return
	}

	respBody, err := doAdapterHTTPRequest(req)
	if err != nil {
		h.updateImageRecord(recordID, "failed", "HTTP: "+err.Error(), nil)
		return
	}

	genResp, err := adp.ParseGenerateResponse(respBody)
	if err != nil {
		h.updateImageRecord(recordID, "failed", "Parse: "+err.Error(), nil)
		return
	}

	if !genResp.IsAsync {
		// Sync — try to download image.
		if genResp.ImageURL != "" {
			localPath, dlErr := h.downloadToStorage(genResp.ImageURL, "images")
			updates := map[string]interface{}{
				"image_url": genResp.ImageURL, "status": "completed",
				"completed_at": database.Now(), "updated_at": database.Now(),
			}
			if dlErr == nil {
				updates["local_path"] = localPath
			}
			h.DB.Model(&database.ImageGeneration{}).Where("id = ?", recordID).Updates(updates)
		} else {
			// Try base64.
			b64, bErr := adp.ExtractImageBase64(respBody)
			if bErr == nil && b64 != nil {
				lp, sErr := h.saveBase64ToStorage(b64, "images")
				if sErr == nil {
					h.DB.Model(&database.ImageGeneration{}).Where("id = ?", recordID).Updates(map[string]interface{}{
						"local_path": lp, "status": "completed",
						"completed_at": database.Now(), "updated_at": database.Now(),
					})
				}
			}
		}
		return
	}

	// Async — save task_id and start polling.
	h.DB.Model(&database.ImageGeneration{}).Where("id = ?", recordID).Updates(map[string]interface{}{
		"task_id": genResp.TaskID, "status": "processing", "updated_at": database.Now(),
	})
	h.pollImageGen(recordID, adp, aiConfig, genResp.TaskID)
}

func (h *Handler) pollImageGen(recordID int, adp adapter.ImageProviderAdapter, aiConfig *adapter.AIConfig, taskID string) {
	for i := 0; i < 60; i++ {
		time.Sleep(5 * time.Second)
		req, err := adp.BuildPollRequest(aiConfig, taskID)
		if err != nil {
			continue
		}
		respBody, err := doAdapterHTTPRequest(req)
		if err != nil {
			continue
		}
		pollResp, err := adp.ParsePollResponse(respBody)
		if err != nil {
			continue
		}
		switch pollResp.Status {
		case "completed":
			localPath, _ := h.downloadToStorage(pollResp.ImageURL, "images")
			updates := map[string]interface{}{
				"image_url": pollResp.ImageURL, "status": "completed",
				"completed_at": database.Now(), "updated_at": database.Now(),
			}
			if localPath != "" {
				updates["local_path"] = localPath
			}
			h.DB.Model(&database.ImageGeneration{}).Where("id = ?", recordID).Updates(updates)
			// Update storyboard if linked.
			var rec database.ImageGeneration
			if h.DB.First(&rec, recordID).Error == nil && rec.StoryboardID != nil && localPath != "" {
				h.DB.Model(&database.Storyboard{}).Where("id = ?", *rec.StoryboardID).
					Update("composed_image", localPath)
			}
			return
		case "failed":
			h.updateImageRecord(recordID, "failed", pollResp.Error, nil)
			return
		}
	}
	h.updateImageRecord(recordID, "failed", "Polling timeout", nil)
}

func (h *Handler) updateImageRecord(id int, status, errMsg string, extra map[string]interface{}) {
	updates := map[string]interface{}{"status": status, "updated_at": database.Now()}
	if errMsg != "" {
		updates["error_msg"] = errMsg
	}
	for k, v := range extra {
		updates[k] = v
	}
	h.DB.Model(&database.ImageGeneration{}).Where("id = ?", id).Updates(updates)
}

// ---------------------------------------------------------------------------
// Shared helpers (used by both image and video handlers)
// ---------------------------------------------------------------------------

// resolveAIConfig finds the AI config for the given service type.
func (h *Handler) resolveAIConfig(serviceType string, configID *int) (*adapter.AIConfig, string, error) {
	var config database.AIServiceConfig
	if configID != nil {
		if err := h.DB.First(&config, *configID).Error; err != nil {
			return nil, "", fmt.Errorf("config not found: %d", *configID)
		}
	} else {
		if err := h.DB.Where("service_type = ? AND is_active = 1", serviceType).
			Order("priority DESC, id ASC").First(&config).Error; err != nil {
			return nil, "", fmt.Errorf("no active %s config found", serviceType)
		}
	}

	model := ""
	if config.Model != nil {
		var models []string
		if json.Unmarshal([]byte(*config.Model), &models) == nil && len(models) > 0 {
			model = models[0]
		}
	}

	provider := ""
	if config.Provider != nil {
		provider = *config.Provider
	}

	return &adapter.AIConfig{
		Provider: provider,
		BaseURL:  config.BaseURL,
		APIKey:   config.APIKey,
		Model:    model,
	}, provider, nil
}

// doAdapterHTTPRequest executes an HTTP request built by an adapter.
func doAdapterHTTPRequest(req *adapter.ProviderRequest) (json.RawMessage, error) {
	var bodyReader io.Reader
	if req.Body != nil {
		b, err := json.Marshal(req.Body)
		if err != nil {
			return nil, fmt.Errorf("marshal body: %w", err)
		}
		bodyReader = strings.NewReader(string(b))
	}

	httpReq, err := http.NewRequest(req.Method, req.URL, bodyReader)
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	for k, v := range req.Headers {
		httpReq.Header.Set(k, v)
	}

	resp, err := http.DefaultClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("execute: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	return json.RawMessage(respBody), nil
}

// downloadToStorage downloads a file from URL to the storage directory.
func (h *Handler) downloadToStorage(rawURL, subdir string) (string, error) {
	if h.StoragePath == "" {
		return "", fmt.Errorf("storage not configured")
	}
	resp, err := http.Get(rawURL)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("status %d", resp.StatusCode)
	}

	targetDir := filepath.Join(h.StoragePath, subdir)
	os.MkdirAll(targetDir, 0o755)

	ext := ".bin"
	ct := resp.Header.Get("Content-Type")
	switch {
	case strings.Contains(ct, "png"):
		ext = ".png"
	case strings.Contains(ct, "jpeg") || strings.Contains(ct, "jpg"):
		ext = ".jpg"
	case strings.Contains(ct, "webp"):
		ext = ".webp"
	case strings.Contains(ct, "mp4"):
		ext = ".mp4"
	case strings.Contains(ct, "mp3"):
		ext = ".mp3"
	case strings.Contains(ct, "wav"):
		ext = ".wav"
	}

	filename := fmt.Sprintf("%d%s", util.TimestampMillis(), ext)
	fullPath := filepath.Join(targetDir, filename)

	f, err := os.Create(fullPath)
	if err != nil {
		return "", err
	}
	defer f.Close()

	if _, err := io.Copy(f, resp.Body); err != nil {
		return "", err
	}

	return filepath.Join(subdir, filename), nil
}

// saveBase64ToStorage saves a base64-encoded image to the storage directory.
func (h *Handler) saveBase64ToStorage(img *adapter.Base64Image, subdir string) (string, error) {
	if h.StoragePath == "" {
		return "", fmt.Errorf("storage not configured")
	}

	decoded, err := base64.StdEncoding.DecodeString(img.Data)
	if err != nil {
		return "", fmt.Errorf("decode base64: %w", err)
	}

	targetDir := filepath.Join(h.StoragePath, subdir)
	os.MkdirAll(targetDir, 0o755)

	ext := ".png"
	if strings.Contains(img.MimeType, "jpeg") {
		ext = ".jpg"
	} else if strings.Contains(img.MimeType, "webp") {
		ext = ".webp"
	}

	filename := fmt.Sprintf("%d%s", util.TimestampMillis(), ext)
	fullPath := filepath.Join(targetDir, filename)

	if err := os.WriteFile(fullPath, decoded, 0o644); err != nil {
		return "", err
	}

	log.Printf("[image-gen] saved base64 image to %s", fullPath)
	return filepath.Join(subdir, filename), nil
}

// strPtr returns a pointer to the given string.
func strPtr(s string) *string { return &s }

// ptrStr returns the dereferenced string value or fallback if nil.
func ptrStr(p *string, fallback string) string {
	if p != nil && *p != "" {
		return *p
	}
	return fallback
}
