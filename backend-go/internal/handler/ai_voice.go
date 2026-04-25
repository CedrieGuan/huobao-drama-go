package handler

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// GET /api/v1/ai-voices?provider=minimax — List AI voices
// ---------------------------------------------------------------------------

// ListAIVoices returns all AI voices, optionally filtered by provider.
func (h *Handler) ListAIVoices(c *gin.Context) {
	provider := c.Query("provider")
	if provider == "" {
		provider = "minimax"
	}

	var voices []database.AIVoice
	if err := h.DB.Where("provider = ?", provider).Find(&voices).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	type voiceResponse struct {
		VoiceID     string      `json:"voice_id"`
		VoiceName   string      `json:"voice_name"`
		Description interface{} `json:"description"`
		Language    *string     `json:"language"`
		Provider    string      `json:"provider"`
	}

	items := make([]voiceResponse, 0, len(voices))
	for _, v := range voices {
		var desc interface{} = []interface{}{}
		if v.Description != nil {
			var parsed []interface{}
			if err := json.Unmarshal([]byte(*v.Description), &parsed); err == nil {
				desc = parsed
			}
		}
		items = append(items, voiceResponse{
			VoiceID:     v.VoiceID,
			VoiceName:   v.VoiceName,
			Description: desc,
			Language:    v.Language,
			Provider:    v.Provider,
		})
	}

	util.Success(c, items)
}

// ---------------------------------------------------------------------------
// POST /api/v1/ai-voices/sync — Sync voices from MiniMax
// ---------------------------------------------------------------------------

// SyncAIVoices fetches voice list from MiniMax API and updates the database.
func (h *Handler) SyncAIVoices(c *gin.Context) {
	// Find active minimax audio config.
	var configs []database.AIServiceConfig
	if err := h.DB.Where("service_type = ? AND is_active = 1 AND provider = ?", "audio", "minimax").Find(&configs).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	if len(configs) == 0 {
		util.BadRequest(c, "No active minimax audio config found")
		return
	}

	config := configs[0]
	if config.APIKey == "" {
		util.BadRequest(c, "MiniMax API key not configured")
		return
	}

	// Build MiniMax API URL.
	baseURL := strings.TrimRight(config.BaseURL, "/")
	apiURL := baseURL + "/v1/get_voice"

	reqBody := `{"voice_type":"all"}`
	req, err := http.NewRequest("POST", apiURL, strings.NewReader(reqBody))
	if err != nil {
		util.ServerError(c, fmt.Sprintf("create request: %v", err))
		return
	}
	req.Header.Set("Authorization", "Bearer "+config.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		util.BadRequest(c, fmt.Sprintf("MiniMax API error: %v", err))
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		util.ServerError(c, fmt.Sprintf("read response: %v", err))
		return
	}

	if resp.StatusCode != http.StatusOK {
		util.BadRequest(c, fmt.Sprintf("MiniMax API error: %d", resp.StatusCode))
		return
	}

	// Parse response.
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		util.BadRequest(c, "Invalid MiniMax response")
		return
	}

	baseResp, _ := result["base_resp"].(map[string]interface{})
	if statusCode, ok := baseResp["status_code"].(float64); ok && statusCode != 0 {
		statusMsg, _ := baseResp["status_msg"].(string)
		util.BadRequest(c, statusMsg)
		return
	}

	systemVoices, ok := result["system_voice"].([]interface{})
	if !ok {
		util.Success(c, gin.H{"count": 0, "message": "No voices found"})
		return
	}

	// Filter voices (only keep 中文 and 粤语, exclude certain patterns).
	var filtered []map[string]interface{}
	for _, v := range systemVoices {
		voice, ok := v.(map[string]interface{})
		if !ok {
			continue
		}
		voiceID, _ := voice["voice_id"].(string)
		voiceName, _ := voice["voice_name"].(string)
		language := extractLanguage(voiceID, voiceName)

		if language != "中文" && language != "粤语" {
			continue
		}
		if shouldExcludeVoice(voiceID, voiceName) {
			continue
		}
		filtered = append(filtered, voice)
	}

	ts := database.Now()

	// Delete old data.
	h.DB.Where("provider = ?", "minimax").Delete(&database.AIVoice{})

	// Batch insert.
	insertCount := 0
	for _, v := range filtered {
		voiceID, _ := v["voice_id"].(string)
		voiceName, _ := v["voice_name"].(string)
		if voiceID == "" {
			continue
		}

		descJSON, _ := json.Marshal(v["description"])
		descStr := string(descJSON)
		lang := extractLanguage(voiceID, voiceName)

		voice := database.AIVoice{
			VoiceID:     voiceID,
			VoiceName:   voiceName,
			Description: &descStr,
			Language:    &lang,
			Provider:    "minimax",
			CreatedAt:   ts,
		}
		if err := h.DB.Create(&voice).Error; err != nil {
			continue
		}
		insertCount++
	}

	util.Success(c, gin.H{
		"count":   insertCount,
		"message": fmt.Sprintf("Synced %d voices", insertCount),
	})
}

// extractLanguage infers language from voice_id and voice_name.
func extractLanguage(voiceID, voiceName string) string {
	text := strings.ToLower(voiceID + " " + voiceName)
	switch {
	case strings.Contains(text, "cantonese") || strings.Contains(text, "粤"):
		return "粤语"
	case strings.Contains(text, "english") || strings.Contains(text, "aussie"):
		return "英语"
	case strings.Contains(text, "japanese") || strings.Contains(text, "日语"):
		return "日语"
	case strings.Contains(text, "korean") || strings.Contains(text, "韩"):
		return "韩语"
	case strings.Contains(text, "spanish"):
		return "西班牙语"
	case strings.Contains(text, "portuguese"):
		return "葡萄牙语"
	case strings.Contains(text, "french"):
		return "法语"
	case strings.Contains(text, "indonesian"):
		return "印尼语"
	case strings.Contains(text, "german"):
		return "德语"
	case strings.Contains(text, "russian"):
		return "俄语"
	case strings.Contains(text, "italian"):
		return "意大利语"
	case strings.Contains(text, "arabic"):
		return "阿拉伯语"
	case strings.Contains(text, "turkish"):
		return "土耳其语"
	case strings.Contains(text, "ukrainian"):
		return "乌克兰语"
	case strings.Contains(text, "dutch"):
		return "荷兰语"
	case strings.Contains(text, "vietnamese"):
		return "越南语"
	case strings.Contains(text, "chinese") || strings.Contains(text, "mandarin") || strings.Contains(text, "中文"):
		return "中文"
	default:
		return "其他"
	}
}

// shouldExcludeVoice returns true for voices that should be filtered out.
func shouldExcludeVoice(voiceID, voiceName string) bool {
	text := strings.ToLower(voiceID + " " + voiceName)
	excluded := []string{
		"jingpin", "-beta", "cartoon_pig", "cute_boy",
		"lovely_girl", "clever_boy", "robot_armor",
		"news_anchor", "male_announcer", "radio_host",
		"hk_flight_attendant",
	}
	for _, pattern := range excluded {
		if strings.Contains(text, pattern) {
			return true
		}
	}
	return false
}
