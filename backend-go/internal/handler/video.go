package handler

import (
	"encoding/json"
	"strconv"
	"time"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/adapter"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// POST /api/v1/videos — Generate video
// ---------------------------------------------------------------------------

func (h *Handler) GenerateVideo(c *gin.Context) {
	var body struct {
		StoryboardID       *int     `json:"storyboard_id"`
		DramaID            *int     `json:"drama_id"`
		Prompt             string   `json:"prompt"`
		Model              *string  `json:"model"`
		ReferenceMode      *string  `json:"reference_mode"`
		ImageURL           *string  `json:"image_url"`
		FirstFrameURL      *string  `json:"first_frame_url"`
		LastFrameURL       *string  `json:"last_frame_url"`
		ReferenceImageURLs []string `json:"reference_image_urls"`
		Duration           *int     `json:"duration"`
		AspectRatio        *string  `json:"aspect_ratio"`
		ConfigID           *int     `json:"config_id"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}
	if body.Prompt == "" {
		util.BadRequest(c, "prompt is required")
		return
	}

	// Resolve config_id: explicit > episode's video_config_id
	configID := body.ConfigID
	if configID == nil && body.StoryboardID != nil {
		var sb database.Storyboard
		if h.DB.First(&sb, *body.StoryboardID).Error == nil {
			var ep database.Episode
			if h.DB.First(&ep, sb.EpisodeID).Error == nil && ep.VideoConfigID != nil {
				configID = ep.VideoConfigID
			}
		}
	}

	aiConfig, provider, err := h.resolveAIConfig("video", configID)
	if err != nil {
		util.BadRequest(c, err.Error())
		return
	}

	refURLsJSON := "[]"
	if len(body.ReferenceImageURLs) > 0 {
		b, _ := json.Marshal(body.ReferenceImageURLs)
		refURLsJSON = string(b)
	}

	modelVal := ptrStr(body.Model, "")
	refMode := ptrStr(body.ReferenceMode, "none")
	imageURL := ptrStr(body.ImageURL, "")
	firstFrameURL := ptrStr(body.FirstFrameURL, "")
	lastFrameURL := ptrStr(body.LastFrameURL, "")
	aspectRatio := ptrStr(body.AspectRatio, "16:9")
	duration := 5
	if body.Duration != nil {
		duration = *body.Duration
	}

	ts := database.Now()
	record := database.VideoGeneration{
		StoryboardID:       body.StoryboardID,
		DramaID:            body.DramaID,
		Provider:           &provider,
		Prompt:             &body.Prompt,
		Model:              &modelVal,
		ReferenceMode:      &refMode,
		ImageURL:           &imageURL,
		FirstFrameURL:      &firstFrameURL,
		LastFrameURL:       &lastFrameURL,
		ReferenceImageURLs: &refURLsJSON,
		Duration:           &duration,
		AspectRatio:        &aspectRatio,
		Status:             strPtr("pending"),
		CreatedAt:          ts,
		UpdatedAt:          ts,
	}
	if err := h.DB.Create(&record).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	go h.executeVideoGen(record.ID, aiConfig, provider, body.Prompt, modelVal, refMode, imageURL, firstFrameURL, lastFrameURL, refURLsJSON, duration, aspectRatio)

	util.Created(c, record)
}

// ---------------------------------------------------------------------------
// GET /api/v1/videos/:id
// ---------------------------------------------------------------------------

func (h *Handler) GetVideo(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}
	var record database.VideoGeneration
	if err := h.DB.First(&record, id).Error; err != nil {
		util.NotFound(c, "Video generation not found")
		return
	}
	util.Success(c, record)
}

// ---------------------------------------------------------------------------
// GET /api/v1/videos — List by storyboard_id or drama_id
// ---------------------------------------------------------------------------

func (h *Handler) ListVideos(c *gin.Context) {
	q := h.DB.Model(&database.VideoGeneration{})
	if v := c.Query("storyboard_id"); v != "" {
		q = q.Where("storyboard_id = ?", v)
	}
	if v := c.Query("drama_id"); v != "" {
		q = q.Where("drama_id = ?", v)
	}
	var records []database.VideoGeneration
	if err := q.Order("id DESC").Find(&records).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}
	util.Success(c, records)
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/videos/:id
// ---------------------------------------------------------------------------

func (h *Handler) DeleteVideo(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}
	h.DB.Delete(&database.VideoGeneration{}, id)
	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// Background video generation
// ---------------------------------------------------------------------------

func (h *Handler) executeVideoGen(recordID int, aiConfig *adapter.AIConfig, provider, prompt, model, refMode, imageURL, firstFrameURL, lastFrameURL, refURLsJSON string, duration int, aspectRatio string) {
	adp := adapter.GetVideoAdapter(provider)
	if adp == nil {
		h.updateVideoRecord(recordID, "failed", "No adapter for provider: "+provider, nil)
		return
	}

	genRecord := &adapter.VideoGenRecord{
		ID:                 int64(recordID),
		Model:              model,
		Prompt:             prompt,
		ReferenceMode:      refMode,
		ImageURL:           imageURL,
		FirstFrameURL:      firstFrameURL,
		LastFrameURL:       lastFrameURL,
		ReferenceImageURLs: refURLsJSON,
		Duration:           duration,
		AspectRatio:        aspectRatio,
	}

	req, err := adp.BuildGenerateRequest(aiConfig, genRecord)
	if err != nil {
		h.updateVideoRecord(recordID, "failed", "Build request: "+err.Error(), nil)
		return
	}

	respBody, err := doAdapterHTTPRequest(req)
	if err != nil {
		h.updateVideoRecord(recordID, "failed", "HTTP: "+err.Error(), nil)
		return
	}

	genResp, err := adp.ParseGenerateResponse(respBody)
	if err != nil {
		h.updateVideoRecord(recordID, "failed", "Parse: "+err.Error(), nil)
		return
	}

	if !genResp.IsAsync {
		if genResp.VideoURL != "" {
			localPath, dlErr := h.downloadToStorage(genResp.VideoURL, "videos")
			updates := map[string]interface{}{
				"video_url": genResp.VideoURL, "status": "completed",
				"completed_at": database.Now(), "updated_at": database.Now(),
			}
			if dlErr == nil {
				updates["local_path"] = localPath
			}
			h.DB.Model(&database.VideoGeneration{}).Where("id = ?", recordID).Updates(updates)

			var rec database.VideoGeneration
			if h.DB.First(&rec, recordID).Error == nil && rec.StoryboardID != nil && localPath != "" {
				h.DB.Model(&database.Storyboard{}).Where("id = ?", *rec.StoryboardID).
					Update("video_url", localPath)
			}
		}
		return
	}

	h.DB.Model(&database.VideoGeneration{}).Where("id = ?", recordID).Updates(map[string]interface{}{
		"task_id": genResp.TaskID, "status": "processing", "updated_at": database.Now(),
	})
	h.pollVideoGen(recordID, adp, aiConfig, genResp.TaskID)
}

func (h *Handler) pollVideoGen(recordID int, adp adapter.VideoProviderAdapter, aiConfig *adapter.AIConfig, taskID string) {
	for i := 0; i < 120; i++ {
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
			localPath, _ := h.downloadToStorage(pollResp.VideoURL, "videos")
			updates := map[string]interface{}{
				"video_url": pollResp.VideoURL, "status": "completed",
				"completed_at": database.Now(), "updated_at": database.Now(),
			}
			if localPath != "" {
				updates["local_path"] = localPath
			}
			h.DB.Model(&database.VideoGeneration{}).Where("id = ?", recordID).Updates(updates)

			var rec database.VideoGeneration
			if h.DB.First(&rec, recordID).Error == nil && rec.StoryboardID != nil && localPath != "" {
				h.DB.Model(&database.Storyboard{}).Where("id = ?", *rec.StoryboardID).
					Update("video_url", localPath)
			}
			return
		case "failed":
			h.updateVideoRecord(recordID, "failed", pollResp.Error, nil)
			return
		}
	}
	h.updateVideoRecord(recordID, "failed", "Polling timeout", nil)
}

func (h *Handler) updateVideoRecord(id int, status, errMsg string, extra map[string]interface{}) {
	updates := map[string]interface{}{"status": status, "updated_at": database.Now()}
	if errMsg != "" {
		updates["error_msg"] = errMsg
	}
	for k, v := range extra {
		updates[k] = v
	}
	h.DB.Model(&database.VideoGeneration{}).Where("id = ?", id).Updates(updates)
}
