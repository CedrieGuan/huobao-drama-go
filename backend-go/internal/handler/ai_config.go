package handler

import (
	"encoding/json"
	"strconv"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/database"
	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// GET /api/v1/ai-configs — List AI service configs
// ---------------------------------------------------------------------------

// ListAIConfigs returns all AI service configs, optionally filtered by service_type.
// Query params: service_type
func (h *Handler) ListAIConfigs(c *gin.Context) {
	serviceType := c.Query("service_type")

	var configs []database.AIServiceConfig
	q := h.DB.Where("1=1")
	if serviceType != "" {
		q = q.Where("service_type = ?", serviceType)
	}
	if err := q.Order("priority DESC, id ASC").Find(&configs).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	type configResponse struct {
		database.AIServiceConfig
		Model interface{} `json:"model"`
	}

	items := make([]configResponse, 0, len(configs))
	for _, cfg := range configs {
		var models interface{} = []interface{}{}
		if cfg.Model != nil {
			var parsed []interface{}
			if err := json.Unmarshal([]byte(*cfg.Model), &parsed); err == nil {
				models = parsed
			}
		}
		items = append(items, configResponse{
			AIServiceConfig: cfg,
			Model:           models,
		})
	}

	util.Success(c, items)
}

// ---------------------------------------------------------------------------
// POST /api/v1/ai-configs — Create AI service config
// ---------------------------------------------------------------------------

// CreateAIConfig creates a new AI service config entry.
func (h *Handler) CreateAIConfig(c *gin.Context) {
	var body struct {
		ServiceType string   `json:"service_type"`
		Provider    *string  `json:"provider"`
		Name        *string  `json:"name"`
		BaseURL     *string  `json:"base_url"`
		APIKey      *string  `json:"api_key"`
		Model       []string `json:"model"`
		Priority    *int     `json:"priority"`
		IsActive    *bool    `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}
	if body.ServiceType == "" {
		util.BadRequest(c, "service_type is required")
		return
	}

	ts := database.Now()

	name := body.ServiceType
	if body.Provider != nil && *body.Provider != "" {
		name = *body.Provider + "-" + body.ServiceType
	}
	if body.Name != nil && *body.Name != "" {
		name = *body.Name
	}

	baseURL := ""
	if body.BaseURL != nil {
		baseURL = *body.BaseURL
	}
	apiKey := ""
	if body.APIKey != nil {
		apiKey = *body.APIKey
	}

	modelJSON, _ := json.Marshal(body.Model)
	modelStr := string(modelJSON)

	priority := 0
	if body.Priority != nil {
		priority = *body.Priority
	}

	isActive := 1
	if body.IsActive != nil && !*body.IsActive {
		isActive = 0
	}

	config := database.AIServiceConfig{
		ServiceType: body.ServiceType,
		Provider:    body.Provider,
		Name:        name,
		BaseURL:     baseURL,
		APIKey:      apiKey,
		Model:       &modelStr,
		Priority:    &priority,
		IsActive:    isActive,
		CreatedAt:   ts,
		UpdatedAt:   ts,
	}

	if err := h.DB.Create(&config).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	// Return with parsed model array
	type configResponse struct {
		database.AIServiceConfig
		Model interface{} `json:"model"`
	}

	var models interface{} = []interface{}{}
	if body.Model != nil {
		models = body.Model
	}

	util.Created(c, configResponse{
		AIServiceConfig: config,
		Model:           models,
	})
}

// ---------------------------------------------------------------------------
// GET /api/v1/ai-configs/:id — Get single AI config
// ---------------------------------------------------------------------------

// GetAIConfig returns a single AI service config by ID.
func (h *Handler) GetAIConfig(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	var config database.AIServiceConfig
	if err := h.DB.First(&config, id).Error; err != nil {
		util.NotFound(c, "配置不存在")
		return
	}

	type configResponse struct {
		database.AIServiceConfig
		Model interface{} `json:"model"`
	}

	var models interface{} = []interface{}{}
	if config.Model != nil {
		var parsed []interface{}
		if err := json.Unmarshal([]byte(*config.Model), &parsed); err == nil {
			models = parsed
		}
	}

	util.Success(c, configResponse{
		AIServiceConfig: config,
		Model:           models,
	})
}

// ---------------------------------------------------------------------------
// PUT /api/v1/ai-configs/:id — Update AI config
// ---------------------------------------------------------------------------

// UpdateAIConfig updates select fields of an AI service config.
func (h *Handler) UpdateAIConfig(c *gin.Context) {
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

	if v, ok := body["provider"]; ok {
		updates["provider"] = v
	}
	if v, ok := body["name"]; ok {
		updates["name"] = v
	}
	if v, ok := body["base_url"]; ok {
		updates["base_url"] = v
	}
	if v, ok := body["api_key"]; ok {
		updates["api_key"] = v
	}
	if v, ok := body["model"]; ok {
		b, _ := json.Marshal(v)
		updates["model"] = string(b)
	}
	if v, ok := body["priority"]; ok {
		updates["priority"] = v
	}
	if v, ok := body["is_active"]; ok {
		updates["is_active"] = v
	}
	if v, ok := body["is_default"]; ok {
		updates["is_default"] = v
	}

	if err := h.DB.Model(&database.AIServiceConfig{}).Where("id = ?", id).Updates(updates).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/ai-configs/:id — Delete AI config
// ---------------------------------------------------------------------------

// DeleteAIConfig deletes an AI service config.
func (h *Handler) DeleteAIConfig(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		util.BadRequest(c, "invalid id")
		return
	}

	if err := h.DB.Delete(&database.AIServiceConfig{}, id).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// GET /api/v1/ai-providers — List AI service providers
// ---------------------------------------------------------------------------

// ListAIProviders returns all configured AI service providers.
func (h *Handler) ListAIProviders(c *gin.Context) {
	var providers []database.AIServiceProvider
	if err := h.DB.Order("service_type, provider").Find(&providers).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	type providerResponse struct {
		database.AIServiceProvider
		PresetModels interface{} `json:"preset_models"`
	}

	items := make([]providerResponse, 0, len(providers))
	for _, p := range providers {
		var presetModels interface{} = []interface{}{}
		if p.PresetModels != nil {
			var parsed []interface{}
			if err := json.Unmarshal([]byte(*p.PresetModels), &parsed); err == nil {
				presetModels = parsed
			}
		}
		items = append(items, providerResponse{
			AIServiceProvider: p,
			PresetModels:      presetModels,
		})
	}

	util.Success(c, items)
}

// ---------------------------------------------------------------------------
// GET /api/v1/agent-configs — List agent configs
// ---------------------------------------------------------------------------

// ListAgentConfigs returns all agent configurations.
func (h *Handler) ListAgentConfigs(c *gin.Context) {
	var configs []database.AgentConfig
	if err := h.DB.Where("deleted_at IS NULL").Order("agent_type").Find(&configs).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}
	util.Success(c, configs)
}

// ---------------------------------------------------------------------------
// POST /api/v1/agent-configs — Upsert agent config
// ---------------------------------------------------------------------------

// UpsertAgentConfig creates or updates an agent configuration by agent_type.
func (h *Handler) UpsertAgentConfig(c *gin.Context) {
	var body struct {
		AgentType    string   `json:"agent_type"`
		Name         *string  `json:"name"`
		Description  *string  `json:"description"`
		Model        *string  `json:"model"`
		SystemPrompt *string  `json:"system_prompt"`
		Temperature  *float64 `json:"temperature"`
		MaxTokens    *int     `json:"max_tokens"`
		MaxIterations *int    `json:"max_iterations"`
		IsActive     *bool    `json:"is_active"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}
	if body.AgentType == "" {
		util.BadRequest(c, "agent_type is required")
		return
	}

	ts := database.Now()

	// Find existing by agent_type
	var existing database.AgentConfig
	found := h.DB.Where("agent_type = ? AND deleted_at IS NULL", body.AgentType).First(&existing).Error == nil

	isActive := 1
	if body.IsActive != nil && !*body.IsActive {
		isActive = 0
	}

	if found {
		updates := map[string]interface{}{
			"updated_at": ts,
			"is_active":  isActive,
		}
		if body.Name != nil {
			updates["name"] = *body.Name
		}
		if body.Model != nil {
			updates["model"] = *body.Model
		}
		if body.SystemPrompt != nil {
			updates["system_prompt"] = *body.SystemPrompt
		}
		if body.Temperature != nil {
			updates["temperature"] = *body.Temperature
		}
		if body.MaxTokens != nil {
			updates["max_tokens"] = *body.MaxTokens
		}
		if body.MaxIterations != nil {
			updates["max_iterations"] = *body.MaxIterations
		}

		h.DB.Model(&existing).Updates(updates)
		h.DB.First(&existing, existing.ID)
		util.Success(c, existing)
	} else {
		name := body.AgentType
		if body.Name != nil {
			name = *body.Name
		}
		config := database.AgentConfig{
			AgentType:     body.AgentType,
			Name:          name,
			Description:   body.Description,
			Model:         body.Model,
			SystemPrompt:  body.SystemPrompt,
			Temperature:   body.Temperature,
			MaxTokens:     body.MaxTokens,
			MaxIterations: body.MaxIterations,
			IsActive:      isActive,
			CreatedAt:     ts,
			UpdatedAt:     ts,
		}
		if err := h.DB.Create(&config).Error; err != nil {
			util.ServerError(c, err.Error())
			return
		}
		util.Created(c, config)
	}
}

// ---------------------------------------------------------------------------
// PUT /api/v1/agent-configs/:id — Update agent config
// ---------------------------------------------------------------------------

// UpdateAgentConfig updates an agent configuration by ID.
func (h *Handler) UpdateAgentConfig(c *gin.Context) {
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

	if v, ok := body["name"]; ok {
		updates["name"] = v
	}
	if v, ok := body["model"]; ok {
		updates["model"] = v
	}
	if v, ok := body["system_prompt"]; ok {
		updates["system_prompt"] = v
	}
	if v, ok := body["temperature"]; ok {
		updates["temperature"] = v
	}
	if v, ok := body["max_tokens"]; ok {
		updates["max_tokens"] = v
	}
	if v, ok := body["is_active"]; ok {
		updates["is_active"] = v
	}

	if err := h.DB.Model(&database.AgentConfig{}).Where("id = ?", id).Updates(updates).Error; err != nil {
		util.ServerError(c, err.Error())
		return
	}

	util.Success(c, nil)
}
