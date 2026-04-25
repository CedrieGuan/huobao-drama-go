package handler

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// POST /api/v1/storyboards/:id/compose — Compose single storyboard
// ---------------------------------------------------------------------------

func (h *Handler) ComposeStoryboard(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var sb database.Storyboard
	if err := h.DB.First(&sb, id).Error; err != nil {
		util.NotFound(c, "Storyboard not found")
		return
	}

	go h.executeCompose(int64(id))
	util.Success(c, gin.H{"id": id, "message": "Compose started"})
}

// ---------------------------------------------------------------------------
// POST /api/v1/episodes/:id/compose-all — Batch compose
// ---------------------------------------------------------------------------

func (h *Handler) ComposeAllStoryboards(c *gin.Context) {
	episodeID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var storyboards []database.Storyboard
	if err := h.DB.Where("episode_id = ?", episodeID).Order("storyboard_number").Find(&storyboards).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	withVideo := filterWithVideo(storyboards)
	if len(withVideo) == 0 {
		util.BadRequest(c, "No storyboards have video yet")
		return
	}

	for _, sb := range withVideo {
		h.DB.Model(&database.Storyboard{}).Where("id = ?", sb.ID).Update("status", "compose_processing")
	}

	go func() {
		for _, sb := range withVideo {
			if err := h.executeComposeSync(int64(sb.ID)); err != nil {
				h.DB.Model(&database.Storyboard{}).Where("id = ?", sb.ID).Update("status", "compose_failed")
			}
		}
	}()

	util.Success(c, gin.H{
		"message": fmt.Sprintf("Started composing %d storyboards", len(withVideo)),
		"total":   len(withVideo),
	})
}

// ---------------------------------------------------------------------------
// GET /api/v1/episodes/:id/compose-status — Query compose status
// ---------------------------------------------------------------------------

func (h *Handler) ComposeStatus(c *gin.Context) {
	episodeID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var storyboards []database.Storyboard
	if err := h.DB.Where("episode_id = ?", episodeID).Order("storyboard_number").Find(&storyboards).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	type composeItem struct {
		ID               int    `json:"id"`
		StoryboardNumber int    `json:"storyboard_number"`
		Status           string `json:"status"`
		ComposedVideoURL string `json:"composed_video_url"`
		ErrorMsg         string `json:"error_msg"`
	}

	withVideo := filterWithVideo(storyboards)
	completed, failed, processing, idle := 0, 0, 0, 0
	var items []composeItem

	for _, sb := range withVideo {
		status := "pending"
		if sb.Status != nil {
			status = *sb.Status
		}
		composedURL := ""
		if sb.ComposedVideoURL != nil {
			composedURL = *sb.ComposedVideoURL
		}

		switch {
		case status == "compose_completed" && composedURL != "":
			completed++
		case status == "compose_failed":
			failed++
		case status == "compose_processing":
			processing++
		default:
			idle++
		}

		errMsg := ""
		if status == "compose_failed" {
			errMsg = "视频合成失败，请检查视频、配音或字幕素材"
		}

		items = append(items, composeItem{
			ID: sb.ID, StoryboardNumber: sb.StoryboardNumber,
			Status: status, ComposedVideoURL: composedURL, ErrorMsg: errMsg,
		})
	}

	util.Success(c, gin.H{
		"total": len(withVideo), "completed": completed,
		"failed": failed, "processing": processing, "idle": idle, "items": items,
	})
}

// ---------------------------------------------------------------------------
// Background compose execution
// ---------------------------------------------------------------------------

func (h *Handler) executeCompose(storyboardID int64) {
	_ = h.executeComposeSync(storyboardID)
}

func (h *Handler) executeComposeSync(storyboardID int64) error {
	var sb database.Storyboard
	if err := h.DB.First(&sb, storyboardID).Error; err != nil {
		return err
	}

	videoPath := ""
	if sb.VideoURL != nil {
		videoPath = *sb.VideoURL
	}
	if videoPath == "" {
		return fmt.Errorf("no video URL")
	}

	fullVideoPath := videoPath
	if h.StoragePath != "" && !filepath.IsAbs(videoPath) {
		fullVideoPath = filepath.Join(h.StoragePath, videoPath)
	}

	outputName := fmt.Sprintf("composed_%d.mp4", storyboardID)
	outputDir := filepath.Join(h.StoragePath, "composed")
	exec.Command("mkdir", "-p", outputDir).Run()
	outputPath := filepath.Join(outputDir, outputName)

	cmd := exec.Command("ffmpeg", "-y", "-i", fullVideoPath, "-c", "copy", outputPath)
	if err := cmd.Run(); err != nil {
		h.DB.Model(&database.Storyboard{}).Where("id = ?", storyboardID).Updates(map[string]interface{}{
			"status": "compose_failed", "updated_at": database.Now(),
		})
		return err
	}

	composedURL := filepath.Join("composed", outputName)
	h.DB.Model(&database.Storyboard{}).Where("id = ?", storyboardID).Updates(map[string]interface{}{
		"status": "compose_completed", "composed_video_url": composedURL, "updated_at": database.Now(),
	})
	return nil
}

func filterWithVideo(storyboards []database.Storyboard) []database.Storyboard {
	var result []database.Storyboard
	for _, sb := range storyboards {
		if sb.VideoURL != nil && *sb.VideoURL != "" {
			result = append(result, sb)
		}
	}
	return result
}
