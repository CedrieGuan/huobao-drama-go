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

// validAgentTypes lists the supported agent types.
var validAgentTypes = []string{
	"script_rewriter", "extractor", "storyboard_breaker",
	"voice_assigner", "grid_prompt_generator",
}

// ---------------------------------------------------------------------------
// POST /api/v1/agent/:type/chat — Agent chat (non-streaming)
// ---------------------------------------------------------------------------

func (h *Handler) AgentChat(c *gin.Context) {
	agentType := c.Param("type")
	if !isValidAgentType(agentType) {
		util.BadRequest(c, fmt.Sprintf("Invalid agent type: %s", agentType))
		return
	}

	var body struct {
		Message   string `json:"message"`
		DramaID   int    `json:"drama_id"`
		EpisodeID int    `json:"episode_id"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}
	if body.EpisodeID == 0 || body.DramaID == 0 {
		util.BadRequest(c, "drama_id and episode_id are required")
		return
	}

	aiConfig, provider, err := h.resolveAIConfig("text", nil)
	if err != nil {
		util.BadRequest(c, err.Error())
		return
	}

	// Resolve agent-specific config.
	var agentCfg database.AgentConfig
	systemPrompt := ""
	if h.DB.Where("agent_type = ? AND is_active = 1", agentType).First(&agentCfg).Error == nil {
		if agentCfg.SystemPrompt != nil {
			systemPrompt = *agentCfg.SystemPrompt
		}
		if agentCfg.Model != nil && *agentCfg.Model != "" {
			aiConfig.Model = *agentCfg.Model
		}
	}

	messages := []map[string]string{}
	if systemPrompt != "" {
		messages = append(messages, map[string]string{"role": "system", "content": systemPrompt})
	}

	// Load episode content as context.
	var episode database.Episode
	if h.DB.First(&episode, body.EpisodeID).Error == nil {
		contextParts := []string{}
		if episode.Content != nil && *episode.Content != "" {
			contextParts = append(contextParts, fmt.Sprintf("原始内容:\n%s", *episode.Content))
		}
		if episode.ScriptContent != nil && *episode.ScriptContent != "" {
			contextParts = append(contextParts, fmt.Sprintf("当前剧本:\n%s", *episode.ScriptContent))
		}
		if len(contextParts) > 0 {
			messages = append(messages, map[string]string{
				"role": "user", "content": strings.Join(contextParts, "\n\n"),
			})
		}
	}

	messages = append(messages, map[string]string{"role": "user", "content": body.Message})

	// Call OpenAI-compatible chat API.
	reqBody := map[string]interface{}{"model": aiConfig.Model, "messages": messages}
	reqJSON, _ := json.Marshal(reqBody)

	url := strings.TrimRight(aiConfig.BaseURL, "/") + "/v1/chat/completions"
	req, err := http.NewRequest("POST", url, strings.NewReader(string(reqJSON)))
	if err != nil {
		util.ServerError(c, err.Error())
		return
	}
	req.Header.Set("Authorization", "Bearer "+aiConfig.APIKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		util.BadRequest(c, fmt.Sprintf("AI API error: %v", err))
		return
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		util.ServerError(c, err.Error())
		return
	}

	if resp.StatusCode != http.StatusOK {
		util.BadRequest(c, fmt.Sprintf("AI API returned %d: %s", resp.StatusCode, string(respBody)))
		return
	}

	var chatResp struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		util.ServerError(c, err.Error())
		return
	}

	resultText := ""
	if len(chatResp.Choices) > 0 {
		resultText = chatResp.Choices[0].Message.Content
	}

	util.Success(c, gin.H{
		"type": "done", "text": resultText,
		"toolCalls": []interface{}{}, "toolResults": []interface{}{},
		"provider": provider,
	})
}

// ---------------------------------------------------------------------------
// GET /api/v1/agent/:type/debug
// ---------------------------------------------------------------------------

func (h *Handler) AgentDebug(c *gin.Context) {
	agentType := c.Param("type")
	if !isValidAgentType(agentType) {
		util.BadRequest(c, "Invalid agent type")
		return
	}
	util.Success(c, gin.H{"agent_type": agentType, "valid": true})
}

func isValidAgentType(t string) bool {
	for _, v := range validAgentTypes {
		if v == t {
			return true
		}
	}
	return false
}
