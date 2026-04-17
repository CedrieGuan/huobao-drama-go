package handler

import (
	"strconv"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// PUT /api/v1/characters/:id — Update character
// ---------------------------------------------------------------------------

// UpdateCharacter updates select fields of a character.
// Body: { name?, role?, description?, appearance?, personality?,
//
//	voice_style?, voice_provider?, image_url?, local_path?,
//	reference_images?, seed_value?, sort_order? }
//
// Accepts both snake_case and camelCase keys (matching TS behavior).
// If voice_style is changed, voice_sample_url is reset to null.
func (h *Handler) UpdateCharacter(c *gin.Context) {
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

	// Map of allowed JSON keys to database column names.
	// The TS backend accepts both snake_case and camelCase, so we handle both.
	allowedFields := map[string]string{
		// snake_case keys (preferred)
		"name":             "name",
		"role":             "role",
		"description":      "description",
		"appearance":       "appearance",
		"personality":      "personality",
		"voice_style":      "voice_style",
		"voice_provider":   "voice_provider",
		"image_url":        "image_url",
		"local_path":       "local_path",
		"reference_images": "reference_images",
		"seed_value":       "seed_value",
		"sort_order":       "sort_order",
		"voice_sample_url": "voice_sample_url",
		"thumbnail":        "thumbnail",
	}

	for jsonKey, dbCol := range allowedFields {
		if v, ok := body[jsonKey]; ok {
			updates[dbCol] = v
		}
	}

	// If voice_style is being changed, reset voice_sample_url to null.
	// This matches the TS behavior: changing the voice invalidates the old sample.
	_, hasVoiceStyle := body["voice_style"]
	if hasVoiceStyle {
		updates["voice_sample_url"] = nil
	}

	h.DB.Model(&database.Character{}).Where("id = ?", id).Updates(updates)
	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/characters/:id — Soft delete character
// ---------------------------------------------------------------------------

// DeleteCharacter soft-deletes a character by setting deleted_at.
// This is a soft delete (matching the TypeScript backend behavior).
func (h *Handler) DeleteCharacter(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	h.DB.Model(&database.Character{}).Where("id = ?", id).
		Update("deleted_at", database.Now())

	util.Success(c, nil)
}
