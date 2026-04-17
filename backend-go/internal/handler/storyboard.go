package handler

import (
	"strconv"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// ---------------------------------------------------------------------------
// POST /api/v1/storyboards — Create a new storyboard
// ---------------------------------------------------------------------------

// CreateStoryboard creates a new storyboard linked to an episode.
// Body: { episode_id, storyboard_number?, title?, description?, action?,
//
//	dialogue?, scene_id?, duration?, character_ids? }
//
// Validates that scene_id and character_ids belong to the episode.
// Defaults: storyboard_number=1, duration=10.
func (h *Handler) CreateStoryboard(c *gin.Context) {
	var body struct {
		EpisodeID        int     `json:"episode_id"`
		StoryboardNumber *int    `json:"storyboard_number"`
		Title            *string `json:"title"`
		Description      *string `json:"description"`
		Action           *string `json:"action"`
		Dialogue         *string `json:"dialogue"`
		SceneID          *int    `json:"scene_id"`
		Duration         *int    `json:"duration"`
		CharacterIDs     []int   `json:"character_ids"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	if body.EpisodeID == 0 {
		util.BadRequest(c, "episode_id is required")
		return
	}

	ts := database.Now()

	// Validate that scene_id and character_ids belong to the episode.
	if err := h.validateStoryboardBindings(body.EpisodeID, body.SceneID, body.CharacterIDs); err != nil {
		util.BadRequest(c, err.Error())
		return
	}

	sbNum := 1
	if body.StoryboardNumber != nil && *body.StoryboardNumber > 0 {
		sbNum = *body.StoryboardNumber
	}

	duration := 10
	if body.Duration != nil && *body.Duration > 0 {
		duration = *body.Duration
	}

	storyboard := database.Storyboard{
		EpisodeID:        body.EpisodeID,
		SceneID:          body.SceneID,
		StoryboardNumber: sbNum,
		Title:            body.Title,
		Description:      body.Description,
		Action:           body.Action,
		Dialogue:         body.Dialogue,
		Duration:         &duration,
		CreatedAt:        ts,
		UpdatedAt:        ts,
	}

	if err := h.DB.Create(&storyboard).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	// Sync storyboard_characters (delete-and-replace).
	h.syncStoryboardCharacters(storyboard.ID, body.CharacterIDs)

	// Fetch character IDs for the response.
	charIDs := h.getStoryboardCharacterIDs(storyboard.ID)

	util.Created(c, gin.H{
		"id":                storyboard.ID,
		"episode_id":        storyboard.EpisodeID,
		"scene_id":          storyboard.SceneID,
		"storyboard_number": storyboard.StoryboardNumber,
		"title":             storyboard.Title,
		"description":       storyboard.Description,
		"action":            storyboard.Action,
		"dialogue":          storyboard.Dialogue,
		"duration":          storyboard.Duration,
		"status":            storyboard.Status,
		"created_at":        storyboard.CreatedAt,
		"updated_at":        storyboard.UpdatedAt,
		"deleted_at":        storyboard.DeletedAt,
		"character_ids":     charIDs,
	})
}

// ---------------------------------------------------------------------------
// PUT /api/v1/storyboards/:id — Update storyboard
// ---------------------------------------------------------------------------

// UpdateStoryboard updates select fields of a storyboard.
// Body: { title?, description?, shot_type?, angle?, movement?, action?,
//
//	dialogue?, duration?, video_prompt?, image_prompt?, scene_id?,
//	location?, time?, atmosphere?, result?, bgm_prompt?, sound_effect?,
//	character_ids? }
//
// If dialogue is changed, tts_audio_url and subtitle_url are reset to null.
// Validates that updated scene_id/character_ids still belong to the episode.
func (h *Handler) UpdateStoryboard(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	// Fetch existing storyboard to get episode_id for validation.
	var storyboard database.Storyboard
	if err := h.DB.First(&storyboard, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			util.BadRequest(c, "镜头不存在")
			return
		}
		util.ServerError(c, err.Error())
		return
	}

	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	// Map of allowed JSON field names to database column names.
	fieldMap := map[string]string{
		"title":        "title",
		"description":  "description",
		"shot_type":    "shot_type",
		"angle":        "angle",
		"movement":     "movement",
		"action":       "action",
		"dialogue":     "dialogue",
		"duration":     "duration",
		"video_prompt": "video_prompt",
		"image_prompt": "image_prompt",
		"scene_id":     "scene_id",
		"location":     "location",
		"time":         "time",
		"atmosphere":   "atmosphere",
		"result":       "result",
		"bgm_prompt":   "bgm_prompt",
		"sound_effect": "sound_effect",
	}

	updates := map[string]interface{}{
		"updated_at": database.Now(),
	}

	for jsonKey, dbCol := range fieldMap {
		if v, ok := body[jsonKey]; ok {
			updates[dbCol] = v
		}
	}

	// If dialogue is being changed, reset TTS audio URL and subtitle URL.
	if _, hasDialogue := body["dialogue"]; hasDialogue {
		updates["tts_audio_url"] = nil
		updates["subtitle_url"] = nil
	}

	// Validate bindings with merged values (new + existing).
	sceneID := storyboard.SceneID
	if v, ok := toInt(body["scene_id"]); ok {
		sceneID = &v
	}

	var charIDs []int
	if raw, ok := body["character_ids"]; ok {
		charIDs = toIntSlice(raw)
	} else {
		charIDs = h.getStoryboardCharacterIDs(id)
	}

	if err := h.validateStoryboardBindings(storyboard.EpisodeID, sceneID, charIDs); err != nil {
		util.BadRequest(c, err.Error())
		return
	}

	// Apply updates.
	h.DB.Model(&database.Storyboard{}).Where("id = ?", id).Updates(updates)

	// Sync character IDs if provided in the body.
	if _, hasCharIDs := body["character_ids"]; hasCharIDs {
		h.syncStoryboardCharacters(id, charIDs)
	}

	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/storyboards/:id — Hard delete storyboard
// ---------------------------------------------------------------------------

// DeleteStoryboard permanently deletes a storyboard and its character associations.
// This is a hard delete (matching the TypeScript backend behavior):
//   - First deletes all rows in storyboard_characters for this storyboard
//   - Then deletes the storyboard itself
func (h *Handler) DeleteStoryboard(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	// Delete character associations first (foreign key cleanup).
	h.DB.Where("storyboard_id = ?", id).Delete(&database.StoryboardCharacter{})

	// Delete the storyboard itself (hard delete).
	h.DB.Where("id = ?", id).Delete(&database.Storyboard{})

	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// Helper methods for storyboard-character associations
// ---------------------------------------------------------------------------

// syncStoryboardCharacters replaces all character associations for a storyboard.
// It first deletes all existing rows in storyboard_characters for the given
// storyboard ID, then inserts new rows for each provided character ID.
// Duplicate and zero IDs are filtered out.
func (h *Handler) syncStoryboardCharacters(storyboardID int, characterIDs []int) {
	// Delete existing associations.
	h.DB.Where("storyboard_id = ?", storyboardID).Delete(&database.StoryboardCharacter{})

	// Deduplicate and filter zero IDs.
	seen := make(map[int]bool, len(characterIDs))
	unique := make([]int, 0, len(characterIDs))
	for _, cid := range characterIDs {
		if cid > 0 && !seen[cid] {
			seen[cid] = true
			unique = append(unique, cid)
		}
	}

	if len(unique) == 0 {
		return
	}

	// Insert new associations.
	for _, cid := range unique {
		link := database.StoryboardCharacter{
			StoryboardID: storyboardID,
			CharacterID:  cid,
		}
		h.DB.Create(&link)
	}
}

// getStoryboardCharacterIDs returns the character IDs associated with a storyboard
// via the storyboard_characters join table.
func (h *Handler) getStoryboardCharacterIDs(storyboardID int) []int {
	var links []database.StoryboardCharacter
	h.DB.Where("storyboard_id = ?", storyboardID).Find(&links)

	ids := make([]int, 0, len(links))
	for _, l := range links {
		ids = append(ids, l.CharacterID)
	}
	return ids
}

// validateStoryboardBindings checks that the provided scene_id exists in the
// episode_scenes join table and all character_ids exist in the episode_characters
// join table for the given episode. Returns an error describing the first
// validation failure, or nil if all bindings are valid.
func (h *Handler) validateStoryboardBindings(episodeID int, sceneID *int, characterIDs []int) error {
	if sceneID != nil && *sceneID > 0 {
		var count int64
		h.DB.Model(&database.EpisodeScene{}).
			Where("episode_id = ? AND scene_id = ?", episodeID, *sceneID).
			Count(&count)
		if count == 0 {
			return errSceneNotInEpisode
		}
	}

	if len(characterIDs) > 0 {
		var links []database.EpisodeCharacter
		h.DB.Where("episode_id = ?", episodeID).Find(&links)

		epCharIDs := make(map[int]bool, len(links))
		for _, l := range links {
			epCharIDs[l.CharacterID] = true
		}

		for _, cid := range characterIDs {
			if cid > 0 && !epCharIDs[cid] {
				return errCharacterNotInEpisode
			}
		}
	}

	return nil
}

// toIntSlice converts an interface{} (expected to be []interface{} of numbers)
// into a []int slice. Non-numeric values are silently skipped.
func toIntSlice(v interface{}) []int {
	if v == nil {
		return nil
	}

	switch val := v.(type) {
	case []interface{}:
		result := make([]int, 0, len(val))
		for _, item := range val {
			if n, ok := toInt(item); ok {
				result = append(result, n)
			}
		}
		return result
	case []float64:
		result := make([]int, 0, len(val))
		for _, item := range val {
			result = append(result, int(item))
		}
		return result
	case []int:
		return val
	}

	return nil
}
