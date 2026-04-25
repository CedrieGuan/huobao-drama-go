package handler

import (
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// POST /api/v1/webhooks/vidu — Vidu async callback
// ---------------------------------------------------------------------------

func (h *Handler) ViduWebhook(c *gin.Context) {
	var body struct {
		TaskID   string `json:"task_id"`
		State    string `json:"state"`
		VideoURL string `json:"video_url"`
		Error    string `json:"error"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	if body.TaskID == "" {
		util.BadRequest(c, "Missing task_id")
		return
	}

	var records []database.VideoGeneration
	if err := h.DB.Where("task_id = ?", body.TaskID).Find(&records).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	if len(records) == 0 {
		util.Success(c, gin.H{"message": "Task not found"})
		return
	}

	record := records[0]

	switch body.State {
	case "success":
		if body.VideoURL == "" {
			util.Success(c, gin.H{"message": "No video URL"})
			return
		}
		localPath, dlErr := h.downloadToStorage(body.VideoURL, "videos")
		updates := map[string]interface{}{
			"video_url": body.VideoURL, "status": "completed",
			"updated_at": database.Now(),
		}
		if dlErr == nil {
			updates["local_path"] = localPath
		}
		h.DB.Model(&database.VideoGeneration{}).Where("id = ?", record.ID).Updates(updates)
		if record.StoryboardID != nil && localPath != "" {
			h.DB.Model(&database.Storyboard{}).Where("id = ?", *record.StoryboardID).
				Update("video_url", localPath)
		}
		util.Success(c, gin.H{"message": "Video updated successfully"})

	case "failed":
		errMsg := body.Error
		if errMsg == "" {
			errMsg = "Vidu generation failed"
		}
		h.DB.Model(&database.VideoGeneration{}).Where("id = ?", record.ID).Updates(map[string]interface{}{
			"status": "failed", "error_msg": errMsg, "updated_at": database.Now(),
		})
		util.Success(c, gin.H{"message": "Error recorded"})

	default:
		util.Success(c, gin.H{"message": "Status noted"})
	}
}
