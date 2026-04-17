package handler

import (
	"encoding/json"
	"strconv"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// ---------------------------------------------------------------------------
// GET /api/v1/dramas — List dramas with pagination and enrichment
// ---------------------------------------------------------------------------

// ListDramas returns a paginated, optionally filtered list of dramas.
// Each drama is enriched with its episodes, characters, and scenes.
// Query params: page, page_size, status, keyword
func (h *Handler) ListDramas(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	statusFilter := c.Query("status")
	keyword := c.Query("keyword")

	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = 20
	}

	// Fetch all non-deleted dramas, ordered by updated_at desc.
	var dramas []database.Drama
	if err := h.DB.Where("deleted_at IS NULL").
		Order("updated_at DESC").
		Find(&dramas).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	// In-memory filtering (matches TS behavior).
	filtered := make([]database.Drama, 0, len(dramas))
	for i := range dramas {
		d := &dramas[i]
		if statusFilter != "" && d.Status != statusFilter {
			continue
		}
		if keyword != "" && !containsString(d.Title, keyword) {
			continue
		}
		filtered = append(filtered, *d)
	}

	total := len(filtered)
	start := (page - 1) * pageSize
	end := start + pageSize
	if start > total {
		start = total
	}
	if end > total {
		end = total
	}
	pageItems := filtered[start:end]

	// Enrich each drama with episodes, characters, scenes.
	type enrichedDrama struct {
		database.Drama
		Tags          interface{}          `json:"tags"`
		TotalEpisodes int                  `json:"total_episodes"`
		Episodes      []database.Episode   `json:"episodes"`
		Characters    []database.Character `json:"characters"`
		Scenes        []database.Scene     `json:"scenes"`
	}

	items := make([]enrichedDrama, 0, len(pageItems))
	for i := range pageItems {
		d := &pageItems[i]

		var eps []database.Episode
		h.DB.Where("drama_id = ?", d.ID).Find(&eps)

		var chars []database.Character
		h.DB.Where("drama_id = ?", d.ID).Find(&chars)

		var scns []database.Scene
		h.DB.Where("drama_id = ?", d.ID).Find(&scns)

		var tags interface{} = []interface{}{}
		if d.Tags != nil {
			var parsed []interface{}
			if err := json.Unmarshal([]byte(*d.Tags), &parsed); err == nil {
				tags = parsed
			}
		}

		items = append(items, enrichedDrama{
			Drama:         *d,
			Tags:          tags,
			TotalEpisodes: len(eps),
			Episodes:      eps,
			Characters:    chars,
			Scenes:        scns,
		})
	}

	totalPages := total / pageSize
	if total%pageSize != 0 {
		totalPages++
	}

	util.Success(c, gin.H{
		"items": items,
		"pagination": gin.H{
			"page":        page,
			"page_size":   pageSize,
			"total":       total,
			"total_pages": totalPages,
		},
	})
}

// ---------------------------------------------------------------------------
// POST /api/v1/dramas — Create drama
// ---------------------------------------------------------------------------

// CreateDrama creates a new drama and its default episodes.
// Body: { title, description?, genre?, style?, tags?: array, metadata?, total_episodes?: int }
func (h *Handler) CreateDrama(c *gin.Context) {
	var body struct {
		Title         string   `json:"title"`
		Description   *string  `json:"description"`
		Genre         *string  `json:"genre"`
		Style         *string  `json:"style"`
		Tags          []string `json:"tags"`
		Metadata      *string  `json:"metadata"`
		TotalEpisodes *int     `json:"total_episodes"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	ts := database.Now()

	// Serialize tags to JSON string if provided.
	var tagsJSON *string
	if body.Tags != nil {
		b, _ := json.Marshal(body.Tags)
		s := string(b)
		tagsJSON = &s
	}

	drama := database.Drama{
		Title:       body.Title,
		Description: body.Description,
		Genre:       body.Genre,
		Style:       body.Style,
		Tags:        tagsJSON,
		Metadata:    body.Metadata,
		Status:      "draft",
		CreatedAt:   ts,
		UpdatedAt:   ts,
	}

	if err := h.DB.Create(&drama).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	// Create default episodes.
	totalEps := 1
	if body.TotalEpisodes != nil && *body.TotalEpisodes > 0 {
		totalEps = *body.TotalEpisodes
	}
	for i := 1; i <= totalEps; i++ {
		ep := database.Episode{
			DramaID:       drama.ID,
			EpisodeNumber: i,
			Title:         "第" + strconv.Itoa(i) + "集",
			Status:        stringPtr("draft"),
			CreatedAt:     ts,
			UpdatedAt:     ts,
		}
		h.DB.Create(&ep)
	}

	util.Created(c, drama)
}

// ---------------------------------------------------------------------------
// GET /api/v1/dramas/stats — Drama statistics
// NOTE: This must be registered before /:id to avoid route conflicts.
// ---------------------------------------------------------------------------

// DramaStats returns aggregate drama counts grouped by status.
func (h *Handler) DramaStats(c *gin.Context) {
	var dramas []database.Drama
	h.DB.Where("deleted_at IS NULL").Find(&dramas)

	// Aggregate by status.
	countByStatus := make(map[string]int)
	for _, d := range dramas {
		s := d.Status
		if s == "" {
			s = "draft"
		}
		countByStatus[s]++
	}

	byStatus := make([]gin.H, 0, len(countByStatus))
	for status, count := range countByStatus {
		byStatus = append(byStatus, gin.H{
			"status": status,
			"count":  count,
		})
	}

	util.Success(c, gin.H{
		"total":     len(dramas),
		"by_status": byStatus,
	})
}

// ---------------------------------------------------------------------------
// GET /api/v1/dramas/:id — Get drama detail with full enrichment
// ---------------------------------------------------------------------------

// GetDrama returns a single drama enriched with episodes, characters, scenes, and props.
func (h *Handler) GetDrama(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var drama database.Drama
	if err := h.DB.First(&drama, id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			util.NotFound(c, "剧本不存在")
			return
		}
		util.ServerError(c, err.Error())
		return
	}

	var eps []database.Episode
	h.DB.Where("drama_id = ?", id).Find(&eps)

	var chars []database.Character
	h.DB.Where("drama_id = ?", id).Find(&chars)

	var scns []database.Scene
	h.DB.Where("drama_id = ?", id).Find(&scns)

	var props []database.Prop
	h.DB.Where("drama_id = ?", id).Find(&props)

	// Parse tags JSON.
	var tags interface{} = []interface{}{}
	if drama.Tags != nil {
		var parsed []interface{}
		if err := json.Unmarshal([]byte(*drama.Tags), &parsed); err == nil {
			tags = parsed
		}
	}

	util.Success(c, gin.H{
		"id":             drama.ID,
		"title":          drama.Title,
		"description":    drama.Description,
		"genre":          drama.Genre,
		"style":          drama.Style,
		"total_episodes": drama.TotalEpisodes,
		"total_duration": drama.TotalDuration,
		"status":         drama.Status,
		"thumbnail":      drama.Thumbnail,
		"tags":           tags,
		"metadata":       drama.Metadata,
		"created_at":     drama.CreatedAt,
		"updated_at":     drama.UpdatedAt,
		"deleted_at":     drama.DeletedAt,
		"episodes":       eps,
		"characters":     chars,
		"scenes":         scns,
		"props":          props,
	})
}

// ---------------------------------------------------------------------------
// PUT /api/v1/dramas/:id — Update drama
// ---------------------------------------------------------------------------

// UpdateDrama updates select fields of a drama.
// Body: { title?, description?, genre?, style?, status?, tags?: array, metadata? }
func (h *Handler) UpdateDrama(c *gin.Context) {
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

	if v, ok := body["title"]; ok {
		updates["title"] = v
	}
	if v, ok := body["description"]; ok {
		updates["description"] = v
	}
	if v, ok := body["genre"]; ok {
		updates["genre"] = v
	}
	if v, ok := body["style"]; ok {
		updates["style"] = v
	}
	if v, ok := body["status"]; ok {
		updates["status"] = v
	}
	if v, ok := body["metadata"]; ok {
		updates["metadata"] = v
	}
	if v, ok := body["tags"]; ok {
		b, _ := json.Marshal(v)
		updates["tags"] = string(b)
	}

	h.DB.Model(&database.Drama{}).Where("id = ?", id).Updates(updates)
	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/dramas/:id — Soft delete drama
// ---------------------------------------------------------------------------

// DeleteDrama soft-deletes a drama by setting deleted_at.
func (h *Handler) DeleteDrama(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	h.DB.Model(&database.Drama{}).Where("id = ?", id).
		Update("deleted_at", database.Now())

	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// PUT /api/v1/dramas/:id/characters — Upsert characters for a drama
// ---------------------------------------------------------------------------

// UpsertDramaCharacters bulk upserts characters for a drama.
// Body: { characters: [{ id?, name, role, ... }] }
func (h *Handler) UpsertDramaCharacters(c *gin.Context) {
	dramaID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var body struct {
		Characters []map[string]interface{} `json:"characters"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	ts := database.Now()

	for _, charData := range body.Characters {
		if charID, ok := toInt(charData["id"]); ok && charID > 0 {
			// Update existing character.
			updates := map[string]interface{}{
				"updated_at": ts,
			}
			copyAllowedFields(charData, updates, map[string]string{
				"name": "name", "role": "role", "description": "description",
				"appearance": "appearance", "personality": "personality",
				"voice_style": "voice_style", "image_url": "image_url",
				"reference_images": "reference_images", "seed_value": "seed_value",
				"sort_order": "sort_order", "local_path": "local_path",
			})
			h.DB.Model(&database.Character{}).Where("id = ?", charID).Updates(updates)
		} else {
			// Insert new character.
			char := database.Character{
				DramaID:   dramaID,
				Name:      toStringOr(charData, "name", ""),
				CreatedAt: ts,
				UpdatedAt: ts,
			}
			if v, ok := toString(charData["role"]); ok {
				char.Role = &v
			}
			if v, ok := toString(charData["description"]); ok {
				char.Description = &v
			}
			if v, ok := toString(charData["appearance"]); ok {
				char.Appearance = &v
			}
			if v, ok := toString(charData["personality"]); ok {
				char.Personality = &v
			}
			if v, ok := toString(charData["voice_style"]); ok {
				char.VoiceStyle = &v
			}
			if v, ok := toString(charData["image_url"]); ok {
				char.ImageURL = &v
			}
			if v, ok := toInt(charData["sort_order"]); ok {
				char.SortOrder = &v
			}
			h.DB.Create(&char)
		}
	}

	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// PUT /api/v1/dramas/:id/episodes — Upsert episodes for a drama
// ---------------------------------------------------------------------------

// UpsertDramaEpisodes bulk upserts episodes for a drama.
// Body: { episodes: [{ id?, episode_number?, title?, ... }] }
func (h *Handler) UpsertDramaEpisodes(c *gin.Context) {
	dramaID, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var body struct {
		Episodes []map[string]interface{} `json:"episodes"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	ts := database.Now()

	for _, epData := range body.Episodes {
		if epID, ok := toInt(epData["id"]); ok && epID > 0 {
			// Update existing episode.
			updates := map[string]interface{}{
				"updated_at": ts,
			}
			copyAllowedFields(epData, updates, map[string]string{
				"title": "title", "description": "description",
				"content": "content", "script_content": "script_content",
				"status": "status", "episode_number": "episode_number",
				"duration": "duration", "video_url": "video_url",
				"thumbnail":       "thumbnail",
				"image_config_id": "image_config_id",
				"video_config_id": "video_config_id",
				"audio_config_id": "audio_config_id",
			})
			h.DB.Model(&database.Episode{}).Where("id = ?", epID).Updates(updates)
		} else {
			// Insert new episode.
			epNum := 1
			if v, ok := toInt(epData["episode_number"]); ok {
				epNum = v
			}
			title := "未命名"
			if v, ok := toString(epData["title"]); ok && v != "" {
				title = v
			}
			ep := database.Episode{
				DramaID:       dramaID,
				EpisodeNumber: epNum,
				Title:         title,
				CreatedAt:     ts,
				UpdatedAt:     ts,
			}
			if v, ok := toString(epData["status"]); ok {
				ep.Status = &v
			}
			h.DB.Create(&ep)
		}
	}

	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// Helper functions
// ---------------------------------------------------------------------------

// containsString checks if substr is contained in s (case-sensitive).
func containsString(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsSubstring(s, substr))
}

func containsSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

// stringPtr returns a pointer to the given string.
func stringPtr(s string) *string {
	return &s
}

// toInt attempts to convert an interface{} to an int.
func toInt(v interface{}) (int, bool) {
	switch val := v.(type) {
	case float64:
		return int(val), true
	case int:
		return val, true
	case json.Number:
		if i, err := val.Int64(); err == nil {
			return int(i), true
		}
	}
	return 0, false
}

// toString attempts to convert an interface{} to a string.
func toString(v interface{}) (string, bool) {
	switch val := v.(type) {
	case string:
		return val, true
	}
	return "", false
}

// toStringOr returns the string value for a key in the map, or fallback.
func toStringOr(m map[string]interface{}, key, fallback string) string {
	if v, ok := m[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return fallback
}

// copyAllowedFields copies allowed fields from a source map into an updates map.
// The allowed map keys are the JSON field names, values are the DB column names.
func copyAllowedFields(src map[string]interface{}, dest map[string]interface{}, allowed map[string]string) {
	for jsonKey, dbCol := range allowed {
		if v, ok := src[jsonKey]; ok {
			dest[dbCol] = v
		}
	}
}
