package handler

import (
	"strconv"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// POST /api/v1/scenes — Create a new scene
// ---------------------------------------------------------------------------

// CreateScene creates a new scene.
// Body: { drama_id, episode_id?, location, time?, prompt? }
// The prompt field defaults to location if not provided.
func (h *Handler) CreateScene(c *gin.Context) {
	var body struct {
		DramaID   int     `json:"drama_id"`
		EpisodeID *int    `json:"episode_id"`
		Location  string  `json:"location"`
		Time      *string `json:"time"`
		Prompt    *string `json:"prompt"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	ts := database.Now()

	// time defaults to empty string; prompt defaults to location.
	timeVal := ""
	if body.Time != nil {
		timeVal = *body.Time
	}
	promptVal := body.Location
	if body.Prompt != nil && *body.Prompt != "" {
		promptVal = *body.Prompt
	}

	scene := database.Scene{
		DramaID:   body.DramaID,
		EpisodeID: body.EpisodeID,
		Location:  body.Location,
		Time:      timeVal,
		Prompt:    promptVal,
		CreatedAt: ts,
		UpdatedAt: ts,
	}

	if err := h.DB.Create(&scene).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	util.Created(c, scene)
}

// ---------------------------------------------------------------------------
// PUT /api/v1/scenes/:id — Update scene fields
// ---------------------------------------------------------------------------

// UpdateScene updates select fields of a scene.
// Body: { location?, time?, prompt? }
func (h *Handler) UpdateScene(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	updates := map[string]interface{}{
		"updated_at": database.Now(),
	}

	if v, ok := body["location"]; ok {
		updates["location"] = v
	}
	if v, ok := body["time"]; ok {
		updates["time"] = v
	}
	if v, ok := body["prompt"]; ok {
		updates["prompt"] = v
	}

	h.DB.Model(&database.Scene{}).Where("id = ?", id).Updates(updates)
	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/scenes/:id — Hard delete scene
// ---------------------------------------------------------------------------

// DeleteScene permanently deletes a scene.
// This is a hard delete (not soft delete), matching the TypeScript backend behavior.
func (h *Handler) DeleteScene(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	h.DB.Where("id = ?", id).Delete(&database.Scene{})
	util.Success(c, nil)
}
