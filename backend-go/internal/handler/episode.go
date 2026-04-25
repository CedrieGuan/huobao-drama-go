package handler

import (
	"strconv"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// ---------------------------------------------------------------------------
// POST /api/v1/episodes — Create a new episode
// ---------------------------------------------------------------------------

// CreateEpisode creates a new episode under a drama.
// Body: { drama_id, image_config_id, video_config_id, audio_config_id, title? }
// All three config IDs are required.
// The episode_number is auto-calculated as max(existing) + 1.
func (h *Handler) CreateEpisode(c *gin.Context) {
	var body struct {
		DramaID       int     `json:"drama_id"`
		Title         *string `json:"title"`
		ImageConfigID *int    `json:"image_config_id"`
		VideoConfigID *int    `json:"video_config_id"`
		AudioConfigID *int    `json:"audio_config_id"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	if body.DramaID == 0 {
		util.BadRequest(c, "drama_id required")
		return
	}
	if body.ImageConfigID == nil {
		util.BadRequest(c, "image_config_id, video_config_id and audio_config_id are required")
		return
	}
	if body.VideoConfigID == nil {
		util.BadRequest(c, "image_config_id, video_config_id and audio_config_id are required")
		return
	}
	if body.AudioConfigID == nil {
		util.BadRequest(c, "image_config_id, video_config_id and audio_config_id are required")
		return
	}

	ts := database.Now()

	var nextNum int
	if err := h.DB.Transaction(func(tx *gorm.DB) error {
		// Calculate next episode number atomically within a transaction.
		var maxNum *int
		if err := tx.Model(&database.Episode{}).
			Where("drama_id = ?", body.DramaID).
			Select("MAX(episode_number)").
			Scan(&maxNum).Error; err != nil {
			return err
		}
		nextNum = 1
		if maxNum != nil && *maxNum >= nextNum {
			nextNum = *maxNum + 1
		}
		return nil
	}); err != nil {
		util.ServerError(c, err.Error())
		return
	}

	title := "第" + strconv.Itoa(nextNum) + "集"
	if body.Title != nil && *body.Title != "" {
		title = *body.Title
	}

	episode := database.Episode{
		DramaID:       body.DramaID,
		EpisodeNumber: nextNum,
		Title:         title,
		ImageConfigID: body.ImageConfigID,
		VideoConfigID: body.VideoConfigID,
		AudioConfigID: body.AudioConfigID,
		CreatedAt:     ts,
		UpdatedAt:     ts,
	}

	if err := h.DB.Create(&episode).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	// Return full episode data so Swift Episode model can decode all required fields.
	util.Created(c, gin.H{
		"id":               episode.ID,
		"drama_id":         episode.DramaID,
		"episode_number":   episode.EpisodeNumber,
		"title":            episode.Title,
		"content":          episode.Content,
		"script_content":   episode.ScriptContent,
		"description":      episode.Description,
		"duration":         episode.Duration,
		"status":           episode.Status,
		"video_url":        episode.VideoURL,
		"thumbnail":        episode.Thumbnail,
		"image_config_id":  episode.ImageConfigID,
		"video_config_id":  episode.VideoConfigID,
		"audio_config_id":  episode.AudioConfigID,
		"created_at":       episode.CreatedAt,
		"updated_at":       episode.UpdatedAt,
	})
}

// ---------------------------------------------------------------------------
// PUT /api/v1/episodes/:id — Update episode fields
// ---------------------------------------------------------------------------

// UpdateEpisode updates select fields of an episode.
// Body: { content?, script_content?, title?, description?, status? }
// Only these 5 fields are allowed to be updated.
func (h *Handler) UpdateEpisode(c *gin.Context) {
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

	// Whitelist of allowed fields.
	allowed := map[string]string{
		"content":        "content",
		"script_content": "script_content",
		"title":          "title",
		"description":    "description",
		"status":         "status",
	}

	updates := map[string]interface{}{
		"updated_at": database.Now(),
	}
	hasUpdate := false
	for jsonKey, dbCol := range allowed {
		if v, ok := body[jsonKey]; ok {
			updates[dbCol] = v
			hasUpdate = true
		}
	}

	if !hasUpdate {
		util.BadRequest(c, "no valid fields")
		return
	}

	h.DB.Model(&database.Episode{}).Where("id = ?", id).Updates(updates)
	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// GET /api/v1/episodes/:id/characters — Characters linked to an episode
// ---------------------------------------------------------------------------

// GetEpisodeCharacters returns all characters linked to the episode via the
// episode_characters join table. Deleted characters are filtered out.
func (h *Handler) GetEpisodeCharacters(c *gin.Context) {
	episodeID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	// Get join rows.
	var links []database.EpisodeCharacter
	h.DB.Where("episode_id = ?", episodeID).Find(&links)

	if len(links) == 0 {
		util.Success(c, []interface{}{})
		return
	}

	// Collect character IDs.
	charIDs := make([]int, 0, len(links))
	for _, l := range links {
		charIDs = append(charIDs, l.CharacterID)
	}

	// Fetch characters, excluding soft-deleted ones.
	var chars []database.Character
	h.DB.Where("id IN ?", charIDs).
		Where("deleted_at IS NULL").
		Find(&chars)

	util.Success(c, chars)
}

// ---------------------------------------------------------------------------
// GET /api/v1/episodes/:id/scenes — Scenes linked to an episode
// ---------------------------------------------------------------------------

// GetEpisodeScenes returns all scenes linked to the episode via the
// episode_scenes join table. Deleted scenes are filtered out.
func (h *Handler) GetEpisodeScenes(c *gin.Context) {
	episodeID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	// Get join rows.
	var links []database.EpisodeScene
	h.DB.Where("episode_id = ?", episodeID).Find(&links)

	if len(links) == 0 {
		util.Success(c, []interface{}{})
		return
	}

	// Collect scene IDs.
	sceneIDs := make([]int, 0, len(links))
	for _, l := range links {
		sceneIDs = append(sceneIDs, l.SceneID)
	}

	// Fetch scenes, excluding soft-deleted ones.
	var scenes []database.Scene
	h.DB.Where("id IN ?", sceneIDs).
		Where("deleted_at IS NULL").
		Find(&scenes)

	util.Success(c, scenes)
}

// ---------------------------------------------------------------------------
// GET /api/v1/episodes/:episode_id/storyboards — Storyboards for an episode
// ---------------------------------------------------------------------------

// enrichedStoryboard is a storyboard with its associated character IDs and
// full character objects attached.
type enrichedStoryboard struct {
	database.Storyboard
	CharacterIDs []int                `json:"character_ids"`
	Characters   []database.Character `json:"characters"`
}

// GetEpisodeStoryboards returns all storyboards for an episode, ordered by
// storyboard_number, each enriched with character_ids and character objects.
func (h *Handler) GetEpisodeStoryboards(c *gin.Context) {
	episodeID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	// Fetch storyboards ordered by storyboard_number.
	var storyboards []database.Storyboard
	h.DB.Where("episode_id = ?", episodeID).
		Order("storyboard_number ASC").
		Find(&storyboards)

	// Collect storyboard IDs for batch queries.
	sbIDs := make([]int, 0, len(storyboards))
	for _, sb := range storyboards {
		sbIDs = append(sbIDs, sb.ID)
	}

	// Batch fetch character associations for these storyboards only.
	var sbCharLinks []database.StoryboardCharacter
	if len(sbIDs) > 0 {
		h.DB.Where("storyboard_id IN ?", sbIDs).Find(&sbCharLinks)
	}

	charIDsBySB := make(map[int][]int)
	allCharIDs := make(map[int]bool)
	for _, link := range sbCharLinks {
		charIDsBySB[link.StoryboardID] = append(charIDsBySB[link.StoryboardID], link.CharacterID)
		allCharIDs[link.CharacterID] = true
	}

	// Batch fetch only the characters referenced by these storyboards.
	charByID := make(map[int]database.Character)
	if len(allCharIDs) > 0 {
		ids := make([]int, 0, len(allCharIDs))
		for id := range allCharIDs {
			ids = append(ids, id)
		}
		var chars []database.Character
		h.DB.Where("id IN ? AND deleted_at IS NULL", ids).Find(&chars)
		for _, ch := range chars {
			charByID[ch.ID] = ch
		}
	}

	// Enrich each storyboard.
	result := make([]enrichedStoryboard, 0, len(storyboards))
	for i := range storyboards {
		sb := &storyboards[i]
		ids := charIDsBySB[sb.ID]
		if ids == nil {
			ids = []int{}
		}

		// Collect full character objects for this storyboard.
		sbChars := make([]database.Character, 0)
		for _, cid := range ids {
			if ch, ok := charByID[cid]; ok {
				sbChars = append(sbChars, ch)
			}
		}

		result = append(result, enrichedStoryboard{
			Storyboard:   *sb,
			CharacterIDs: ids,
			Characters:   sbChars,
		})
	}

	util.Success(c, result)
}

// ---------------------------------------------------------------------------
// GET /api/v1/episodes/:id/pipeline-status — Episode pipeline progress
// ---------------------------------------------------------------------------

// stepStatus computes a step's status string from done/partial booleans.
func stepStatus(done, partial bool) string {
	if done {
		return "done"
	}
	if partial {
		return "partial"
	}
	return "pending"
}

// GetEpisodePipelineStatus computes the 10-step pipeline progress for an episode.
// Steps: script_rewrite, extract_characters, extract_scenes, assign_voices,
// generate_voice_samples, extract_storyboards, generate_images, generate_videos,
// compose_shots, merge_episode.
func (h *Handler) GetEpisodePipelineStatus(c *gin.Context) {
	episodeID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	// Fetch episode.
	var ep database.Episode
	if err := h.DB.First(&ep, episodeID).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			util.NotFound(c, "Episode not found")
			return
		}
		util.ServerError(c, err.Error())
		return
	}

	// Fetch related data.
	var chars []database.Character
	h.DB.Where("drama_id = ?", ep.DramaID).Find(&chars)

	var scenes []database.Scene
	h.DB.Where("drama_id = ?", ep.DramaID).Find(&scenes)

	var sbs []database.Storyboard
	h.DB.Where("episode_id = ?", episodeID).Find(&sbs)

	var merges []database.VideoMerge
	h.DB.Where("episode_id = ?", episodeID).Find(&merges)

	// Compute metrics.
	charsWithVoice := 0
	charsWithSample := 0
	for _, ch := range chars {
		if ch.VoiceStyle != nil && *ch.VoiceStyle != "" {
			charsWithVoice++
		}
		if ch.VoiceSampleURL != nil && *ch.VoiceSampleURL != "" {
			charsWithSample++
		}
	}

	sbsWithImage := 0
	sbsWithVideo := 0
	sbsComposed := 0
	for _, sb := range sbs {
		if sb.ComposedImage != nil && *sb.ComposedImage != "" {
			sbsWithImage++
		}
		if sb.VideoURL != nil && *sb.VideoURL != "" {
			sbsWithVideo++
		}
		if sb.ComposedVideoURL != nil && *sb.ComposedVideoURL != "" {
			sbsComposed++
		}
	}

	// Latest merge.
	var latestMerge *database.VideoMerge
	if len(merges) > 0 {
		latestMerge = &merges[len(merges)-1]
	}

	// Build pipeline status for each step.
	scriptContent := ""
	if ep.ScriptContent != nil {
		scriptContent = *ep.ScriptContent
	}
	content := ""
	if ep.Content != nil {
		content = *ep.Content
	}

	mergeStatus := "pending"
	var mergedURL *string
	if latestMerge != nil {
		mergeStatus = nilToStr(latestMerge.Status, "pending")
		if latestMerge.MergedURL != nil {
			mergedURL = latestMerge.MergedURL
		}
		if latestMerge.Status != nil && *latestMerge.Status == "completed" {
			mergeStatus = "done"
		}
	}

	util.Success(c, gin.H{
		"episode_id": episodeID,
		"steps": gin.H{
			"script_rewrite": gin.H{
				"status": func() string {
					if scriptContent != "" {
						return "done"
					}
					if content != "" {
						return "ready"
					}
					return "pending"
				}(),
			},
			"extract_characters": gin.H{
				"status": stepStatus(len(chars) > 0, false),
				"count":  len(chars),
			},
			"extract_scenes": gin.H{
				"status": stepStatus(len(scenes) > 0, false),
				"count":  len(scenes),
			},
			"assign_voices": gin.H{
				"status":   stepStatus(charsWithVoice == len(chars) && len(chars) > 0, charsWithVoice > 0),
				"assigned": charsWithVoice,
				"total":    len(chars),
			},
			"generate_voice_samples": gin.H{
				"status":    stepStatus(charsWithSample == charsWithVoice && charsWithVoice > 0, charsWithSample > 0),
				"completed": charsWithSample,
				"total":     charsWithVoice,
			},
			"extract_storyboards": gin.H{
				"status": stepStatus(len(sbs) > 0, false),
				"count":  len(sbs),
			},
			"generate_images": gin.H{
				"status":    stepStatus(sbsWithImage == len(sbs) && len(sbs) > 0, sbsWithImage > 0),
				"completed": sbsWithImage,
				"total":     len(sbs),
			},
			"generate_videos": gin.H{
				"status":    stepStatus(sbsWithVideo == len(sbs) && len(sbs) > 0, sbsWithVideo > 0),
				"completed": sbsWithVideo,
				"total":     len(sbs),
			},
			"compose_shots": gin.H{
				"status":    stepStatus(sbsComposed == len(sbs) && len(sbs) > 0, sbsComposed > 0),
				"completed": sbsComposed,
				"total":     len(sbs),
			},
			"merge_episode": gin.H{
				"status":     mergeStatus,
				"merged_url": mergedURL,
			},
		},
	})
}

// nilToStr returns the dereferenced string value or fallback if nil.
func nilToStr(s *string, fallback string) string {
	if s == nil {
		return fallback
	}
	return *s
}
