package handler

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// POST /api/v1/episodes/:id/merge — Merge episode videos
// ---------------------------------------------------------------------------

func (h *Handler) MergeEpisode(c *gin.Context) {
	episodeID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var ep database.Episode
	if err := h.DB.First(&ep, episodeID).Error; err != nil {
		util.BadRequest(c, "Episode not found")
		return
	}

	ts := database.Now()
	provider := "ffmpeg"
	modelVal := "concat"
	pending := "processing"
	dramaID := ep.DramaID
	record := database.VideoMerge{
		EpisodeID: &episodeID,
		DramaID:   &dramaID,
		Provider:  provider,
		Model:     modelVal,
		Status:    &pending,
		CreatedAt: ts,
	}
	if err := h.DB.Create(&record).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	go h.executeMerge(record.ID, episodeID, ep.DramaID)
	util.Success(c, gin.H{"merge_id": record.ID, "status": "processing"})
}

// ---------------------------------------------------------------------------
// GET /api/v1/episodes/:id/merge — Query merge status
// ---------------------------------------------------------------------------

func (h *Handler) GetMergeStatus(c *gin.Context) {
	episodeID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var merges []database.VideoMerge
	if err := h.DB.Where("episode_id = ?", episodeID).Order("id ASC").Find(&merges).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	if len(merges) == 0 {
		util.Success(c, nil)
		return
	}

	util.Success(c, merges[len(merges)-1])
}

// ---------------------------------------------------------------------------
// Background merge execution
// ---------------------------------------------------------------------------

func (h *Handler) executeMerge(mergeID, episodeID, dramaID int) {
	var storyboards []database.Storyboard
	if err := h.DB.Where("episode_id = ? AND composed_video_url IS NOT NULL AND composed_video_url != ''", episodeID).
		Order("storyboard_number").Find(&storyboards).Error; err != nil || len(storyboards) == 0 {
		h.DB.Model(&database.VideoMerge{}).Where("id = ?", mergeID).Updates(map[string]interface{}{
			"status": "failed", "error_msg": "No composed storyboards found", "updated_at": database.Now(),
		})
		return
	}

	tmpDir := filepath.Join(h.StoragePath, "tmp")
	os.MkdirAll(tmpDir, 0o755)
	concatPath := filepath.Join(tmpDir, fmt.Sprintf("merge_%d.txt", mergeID))

	var entries []string
	for _, sb := range storyboards {
		fullPath := *sb.ComposedVideoURL
		if h.StoragePath != "" && !filepath.IsAbs(fullPath) {
			fullPath = filepath.Join(h.StoragePath, fullPath)
		}
		entries = append(entries, fmt.Sprintf("file '%s'", fullPath))
	}

	concatContent := ""
	for _, e := range entries {
		concatContent += e + "\n"
	}
	if err := os.WriteFile(concatPath, []byte(concatContent), 0o644); err != nil {
		h.DB.Model(&database.VideoMerge{}).Where("id = ?", mergeID).Updates(map[string]interface{}{
			"status": "failed", "error_msg": err.Error(), "updated_at": database.Now(),
		})
		return
	}

	outputName := fmt.Sprintf("merged_ep%d_%d.mp4", episodeID, mergeID)
	outputDir := filepath.Join(h.StoragePath, "merged")
	os.MkdirAll(outputDir, 0o755)
	outputPath := filepath.Join(outputDir, outputName)

	cmd := exec.Command("ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concatPath, "-c", "copy", outputPath)
	if err := cmd.Run(); err != nil {
		h.DB.Model(&database.VideoMerge{}).Where("id = ?", mergeID).Updates(map[string]interface{}{
			"status": "failed", "error_msg": err.Error(), "updated_at": database.Now(),
		})
		return
	}

	mergedURL := filepath.Join("merged", outputName)
	scenesJSON, _ := json.Marshal(len(storyboards))
	scenesStr := string(scenesJSON)
	h.DB.Model(&database.VideoMerge{}).Where("id = ?", mergeID).Updates(map[string]interface{}{
		"status": "completed", "merged_url": mergedURL, "scenes": scenesStr,
		"completed_at": database.Now(), "updated_at": database.Now(),
	})

	h.DB.Model(&database.Episode{}).Where("id = ?", episodeID).Update("video_url", mergedURL)
	os.Remove(concatPath)
}
