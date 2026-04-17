# Phase 5 — AI Agent 系统

> 对应 TS 版：
> - `backend/src/agents/index.ts` — Agent 工厂 + 默认 Prompt
> - `backend/src/agents/skills.ts` — SKILL.md 加载器
> - `backend/src/agents/tools/script-tools.ts` — 剧本改写工具
> - `backend/src/agents/tools/extract-tools.ts` — 角色/场景提取工具
> - `backend/src/agents/tools/storyboard-tools.ts` — 分镜拆解工具
> - `backend/src/agents/tools/voice-tools.ts` — 音色分配工具
> - `backend/src/agents/tools/grid-prompt-tools.ts` — 宫格提示词工具
> - `backend/src/routes/agent.ts` — Agent 聊天路由

---

## 1. 概述

### 1.1 Agent 系统架构

TS 版使用 Mastra 框架的 `Agent.generate()` 实现 Function Calling 循环。Go 版需要自行实现这个循环：

```
User Message
    ↓
System Prompt + SKILL.md 注入
    ↓
调用 LLM (OpenAI Chat Completions API)
    ↓
LLM 返回 tool_calls?
    ├── No  → 返回最终文本给用户
    └── Yes → 执行每个 tool 的 Handler
              ↓
              将 tool result 追加到 messages
              ↓
              再次调用 LLM → (循环，最多 maxSteps 次)
```

### 1.2 五种 Agent 类型

| Agent 类型 | 名称 | 用途 | 工具文件 |
|-----------|------|------|---------|
| `script_rewriter` | 剧本改写 | 将原始内容改写为格式化短剧剧本 | `script_tools.go` |
| `extractor` | 角色/场景提取 | 从剧本提取角色和场景（去重合并） | `extract_tools.go` |
| `storyboard_breaker` | 分镜拆解 | 将剧本拆解为分镜序列 | `storyboard_tools.go` |
| `voice_assigner` | 角色音色分配 | 为角色匹配 TTS 音色 | `voice_tools.go` |
| `grid_prompt_generator` | 图片提示词生成 | 生成英文 AI 图片提示词 | `grid_prompt_tools.go` |

---

## 2. Agent 核心实现

### 2.1 internal/agent/agent.go

```go
package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/rs/zerolog/log"
)

// Agent 是一个 AI Agent 实例
type Agent struct {
	ID           string
	Name         string
	Instructions string
	Model        string
	BaseURL      string
	APIKey       string
	Tools        []ToolDef
	MaxSteps     int
}

// ToolDef 定义一个 Agent 可调用的工具
type ToolDef struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"` // JSON Schema
	Handler     ToolHandler     `json:"-"`
}

// ToolHandler 工具执行函数签名
type ToolHandler func(ctx context.Context, args json.RawMessage) (string, error)

// AgentResult Agent 执行结果
type AgentResult struct {
	Text        string        `json:"text"`
	ToolCalls   []ToolCallInfo `json:"tool_calls,omitempty"`
	ToolResults []ToolResultInfo `json:"tool_results,omitempty"`
}

// ToolCallInfo 记录一次工具调用
type ToolCallInfo struct {
	ToolName string          `json:"tool_name"`
	Args     json.RawMessage `json:"args"`
}

// ToolResultInfo 记录一次工具执行结果
type ToolResultInfo struct {
	ToolName string `json:"tool_name"`
	Result   string `json:"result"`
}

// ========== OpenAI Chat API 数据结构 ==========

// ChatMessage 聊天消息
type ChatMessage struct {
	Role       string        `json:"role"`
	Content    string        `json:"content,omitempty"`
	ToolCalls  []ToolCall    `json:"tool_calls,omitempty"`
	ToolCallID string        `json:"tool_call_id,omitempty"`
}

// ToolCall OpenAI 格式的工具调用
type ToolCall struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Function struct {
		Name      string `json:"name"`
		Arguments string `json:"arguments"`
	} `json:"function"`
}

// ChatRequest OpenAI Chat Completions 请求
type ChatRequest struct {
	Model      string       `json:"model"`
	Messages   []ChatMessage `json:"messages"`
	Tools      []ToolSchema `json:"tools,omitempty"`
	MaxSteps   int          `json:"-"`
}

// ToolSchema OpenAI Function Calling 工具定义
type ToolSchema struct {
	Type     string       `json:"type"`
	Function FuncSchema   `json:"function"`
}

// FuncSchema 函数定义
type FuncSchema struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	Parameters  json.RawMessage `json:"parameters"`
}

// ChatResponse OpenAI Chat Completions 响应
type ChatResponse struct {
	ID      string `json:"id"`
	Choices []struct {
		Message ChatMessage `json:"message"`
	} `json:"choices"`
	Usage struct {
		PromptTokens     int `json:"prompt_tokens"`
		CompletionTokens int `json:"completion_tokens"`
		TotalTokens      int `json:"total_tokens"`
	} `json:"usage"`
}

// Run 执行 Agent 对话，手动实现 Function Calling 循环
func (a *Agent) Run(ctx context.Context, userMessage string) (*AgentResult, error) {
	messages := []ChatMessage{
		{Role: "system", Content: a.Instructions},
		{Role: "user", Content: userMessage},
	}

	// 构建 OpenAI Tools schema
	tools := a.buildToolSchemas()

	maxSteps := a.MaxSteps
	if maxSteps <= 0 {
		maxSteps = 20
	}

	var allToolCalls []ToolCallInfo
	var allToolResults []ToolResultInfo

	for step := 0; step < maxSteps; step++ {
		log.Info().
			Str("agent", a.ID).
			Int("step", step+1).
			Int("maxSteps", maxSteps).
			Msg("Agent loop iteration")

		// 调用 LLM
		resp, err := a.callLLM(ctx, messages, tools)
		if err != nil {
			return nil, fmt.Errorf("LLM call failed at step %d: %w", step+1, err)
		}

		if len(resp.Choices) == 0 {
			return nil, fmt.Errorf("LLM returned no choices at step %d", step+1)
		}

		choice := resp.Choices[0].Message

		// 如果没有 tool_calls，返回最终文本
		if len(choice.ToolCalls) == 0 {
			log.Info().
				Str("agent", a.ID).
				Int("steps", step+1).
				Str("textPreview", truncate(choice.Content, 100)).
				Msg("Agent completed")

			return &AgentResult{
				Text:        choice.Content,
				ToolCalls:   allToolCalls,
				ToolResults: allToolResults,
			}, nil
		}

		// 处理 tool calls
		messages = append(messages, choice)

		for _, tc := range choice.ToolCalls {
			toolName := tc.Function.Name
			toolArgs := json.RawMessage(tc.Function.Arguments)

			log.Info().
				Str("agent", a.ID).
				Str("tool", toolName).
				Str("argsPreview", truncate(string(toolArgs), 200)).
				Msg("Executing tool")

			// 记录工具调用
			allToolCalls = append(allToolCalls, ToolCallInfo{
				ToolName: toolName,
				Args:     toolArgs,
			})

			// 查找并执行工具
			result, err := a.executeTool(ctx, toolName, toolArgs)

			resultStr := ""
			if err != nil {
				resultStr = fmt.Sprintf("Error executing tool %s: %v", toolName, err)
				log.Error().Err(err).Str("tool", toolName).Msg("Tool execution failed")
			} else {
				resultStr = result
			}

			// 记录工具结果
			allToolResults = append(allToolResults, ToolResultInfo{
				ToolName: toolName,
				Result:   truncate(resultStr, 500),
			})

			// 追加 tool result 到消息列表
			messages = append(messages, ChatMessage{
				Role:       "tool",
				Content:    resultStr,
				ToolCallID: tc.ID,
			})
		}
	}

	return nil, fmt.Errorf("agent %s exceeded max steps (%d)", a.ID, maxSteps)
}

// callLLM 调用 OpenAI Chat Completions API
func (a *Agent) callLLM(ctx context.Context, messages []ChatMessage, tools []ToolSchema) (*ChatResponse, error) {
	reqBody := map[string]interface{}{
		"model":    a.Model,
		"messages": messages,
	}

	if len(tools) > 0 {
		reqBody["tools"] = tools
	}

	bodyBytes, _ := json.Marshal(reqBody)

	// 使用带超时的 context
	reqCtx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()

	req, err := httpNewRequestWithContext(reqCtx, "POST", a.BaseURL, bodyBytes)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+a.APIKey)

	resp, err := httpDefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("LLM HTTP request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := ioReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("LLM API error %d: %s", resp.StatusCode, string(respBody))
	}

	var chatResp ChatResponse
	if err := json.Unmarshal(respBody, &chatResp); err != nil {
		return nil, fmt.Errorf("parse LLM response: %w", err)
	}

	return &chatResp, nil
}

// executeTool 查找并执行指定名称的工具
func (a *Agent) executeTool(ctx context.Context, toolName string, args json.RawMessage) (string, error) {
	for _, tool := range a.Tools {
		if tool.Name == toolName {
			return tool.Handler(ctx, args)
		}
	}
	return "", fmt.Errorf("tool %s not found", toolName)
}

// buildToolSchemas 将 ToolDef 列表转为 OpenAI Tool Schema
func (a *Agent) buildToolSchemas() []ToolSchema {
	schemas := make([]ToolSchema, 0, len(a.Tools))
	for _, t := range a.Tools {
		params := t.Parameters
		if params == nil {
			params = json.RawMessage(`{"type":"object","properties":{}}`)
		}
		schemas = append(schemas, ToolSchema{
			Type: "function",
			Function: FuncSchema{
				Name:        t.Name,
				Description: t.Description,
				Parameters:  params,
			},
		})
	}
	return schemas
}

// truncate 截断字符串
func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
```

### 2.2 HTTP 辅助函数

```go
// agent_agent_http.go — HTTP 辅助（避免在 agent.go 中 import net/http）

var httpDefaultClient = &http.Client{}

func httpNewRequestWithContext(ctx context.Context, method, url string, body []byte) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, method, url, bytesNewReader(body))
	if err != nil {
		return nil, err
	}
	return req, nil
}

func ioReadAll(r io.Reader) ([]byte, error) {
	return io.ReadAll(r)
}

func bytesNewReader(data []byte) *bytes.Reader {
	return bytes.NewReader(data)
}
```

---

## 3. 默认 Prompt 定义

### 3.1 internal/agent/prompts.go

对应 TS 版 `backend/src/agents/index.ts` 中的 `DEFAULT_PROMPTS` 常量。

```go
package agent

// DefaultPrompts 定义 5 种 Agent 的默认 Prompt（与 TS 版完全一致）
var DefaultPrompts = map[string]struct {
	Name         string
	Instructions string
}{
	"script_rewriter": {
		Name: "剧本改写",
		Instructions: `你是专业编剧，擅长将小说改编为短剧剧本。

工作流程：
1. 调用 read_episode_script 读取原始内容
2. 根据读取到的内容，自己进行改写（输出格式化剧本格式）
3. 调用 save_script 保存改写后的完整剧本

格式化剧本格式：
- 场景头：## S编号 | 内景/外景 · 地点 | 时间段
- 动作描写：自然段落，不包含镜头语言
- 对白：角色名：（状态/表情）台词内容
- 每个场景 30-60 秒内容

注意：你必须自己完成改写工作，不要只返回指令。读取内容后直接输出改写结果并保存。`,
	},

	"extractor": {
		Name: "角色场景提取",
		Instructions: `你是制片助理，擅长从剧本中提取角色和场景信息，并在提取时与项目已有数据进行智能去重。

工作流程：
1. 调用 read_script_for_extraction 读取格式化剧本
2. 调用 read_existing_characters 读取项目中已存在的角色列表，以及当前集已关联角色
3. 调用 read_existing_scenes 读取项目中已存在的场景列表，以及当前集已关联场景
4. 优先围绕当前集剧本，分析本集实际出现的角色和场景
5. 对每个角色：若同名已存在则合并更新，若不存在则新增
6. 调用 save_dedup_characters 保存角色（去重合并，自动处理新增和更新，并关联到当前集）
7. 分析剧本内容，提取本集涉及的所有场景信息
8. 对每个场景：若同地点+时间段已存在则复用，若不存在则新增
9. 调用 save_dedup_scenes 保存场景（去重合并，自动处理新增和复用，并关联到当前集）

去重规则：
- 角色：按名字精确匹配，同名保留现有（合并信息）
- 场景：按【地点+时间段】精确匹配；同地点不同时段视为新场景

提取要求：
- 只提取当前集真实出现或被明确提及、且对当前集叙事有效的角色和场景
- 角色要包含完整的外貌特征描述（发型、服装、体态等）
- 场景要包含光线、色调、氛围等视觉信息
- 不要遗漏任何有台词或重要动作的角色`,
	},

	"storyboard_breaker": {
		Name: "分镜拆解",
		Instructions: `你是资深影视分镜师，擅长将剧本拆解为分镜方案。

工作流程：
1. 调用 read_storyboard_context 读取剧本、角色列表、场景列表
2. 将剧本拆解为镜头序列（每个镜头 10-15 秒，总体保持剧情完整连续）
3. 为每个镜头补全完整分镜字段，而不只是 video_prompt
4. 调用 save_storyboards 保存所有分镜

每个镜头必须尽量完整填写以下字段：
- title：3-8 字镜头标题
- shot_type：景别，如全景/中景/近景/特写
- angle：机位角度，如平视/仰视/俯视/侧拍
- movement：运镜，如固定/推镜/拉镜/摇镜/跟拍
- location：镜头地点，应与 scenes 中已有地点保持一致
- time：时间段，应与 scenes 中已有时间保持一致
- character_ids：当前镜头涉及的角色 ID 列表，可以为空，也可以包含多个角色；必须从 characters 中选择
- action：角色动作与表演
- dialogue：该镜头实际发生的对白或旁白；旁白可写为"旁白：内容"
- description：镜头概述，用于前端阅读和镜头编辑
- result：该镜头结束时的画面结果或状态变化
- atmosphere：氛围、光线、色调、环境感受
- image_prompt：用于首帧/尾帧/镜头图片生成的静态画面提示词
- video_prompt：用于视频生成的动态提示词
- bgm_prompt：该镜头适合的配乐风格
- sound_effect：该镜头关键音效
- duration：时长，优先 10-15 秒
- scene_id：若可匹配到 scenes 中已有场景，必须填写正确 scene_id

视频提示词格式：
- 按 3 秒为一段，用时间标记分隔
- 使用 <location>地点</location> 标记场景
- 使用 <role>角色名</role> 标记角色
- 使用 <voice>角色名</voice> 标记画外音
- 用 <n> 分隔不同时间段

示例：
"0-3秒：<location>咖啡厅</location>，近景，<role>小明</role>低头看手机。<n>3-6秒：全景，<role>小红</role>推门走入。"

额外要求：
- 优先复用 read_storyboard_context 返回的 scene_id，不要凭空创造新场景
- 镜头角色绑定必须来自 read_storyboard_context 返回的角色列表；无角色的空镜头可传空数组
- 镜头描述必须能支撑后续图片、视频、配音、音效、合成流程
- 若一个镜头没有对白，可将 dialogue 置空，但 description / action / video_prompt / image_prompt 仍必须完整
- 如果已有 existing_storyboards，仅在用户明确要求增量修改时参考；默认按当前剧本重新完整生成并保存整集分镜。`,
	},

	"voice_assigner": {
		Name: "角色音色分配",
		Instructions: `你是配音导演，擅长为角色选择合适的音色。

工作流程：
1. 调用 list_voices 获取可用音色列表
2. 调用 get_characters 获取所有角色信息
3. 根据每个角色的性别、性格、年龄、角色定位，选择最匹配的音色
4. 对每个角色调用 assign_voice 分配音色，并说明选择理由

注意：每个角色都必须分配音色，不要遗漏。`,
	},

	"grid_prompt_generator": {
		Name: "图片提示词生成",
		Instructions: `你是专业的 AI 图像提示词工程师，擅长为角色、场景和宫格图生成高质量的英文提示词。

你将收到用户的请求，告知要生成哪种类型的提示词：
- "角色" → 生成角色图片提示词
- "场景" → 生成场景图片提示词
- "宫格" → 生成宫格图提示词

## 角色图片提示词

工作流程：
1. 调用 read_characters 读取所有角色信息
2. 根据角色外貌特征（appearance）、性格（personality）、定位（role）生成英文提示词
3. 提示词结构：[外貌描述]，[性格/气质]，[角色定位]，[电影感]，[高质量]，[无文字水印]

## 场景图片提示词

工作流程：
1. 调用 read_scenes 读取所有场景信息
2. 根据场景地点（location）、时间段（time）、已有描述（prompt）生成英文提示词
3. 提示词结构：[地点]，[时间/光线/氛围]，[已有描述]，[电影感场景]，[高质量]，[无文字水印]

## 宫格图提示词

工作流程：
1. 调用 read_shots_for_grid 读取选中镜头的详细信息
2. 根据 mode 调用 generate_grid_prompt：
   - first_frame 模式：按用户指定的 rows x cols 生成首帧风格宫格
   - first_last 模式：按用户指定的 rows x cols 生成首尾帧节奏感宫格
   - multi_ref 模式：按用户指定的 rows x cols 生成同一镜头的多角度宫格
3. 返回 grid_prompt（整体提示词）和 cell_prompts（每格提示词）

提示词规范：
- 使用英文提示词
- 必须严格遵守用户指定的 rows 和 cols
- 必须明确写出 "exactly N visible panels"
- 必须明确约束 "no merged panels, no missing panels"
- 宫格位置统一写成"格1/格2/..."，参考图统一写成"图片1/图片2/..."
- 必须包含 "consistent art style" 保持风格统一
- 必须包含 "cinematic quality"
- 避免出现文字或水印
- 角色图片强调外貌和气质，场景图片强调氛围和光线，宫格图片强调整体布局一致性`,
	},
}

// ValidAgentTypes 返回有效的 Agent 类型列表
func ValidAgentTypes() []string {
	return []string{
		"script_rewriter",
		"extractor",
		"storyboard_breaker",
		"voice_assigner",
		"grid_prompt_generator",
	}
}

// IsValidAgentType 检查是否为有效的 Agent 类型
func IsValidAgentType(t string) bool {
	_, ok := DefaultPrompts[t]
	return ok
}
```

---

## 4. SKILL.md 加载器

### 4.1 internal/agent/skills.go

对应 TS 版 `backend/src/agents/skills.ts`。

```go
package agent

import (
	"os"
	"path/filepath"
	"strings"
)

// Agent 到 Skill 目录的映射
var agentSkillMap = map[string][]string{
	"script_rewriter":      {"script_rewriter"},
	"extractor":            {"extractor"},
	"storyboard_breaker":   {"storyboard_breaker"},
	"voice_assigner":       {"voice_assigner"},
	"grid_prompt_generator": {"grid_prompt_generator"},
}

// skillsDir 在 main.go 中初始化时设置
var skillsDir string

// SetSkillsDir 设置 skills 目录路径
func SetSkillsDir(dir string) {
	skillsDir = dir
}

// LoadAgentSkills 加载指定 Agent 的 SKILL.md 内容
func LoadAgentSkills(agentType string) string {
	skillIDs, ok := agentSkillMap[agentType]
	if !ok {
		return ""
	}

	var contents []string
	for _, skillID := range skillIDs {
		content := readSkill(skillID)
		if content != "" {
			contents = append(contents, content)
		}
	}

	if len(contents) == 0 {
		return ""
	}

	var sb strings.Builder
	sb.WriteString("以下是该 Agent 专属的项目技能规范（SKILL.md）。\n")
	sb.WriteString("不同 Agent 会加载不同 skill；你只需要遵守当前注入的这些技能。\n")
	sb.WriteString("你必须在不违背当前工具边界的前提下优先遵守这些规范；若与用户明确要求冲突，以用户要求为准。\n\n")

	for _, c := range contents {
		sb.WriteString(c)
		sb.WriteString("\n\n")
	}

	return sb.String()
}

// readSkill 读取单个 skill 的 SKILL.md
func readSkill(skillID string) string {
	skillPath := filepath.Join(skillsDir, skillID, "SKILL.md")

	data, err := os.ReadFile(skillPath)
	if err != nil {
		return ""
	}

	raw := string(data)
	content := stripFrontmatter(raw)
	if content == "" {
		return ""
	}

	var sb strings.Builder
	sb.WriteString("## Skill: ")
	sb.WriteString(skillID)
	sb.WriteString("\n")
	sb.WriteString(content)
	return sb.String()
}

// stripFrontmatter 去掉 YAML frontmatter（--- ... ---）
func stripFrontmatter(content string) string {
	content = strings.TrimSpace(content)
	if !strings.HasPrefix(content, "---") {
		return content
	}
	end := strings.Index(content[3:], "\n---")
	if end == -1 {
		return content
	}
	return strings.TrimSpace(content[3+end+4:])
}
```

---

## 5. Agent 工厂

### 5.1 internal/agent/factory.go

将 TS 版 `createAgent()` 逻辑用 Go 实现。从数据库读取 Agent 配置，组合 Prompt + SKILL.md + Tools，创建 Agent 实例。

```go
package agent

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/huobao-drama/backend-go/internal/service"
)

// CreateAgent 创建 Agent 实例
func CreateAgent(db *sql.DB, agentType string, episodeID, dramaID int64) (*Agent, error) {
	defaults, ok := DefaultPrompts[agentType]
	if !ok {
		return nil, fmt.Errorf("unknown agent type: %s", agentType)
	}

	// 1. 从数据库读取 Agent 配置
	dbConfig := getAgentConfigFromDB(db, agentType)

	// 2. 获取文本 AI 配置
	textConfig, err := service.GetActiveConfig(db, service.ServiceTypeText)
	if err != nil || textConfig == nil {
		return nil, fmt.Errorf("no active text AI config: %w", err)
	}

	// 3. 解析 base URL
	baseURL := service.GetTextProviderBaseURL(textConfig)
	if !strings.Contains(baseURL, "/chat/completions") {
		baseURL = strings.TrimRight(baseURL, "/") + "/chat/completions"
	}

	// 4. 确定模型
	modelName := textConfig.Model
	if dbConfig != nil && dbConfig.Model != "" {
		modelName = dbConfig.Model
	}

	// 5. 组合 Instructions = basePrompt + SKILL.md
	baseInstructions := defaults.Instructions
	if dbConfig != nil && dbConfig.SystemPrompt != "" {
		baseInstructions = dbConfig.SystemPrompt
	}

	skillInstructions := LoadAgentSkills(agentType)
	instructions := baseInstructions
	if skillInstructions != "" {
		instructions = baseInstructions + "\n\n" + skillInstructions
	}

	// 6. 确定名称
	name := defaults.Name
	if dbConfig != nil && dbConfig.Name != "" {
		name = dbConfig.Name
	}

	// 7. 创建工具
	var tools []ToolDef
	switch agentType {
	case "script_rewriter":
		tools = NewScriptTools(db, episodeID)
	case "extractor":
		tools = NewExtractTools(db, episodeID, dramaID)
	case "storyboard_breaker":
		tools = NewStoryboardTools(db, episodeID, dramaID)
	case "voice_assigner":
		tools = NewVoiceTools(db, episodeID, dramaID)
	case "grid_prompt_generator":
		tools = NewGridPromptTools(db, episodeID, dramaID)
	}

	// 8. 确定 MaxSteps
	maxSteps := 20
	if dbConfig != nil && dbConfig.MaxIterations > 0 {
		maxSteps = dbConfig.MaxIterations
	}

	return &Agent{
		ID:           agentType,
		Name:         name,
		Instructions: instructions,
		Model:        modelName,
		BaseURL:      baseURL,
		APIKey:       textConfig.APIKey,
		Tools:        tools,
		MaxSteps:     maxSteps,
	}, nil
}

// dbAgentConfig 从数据库读取的 Agent 配置
type dbAgentConfig struct {
	Name           string
	Model          string
	SystemPrompt   string
	Temperature    float64
	MaxTokens      int
	MaxIterations  int
}

// getAgentConfigFromDB 从数据库获取 Agent 配置
func getAgentConfigFromDB(db *sql.DB, agentType string) *dbAgentConfig {
	row := db.QueryRow(
		`SELECT name, model, system_prompt, temperature, max_tokens, max_iterations
		 FROM agent_configs
		 WHERE agent_type = ? AND is_active = 1 AND deleted_at IS NULL
		 LIMIT 1`,
		agentType,
	)

	var cfg dbAgentConfig
	var temp sql.NullFloat64
	var maxTokens, maxIter sql.NullInt64
	var model, systemPrompt sql.NullString

	err := row.Scan(&cfg.Name, &model, &systemPrompt, &temp, &maxTokens, &maxIter)
	if err != nil {
		return nil
	}

	if model.Valid {
		cfg.Model = model.String
	}
	if systemPrompt.Valid {
		cfg.SystemPrompt = systemPrompt.String
	}
	if temp.Valid {
		cfg.Temperature = temp.Float64
	}
	if maxTokens.Valid {
		cfg.MaxTokens = int(maxTokens.Int64)
	}
	if maxIter.Valid {
		cfg.MaxIterations = int(maxIter.Int64)
	}

	return &cfg
}

// jsonString 将值序列化为 JSON 字符串
func jsonString(v interface{}) json.RawMessage {
	b, _ := json.Marshal(v)
	return json.RawMessage(b)
}
```

---

## 6. Agent 工具实现

### 6.1 internal/agent/tool/script_tools.go

对应 TS 版 `backend/src/agents/tools/script-tools.ts`。

**功能：**
- `read_episode_script`：读取分集的原始内容
- `save_script`：保存改写后的剧本

```go
package tool

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"

	"github.com/huobao-drama/backend-go/internal/database"
	"github.com/huobao-drama/backend-go/internal/util"
)

// NewScriptTools 创建剧本改写工具集
func NewScriptTools(db *sql.DB, episodeID int64) []agent.ToolDef {
	return []agent.ToolDef{
		{
			Name:        "read_episode_script",
			Description: "读取分集的原始内容（content 或 script_content）",
			Parameters:  agent.jsonString(map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var ep database.Episode
				row := db.QueryRow("SELECT content, script_content FROM episodes WHERE id = ?", episodeID)
				var content, scriptContent sql.NullString
				if err := row.Scan(&content, &scriptContent); err != nil {
					return "", fmt.Errorf("episode %d not found", episodeID)
				}

				// 优先使用 script_content，其次 content
				text := scriptContent.String
				if text == "" {
					text = content.String
				}
				if text == "" {
					return "该分集还没有内容，请先通过前端上传原始内容。", nil
				}
				return text, nil
			},
		},
		{
			Name:        "save_script",
			Description: "保存改写后的完整剧本",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"content": map[string]interface{}{
						"type":        "string",
						"description": "改写后的完整剧本内容",
					},
				},
				"required": []string{"content"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					Content string `json:"content"`
				}
				if err := json.Unmarshal(args, &params); err != nil {
					return "", fmt.Errorf("parse args: %w", err)
				}

				if params.Content == "" {
					return "", fmt.Errorf("content cannot be empty")
				}

				now := database.Now()
				_, err := db.Exec(
					"UPDATE episodes SET script_content = ?, updated_at = ? WHERE id = ?",
					params.Content, now, episodeID,
				)
				if err != nil {
					return "", err
				}

				charCount := len([]rune(params.Content))
				return fmt.Sprintf("剧本已保存，共 %d 字。", charCount), nil
			},
		},
	}
}
```

### 6.2 internal/agent/tool/extract_tools.go

对应 TS 版 `backend/src/agents/tools/extract-tools.ts`。

**功能：**
- `read_script_for_extraction`：读取格式化剧本
- `read_existing_characters`：读取已存在的角色列表（含关联状态）
- `read_existing_scenes`：读取已存在的场景列表（含关联状态）
- `save_dedup_characters`：保存角色（去重合并 + 关联到当前集）
- `save_dedup_scenes`：保存场景（去重合并 + 关联到当前集）

```go
package tool

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/huobao-drama/backend-go/internal/database"
	"github.com/huobao-drama/backend-go/internal/util"
)

// NewExtractTools 创建角色/场景提取工具集
func NewExtractTools(db *sql.DB, episodeID, dramaID int64) []agent.ToolDef {
	return []agent.ToolDef{
		{
			Name:        "read_script_for_extraction",
			Description: "读取格式化剧本内容（script_content 字段）",
			Parameters: agent.jsonString(map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var scriptContent sql.NullString
				row := db.QueryRow("SELECT script_content FROM episodes WHERE id = ?", episodeID)
				if err := row.Scan(&scriptContent); err != nil {
					return "", fmt.Errorf("episode %d not found", episodeID)
				}
				if !scriptContent.Valid || scriptContent.String == "" {
					return "该分集还没有格式化剧本，请先运行剧本改写。", nil
				}
				return scriptContent.String, nil
			},
		},

		{
			Name:        "read_existing_characters",
			Description: "读取项目中已存在的角色列表，以及当前集已关联的角色",
			Parameters: agent.jsonString(map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				// 查询所有角色（未软删）
				rows, err := db.Query(
					`SELECT id, name, role, description, appearance, personality,
					        voice_style, image_url, reference_images
					 FROM characters WHERE drama_id = ? AND deleted_at IS NULL
					 ORDER BY sort_order ASC, id ASC`, dramaID,
				)
				if err != nil {
					return "", err
				}
				defer rows.Close()

				type charInfo struct {
					ID          int64  `json:"id"`
					Name        string `json:"name"`
					Role        string `json:"role,omitempty"`
					Description string `json:"description,omitempty"`
					Appearance  string `json:"appearance,omitempty"`
					Personality string `json:"personality,omitempty"`
					VoiceStyle  string `json:"voice_style,omitempty"`
					ImageURL    string `json:"image_url,omitempty"`
					LinkedToEp  bool   `json:"linked_to_current_episode"`
				}

				// 获取当前集关联的角色 ID
				epCharIDs, _ := database.GetEpisodeCharacterIDs(db, episodeID)

				var chars []charInfo
				for rows.Next() {
					var c charInfo
					var role, desc, app, pers, vs, img, refs sql.NullString
					rows.Scan(&c.ID, &c.Name, &role, &desc, &app, &pers, &vs, &img, &refs)
					c.Role = role.String
					c.Description = desc.String
					c.Appearance = app.String
					c.Personality = pers.String
					c.VoiceStyle = vs.String
					c.ImageURL = img.String
					c.LinkedToEp = epCharIDs[c.ID]
					chars = append(chars, c)
				}

				data, _ := json.Marshal(chars)
				return string(data), nil
			},
		},

		{
			Name:        "read_existing_scenes",
			Description: "读取项目中已存在的场景列表，以及当前集已关联的场景",
			Parameters: agent.jsonString(map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				rows, err := db.Query(
					`SELECT id, location, time, prompt, image_url, status
					 FROM scenes WHERE drama_id = ? AND deleted_at IS NULL
					 ORDER BY id ASC`, dramaID,
				)
				if err != nil {
					return "", err
				}
				defer rows.Close()

				type sceneInfo struct {
					ID        int64  `json:"id"`
					Location  string `json:"location"`
					Time      string `json:"time"`
					Prompt    string `json:"prompt"`
					ImageURL  string `json:"image_url,omitempty"`
					Status    string `json:"status"`
					LinkedToEp bool  `json:"linked_to_current_episode"`
				}

				epSceneIDs, _ := database.GetEpisodeSceneIDs(db, episodeID)

				var scenes []sceneInfo
				for rows.Next() {
					var s sceneInfo
					var img, status sql.NullString
					rows.Scan(&s.ID, &s.Location, &s.Time, &s.Prompt, &img, &status)
					s.ImageURL = img.String
					s.Status = status.String
					s.LinkedToEp = epSceneIDs[s.ID]
					scenes = append(scenes, s)
				}

				data, _ := json.Marshal(scenes)
				return string(data), nil
			},
		},

		{
			Name:        "save_dedup_characters",
			Description: "保存角色（去重合并，自动处理新增和更新，并关联到当前集）",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"characters": map[string]interface{}{
						"type": "array",
						"items": map[string]interface{}{
							"type": "object",
							"properties": map[string]interface{}{
								"name":        map[string]interface{}{"type": "string"},
								"role":        map[string]interface{}{"type": "string"},
								"description": map[string]interface{}{"type": "string"},
								"appearance":  map[string]interface{}{"type": "string"},
								"personality": map[string]interface{}{"type": "string"},
							},
							"required": []string{"name"},
						},
					},
				},
				"required": []string{"characters"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					Characters []struct {
						Name        string `json:"name"`
						Role        string `json:"role"`
						Description string `json:"description"`
						Appearance  string `json:"appearance"`
						Personality string `json:"personality"`
					} `json:"characters"`
				}
				if err := json.Unmarshal(args, &params); err != nil {
					return "", fmt.Errorf("parse args: %w", err)
				}

				now := database.Now()
				created := 0
				updated := 0
				linked := 0

				for _, ch := range params.Characters {
					if ch.Name == "" {
						continue
					}

					// 检查是否已存在同名角色
					var existingID int64
					err := db.QueryRow(
						"SELECT id FROM characters WHERE drama_id = ? AND name = ? AND deleted_at IS NULL LIMIT 1",
						dramaID, ch.Name,
					).Scan(&existingID)

					if err == nil {
						// 已存在 → 更新（只填充空字段）
						updates := []string{}
						args := []interface{}{}
						if ch.Role != "" {
							updates = append(updates, "role = ?")
							args = append(args, ch.Role)
						}
						if ch.Description != "" {
							updates = append(updates, "description = ?")
							args = append(args, ch.Description)
						}
						if ch.Appearance != "" {
							updates = append(updates, "appearance = ?")
							args = append(args, ch.Appearance)
						}
						if ch.Personality != "" {
							updates = append(updates, "personality = ?")
							args = append(args, ch.Personality)
						}
						if len(updates) > 0 {
							updates = append(updates, "updated_at = ?")
							args = append(args, now)
							args = append(args, existingID)
							sql := fmt.Sprintf("UPDATE characters SET %s WHERE id = ?", strings.Join(updates, ", "))
							db.Exec(sql, args...)
							updated++
						}
					} else {
						// 不存在 → 新增
						res, err := db.Exec(
							`INSERT INTO characters (drama_id, name, role, description, appearance, personality, created_at, updated_at)
							 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
							dramaID, ch.Name,
							util.NullIfEmpty(ch.Role),
							util.NullIfEmpty(ch.Description),
							util.NullIfEmpty(ch.Appearance),
							util.NullIfEmpty(ch.Personality),
							now, now,
						)
						if err != nil {
							continue
						}
						existingID, _ = res.LastInsertId()
						created++
					}

					// 关联到当前集（去重）
					var linkCount int
					db.QueryRow(
						"SELECT COUNT(*) FROM episode_characters WHERE episode_id = ? AND character_id = ?",
						episodeID, existingID,
					).Scan(&linkCount)
					if linkCount == 0 {
						db.Exec(
							"INSERT INTO episode_characters (episode_id, character_id, created_at) VALUES (?, ?, ?)",
							episodeID, existingID, now,
						)
						linked++
					}
				}

				return fmt.Sprintf("角色保存完成：新增 %d，更新 %d，关联 %d", created, updated, linked), nil
			},
		},

		{
			Name:        "save_dedup_scenes",
			Description: "保存场景（去重合并，自动处理新增和复用，并关联到当前集）",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"scenes": map[string]interface{}{
						"type": "array",
						"items": map[string]interface{}{
							"type": "object",
							"properties": map[string]interface{}{
								"location": map[string]interface{}{"type": "string"},
								"time":     map[string]interface{}{"type": "string"},
								"prompt":   map[string]interface{}{"type": "string"},
							},
							"required": []string{"location", "time"},
						},
					},
				},
				"required": []string{"scenes"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					Scenes []struct {
						Location string `json:"location"`
						Time     string `json:"time"`
						Prompt   string `json:"prompt"`
					} `json:"scenes"`
				}
				if err := json.Unmarshal(args, &params); err != nil {
					return "", fmt.Errorf("parse args: %w", err)
				}

				now := database.Now()
				created := 0
				reused := 0
				linked := 0

				for _, sc := range params.Scenes {
					if sc.Location == "" || sc.Time == "" {
						continue
					}

					prompt := sc.Prompt
					if prompt == "" {
						prompt = sc.Location + "，" + sc.Time
					}

					// 按地点+时间段去重
					var existingID int64
					err := db.QueryRow(
						"SELECT id FROM scenes WHERE drama_id = ? AND location = ? AND time = ? AND deleted_at IS NULL LIMIT 1",
						dramaID, sc.Location, sc.Time,
					).Scan(&existingID)

					if err == nil {
						// 已存在 → 更新 prompt（如果提供了新的）
						if sc.Prompt != "" {
							db.Exec("UPDATE scenes SET prompt = ?, updated_at = ? WHERE id = ?", sc.Prompt, now, existingID)
						}
						reused++
					} else {
						// 不存在 → 新增
						res, err := db.Exec(
							`INSERT INTO scenes (drama_id, location, time, prompt, status, created_at, updated_at)
							 VALUES (?, ?, ?, ?, 'pending', ?, ?)`,
							dramaID, sc.Location, sc.Time, prompt, now, now,
						)
						if err != nil {
							continue
						}
						existingID, _ = res.LastInsertId()
						created++
					}

					// 关联到当前集
					var linkCount int
					db.QueryRow(
						"SELECT COUNT(*) FROM episode_scenes WHERE episode_id = ? AND scene_id = ?",
						episodeID, existingID,
					).Scan(&linkCount)
					if linkCount == 0 {
						db.Exec(
							"INSERT INTO episode_scenes (episode_id, scene_id, created_at) VALUES (?, ?, ?)",
							episodeID, existingID, now,
						)
						linked++
					}
				}

				return fmt.Sprintf("场景保存完成：新增 %d，复用 %d，关联 %d", created, reused, linked), nil
			},
		},
	}
}
```

### 6.3 internal/agent/tool/storyboard_tools.go

对应 TS 版 `backend/src/agents/tools/storyboard-tools.ts`。

**功能：**
- `read_storyboard_context`：读取完整上下文（剧本+角色+场景+已有分镜）
- `save_storyboards`：全量替换保存分镜（删除旧分镜 + 插入新分镜 + 校验关联）
- `update_storyboard`：更新单个分镜
- `generate_grid_prompt`：生成宫格图提示词

```go
package tool

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/huobao-drama/backend-go/internal/database"
	"github.com/huobao-drama/backend-go/internal/util"
)

// NewStoryboardTools 创建分镜拆解工具集
func NewStoryboardTools(db *sql.DB, episodeID, dramaID int64) []agent.ToolDef {
	return []agent.ToolDef{
		{
			Name:        "read_storyboard_context",
			Description: "读取完整分镜上下文：剧本、角色列表、场景列表、已有分镜",
			Parameters: agent.jsonString(map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				// 读取分集
				var content, scriptContent sql.NullString
				db.QueryRow("SELECT content, script_content FROM episodes WHERE id = ?", episodeID).
					Scan(&content, &scriptContent)

				script := scriptContent.String
				if script == "" {
					script = content.String
				}

				// 读取角色
				chars, _ := database.GetCharactersByDramaID(db, dramaID)

				// 读取场景
				scenes, _ := database.GetScenesByDramaID(db, dramaID)

				// 读取已有分镜
				existingSBs, _ := database.GetStoryboardsByEpisodeID(db, episodeID)
				type sbInfo struct {
					database.Storyboard
					CharacterIDs []int64 `json:"character_ids"`
				}
				var existingList []sbInfo
				for _, sb := range existingSBs {
					ids, _ := database.GetStoryboardCharacterIDs(db, sb.ID)
					existingList = append(existingList, sbInfo{
						Storyboard:   sb,
						CharacterIDs: ids,
					})
				}

				result := map[string]interface{}{
					"script":               script,
					"characters":           chars,
					"scenes":               scenes,
					"existing_storyboards": existingList,
				}

				data, _ := json.Marshal(result)
				return string(data), nil
			},
		},

		{
			Name:        "save_storyboards",
			Description: "保存/替换当前集的所有分镜（全量替换）",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"storyboards": map[string]interface{}{
						"type": "array",
						"items": map[string]interface{}{
							"type": "object",
							"properties": map[string]interface{}{
								"storyboard_number": map[string]interface{}{"type": "integer"},
								"title":             map[string]interface{}{"type": "string"},
								"location":          map[string]interface{}{"type": "string"},
								"time":              map[string]interface{}{"type": "string"},
								"shot_type":         map[string]interface{}{"type": "string"},
								"angle":             map[string]interface{}{"type": "string"},
								"movement":          map[string]interface{}{"type": "string"},
								"action":            map[string]interface{}{"type": "string"},
								"result":            map[string]interface{}{"type": "string"},
								"atmosphere":        map[string]interface{}{"type": "string"},
								"image_prompt":      map[string]interface{}{"type": "string"},
								"video_prompt":      map[string]interface{}{"type": "string"},
								"bgm_prompt":        map[string]interface{}{"type": "string"},
								"sound_effect":      map[string]interface{}{"type": "string"},
								"dialogue":          map[string]interface{}{"type": "string"},
								"description":       map[string]interface{}{"type": "string"},
								"duration":          map[string]interface{}{"type": "integer"},
								"scene_id":          map[string]interface{}{"type": "integer"},
								"character_ids": map[string]interface{}{
									"type":  "array",
									"items": map[string]interface{}{"type": "integer"},
								},
							},
							"required": []string{"storyboard_number", "description"},
						},
					},
				},
				"required": []string{"storyboards"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					Storyboards []struct {
						StoryboardNumber int     `json:"storyboard_number"`
						Title            string  `json:"title"`
						Location         string  `json:"location"`
						Time             string  `json:"time"`
						ShotType         string  `json:"shot_type"`
						Angle            string  `json:"angle"`
						Movement         string  `json:"movement"`
						Action           string  `json:"action"`
						Result           string  `json:"result"`
						Atmosphere       string  `json:"atmosphere"`
						ImagePrompt      string  `json:"image_prompt"`
						VideoPrompt      string  `json:"video_prompt"`
						BGMPrompt        string  `json:"bgm_prompt"`
						SoundEffect      string  `json:"sound_effect"`
						Dialogue         string  `json:"dialogue"`
						Description      string  `json:"description"`
						Duration         int     `json:"duration"`
						SceneID          *int64  `json:"scene_id"`
						CharacterIDs     []int64 `json:"character_ids"`
					} `json:"storyboards"`
				}
				if err := json.Unmarshal(args, &params); err != nil {
					return "", fmt.Errorf("parse args: %w", err)
				}

				now := database.Now()

				// 获取有效的 scene 和 character ID 集合
				validSceneIDs, _ := database.GetEpisodeSceneIDs(db, episodeID)
				validCharIDs := make(map[int64]bool)
				chars, _ := database.GetCharactersByDramaID(db, dramaID)
				for _, c := range chars {
					validCharIDs[c.ID] = true
				}

				// 1. 删除旧分镜和关联
				oldSBs, _ := database.GetStoryboardsByEpisodeID(db, episodeID)
				for _, sb := range oldSBs {
					db.Exec("DELETE FROM storyboard_characters WHERE storyboard_id = ?", sb.ID)
					db.Exec("DELETE FROM storyboards WHERE id = ?", sb.ID)
				}

				// 2. 插入新分镜
				saved := 0
				totalDuration := 0
				for _, sb := range params.Storyboards {
					duration := sb.Duration
					if duration <= 0 {
						duration = 10
					}
					totalDuration += duration

					var sceneID interface{}
					if sb.SceneID != nil && validSceneIDs[*sb.SceneID] {
						sceneID = *sb.SceneID
					}

					res, err := db.Exec(
						`INSERT INTO storyboards
						 (episode_id, scene_id, storyboard_number, title, location, time,
						  shot_type, angle, movement, action, result, atmosphere,
						  image_prompt, video_prompt, bgm_prompt, sound_effect,
						  dialogue, description, duration, status, created_at, updated_at)
						 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)`,
						episodeID, sceneID, sb.StoryboardNumber,
						util.NullIfEmpty(sb.Title), util.NullIfEmpty(sb.Location), util.NullIfEmpty(sb.Time),
						util.NullIfEmpty(sb.ShotType), util.NullIfEmpty(sb.Angle), util.NullIfEmpty(sb.Movement),
						util.NullIfEmpty(sb.Action), util.NullIfEmpty(sb.Result), util.NullIfEmpty(sb.Atmosphere),
						util.NullIfEmpty(sb.ImagePrompt), util.NullIfEmpty(sb.VideoPrompt),
						util.NullIfEmpty(sb.BGMPrompt), util.NullIfEmpty(sb.SoundEffect),
						util.NullIfEmpty(sb.Dialogue), util.NullIfEmpty(sb.Description),
						duration, now, now,
					)
					if err != nil {
						continue
					}

					sbID, _ := res.LastInsertId()

					// 关联角色（校验有效性）
					for _, cid := range sb.CharacterIDs {
						if validCharIDs[cid] {
							db.Exec(
								"INSERT OR IGNORE INTO storyboard_characters (storyboard_id, character_id) VALUES (?, ?)",
								sbID, cid,
							)
						}
					}

					saved++
				}

				// 3. 更新集的总时长
				db.Exec("UPDATE episodes SET duration = ?, updated_at = ? WHERE id = ?", totalDuration, now, episodeID)

				return fmt.Sprintf("分镜保存完成：共 %d 个，总时长 %d 秒", saved, totalDuration), nil
			},
		},

		{
			Name:        "update_storyboard",
			Description: "更新单个分镜的部分字段",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"storyboard_id": map[string]interface{}{"type": "integer"},
					"fields": map[string]interface{}{
						"type": "object",
						"description": "要更新的字段，key 为字段名",
					},
				},
				"required": []string{"storyboard_id", "fields"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					StoryboardID int64                  `json:"storyboard_id"`
					Fields       map[string]interface{} `json:"fields"`
				}
				if err := json.Unmarshal(args, &params); err != nil {
					return "", fmt.Errorf("parse args: %w", err)
				}

				allowedFields := map[string]bool{
					"title": true, "description": true, "shot_type": true,
					"angle": true, "movement": true, "action": true,
					"dialogue": true, "duration": true, "video_prompt": true,
					"image_prompt": true, "scene_id": true, "location": true,
					"time": true, "result": true, "atmosphere": true,
					"bgm_prompt": true, "sound_effect": true,
				}

				var setClauses []string
				var setArgs []interface{}
				for k, v := range params.Fields {
					snakeKey := util.ToSnakeCase(k)
					if !allowedFields[snakeKey] {
						continue
					}
					setClauses = append(setClauses, snakeKey+" = ?")
					setArgs = append(setArgs, v)
				}

				if len(setClauses) == 0 {
					return "没有可更新的字段", nil
				}

				setClauses = append(setClauses, "updated_at = ?")
				setArgs = append(setArgs, database.Now())
				setArgs = append(setArgs, params.StoryboardID)

				sql := fmt.Sprintf("UPDATE storyboards SET %s WHERE id = ?", strings.Join(setClauses, ", "))
				db.Exec(sql, setArgs...)

				// 处理 character_ids
				if charIDs, ok := params.Fields["character_ids"]; ok {
					db.Exec("DELETE FROM storyboard_characters WHERE storyboard_id = ?", params.StoryboardID)
					if ids, ok := charIDs.([]interface{}); ok {
						for _, cid := range ids {
							if v, ok := cid.(float64); ok {
								db.Exec(
									"INSERT OR IGNORE INTO storyboard_characters (storyboard_id, character_id) VALUES (?, ?)",
									params.StoryboardID, int64(v),
								)
							}
						}
					}
				}

				return fmt.Sprintf("分镜 %d 已更新", params.StoryboardID), nil
			},
		},

		{
			Name:        "generate_grid_prompt",
			Description: "生成宫格图的整体和每格提示词",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"mode": map[string]interface{}{
						"type":        "string",
						"enum":        []string{"first_frame", "first_last", "multi_ref"},
						"description": "宫格模式",
					},
					"rows": map[string]interface{}{"type": "integer"},
					"cols": map[string]interface{}{"type": "integer"},
					"shots": map[string]interface{}{
						"type":  "array",
						"items": map[string]interface{}{"type": "object"},
					},
					"reference_legend": map[string]interface{}{
						"type":        "string",
						"description": "参考图映射说明（可选）",
					},
				},
				"required": []string{"mode", "rows", "cols", "shots"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				// 与 TS 版 generateGridPrompt 对齐
				// 简化实现：根据模式生成模板提示词
				var params struct {
					Mode            string                   `json:"mode"`
					Rows            int                      `json:"rows"`
					Cols            int                      `json:"cols"`
					Shots           []map[string]interface{} `json:"shots"`
					ReferenceLegend string                   `json:"reference_legend"`
				}
				if err := json.Unmarshal(args, &params); err != nil {
					return "", fmt.Errorf("parse args: %w", err)
				}

				totalPanels := params.Rows * params.Cols

				var gridPrompt strings.Builder
				gridPrompt.WriteString(fmt.Sprintf(
					"A comic panel grid with exactly %d visible panels arranged in %d rows and %d columns. ",
					totalPanels, params.Rows, params.Cols,
				))
				gridPrompt.WriteString("Consistent art style, cinematic quality, no text, no watermark. ")
				gridPrompt.WriteString("No merged panels, no missing panels. ")

				cellPrompts := make([]string, totalPanels)
				for i := 0; i < totalPanels; i++ {
					if i < len(params.Shots) {
						shot := params.Shots[i]
						desc, _ := shot["description"].(string)
						if desc == "" {
							desc = fmt.Sprintf("Panel %d scene", i+1)
						}
						cellPrompts[i] = fmt.Sprintf("Panel %d: %s, cinematic, high quality", i+1, desc)
					} else {
						cellPrompts[i] = fmt.Sprintf("Panel %d: continuation scene, cinematic", i+1)
					}
				}

				result := map[string]interface{}{
					"grid_prompt":  gridPrompt.String(),
					"cell_prompts": cellPrompts,
					"mode":         params.Mode,
					"rows":         params.Rows,
					"cols":         params.Cols,
					"total_panels": totalPanels,
				}

				data, _ := json.Marshal(result)
				return string(data), nil
			},
		},
	}
}
```

### 6.4 internal/agent/tool/voice_tools.go

对应 TS 版 `backend/src/agents/tools/voice-tools.ts`。

```go
package tool

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/huobao-drama/backend-go/internal/database"
)

// NewVoiceTools 创建音色分配工具集
func NewVoiceTools(db *sql.DB, episodeID, dramaID int64) []agent.ToolDef {
	return []agent.ToolDef{
		{
			Name:        "get_characters",
			Description: "获取项目中所有角色的信息（含当前音色分配状态）",
			Parameters: agent.jsonString(map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				chars, err := database.GetCharactersByDramaID(db, dramaID)
				if err != nil {
					return "", err
				}
				data, _ := json.Marshal(chars)
				return string(data), nil
			},
		},

		{
			Name:        "list_voices",
			Description: "获取当前音频服务提供商的可用音色列表",
			Parameters: agent.jsonString(map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				// 查询分集的音频配置 provider
				var audioConfigID sql.NullInt64
				db.QueryRow("SELECT audio_config_id FROM episodes WHERE id = ?", episodeID).
					Scan(&audioConfigID)

				provider := "minimax"
				if audioConfigID.Valid {
					var p sql.NullString
					db.QueryRow("SELECT provider FROM ai_service_configs WHERE id = ?", audioConfigID.Int64).Scan(&p)
					if p.Valid {
						provider = p.String
					}
				}

				// 从 ai_voices 表查询
				rows, err := db.Query(
					"SELECT voice_id, voice_name, description, language FROM ai_voices WHERE provider = ?",
					provider,
				)
				if err != nil {
					// Fallback 到默认列表
					fallback := []map[string]string{
						{"voice_id": "alloy", "voice_name": "Alloy", "gender": "neutral"},
						{"voice_id": "echo", "voice_name": "Echo", "gender": "male"},
						{"voice_id": "fable", "voice_name": "Fable", "gender": "neutral"},
						{"voice_id": "onyx", "voice_name": "Onyx", "gender": "male"},
						{"voice_id": "nova", "voice_name": "Nova", "gender": "female"},
						{"voice_id": "shimmer", "voice_name": "Shimmer", "gender": "female"},
					}
					data, _ := json.Marshal(fallback)
					return string(data), nil
				}
				defer rows.Close()

				type voiceInfo struct {
					VoiceID   string `json:"voice_id"`
					VoiceName string `json:"voice_name"`
					Gender    string `json:"gender,omitempty"`
					Language  string `json:"language,omitempty"`
				}

				var voices []voiceInfo
				for rows.Next() {
					var v voiceInfo
					var desc, lang sql.NullString
					rows.Scan(&v.VoiceID, &v.VoiceName, &desc, &lang)
					v.Language = lang.String

					// 从 description 推断性别
					if desc.Valid {
						descStr := strings.ToLower(desc.String)
						if strings.Contains(descStr, "女") || strings.Contains(descStr, "female") {
							v.Gender = "female"
						} else if strings.Contains(descStr, "男") || strings.Contains(descStr, "male") {
							v.Gender = "male"
						}
					}

					voices = append(voices, v)
				}

				if len(voices) == 0 {
					// Fallback
					voices = []voiceInfo{
						{"alloy", "Alloy", "neutral", ""},
						{"echo", "Echo", "male", ""},
						{"fable", "Fable", "neutral", ""},
						{"onyx", "Onyx", "male", ""},
						{"nova", "Nova", "female", ""},
						{"shimmer", "Shimmer", "female", ""},
					}
				}

				data, _ := json.Marshal(voices)
				return string(data), nil
			},
		},

		{
			Name:        "assign_voice",
			Description: "为指定角色分配音色",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"character_id": map[string]interface{}{"type": "integer"},
					"voice_id":     map[string]interface{}{"type": "string"},
					"reason":       map[string]interface{}{"type": "string"},
				},
				"required": []string{"character_id", "voice_id"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					CharacterID int64  `json:"character_id"`
					VoiceID     string `json:"voice_id"`
					Reason      string `json:"reason"`
				}
				if err := json.Unmarshal(args, &params); err != nil {
					return "", fmt.Errorf("parse args: %w", err)
				}

				now := database.Now()
				_, err := db.Exec(
					`UPDATE characters SET voice_style = ?, voice_sample_url = NULL, updated_at = ? WHERE id = ?`,
					params.VoiceID, now, params.CharacterID,
				)
				if err != nil {
					return "", err
				}

				reasonStr := ""
				if params.Reason != "" {
					reasonStr = fmt.Sprintf(" 理由：%s", params.Reason)
				}
				return fmt.Sprintf("角色 %d 已分配音色 %s。%s", params.CharacterID, params.VoiceID, reasonStr), nil
			},
		},
	}
}
```

### 6.5 internal/agent/tool/grid_prompt_tools.go

对应 TS 版 `backend/src/agents/tools/grid-prompt-tools.ts`。

```go
package tool

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/huobao-drama/backend-go/internal/database"
)

// NewGridPromptTools 创建宫格图提示词工具集
func NewGridPromptTools(db *sql.DB, episodeID, dramaID int64) []agent.ToolDef {
	return []agent.ToolDef{
		{
			Name:        "read_characters",
			Description: "读取项目中所有角色的信息（含外貌、性格等）",
			Parameters: agent.jsonString(map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				chars, err := database.GetCharactersByDramaID(db, dramaID)
				if err != nil {
					return "", err
				}
				data, _ := json.Marshal(chars)
				return string(data), nil
			},
		},

		{
			Name:        "generate_character_prompt",
			Description: "为角色生成英文 AI 图片提示词",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"character_id": map[string]interface{}{"type": "integer"},
					"extra":        map[string]interface{}{"type": "string"},
				},
				"required": []string{"character_id"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					CharacterID int64  `json:"character_id"`
					Extra       string `json:"extra"`
				}
				json.Unmarshal(args, &params)

				// 查询角色信息
				var name, appearance, personality, desc, role sql.NullString
				db.QueryRow(
					"SELECT name, appearance, personality, description, role FROM characters WHERE id = ?",
					params.CharacterID,
				).Scan(&name, &appearance, &personality, &desc, &role)

				var promptParts []string
				if appearance.Valid && appearance.String != "" {
					promptParts = append(promptParts, appearance.String)
				}
				if personality.Valid && personality.String != "" {
					promptParts = append(promptParts, personality.String)
				}
				if role.Valid && role.String != "" {
					promptParts = append(promptParts, role.String+" character")
				}
				if params.Extra != "" {
					promptParts = append(promptParts, params.Extra)
				}

				promptParts = append(promptParts,
					"cinematic portrait", "high quality", "consistent art style", "no text", "no watermark")

				return strings.Join(promptParts, ", "), nil
			},
		},

		{
			Name:        "read_scenes",
			Description: "读取项目中所有场景信息",
			Parameters: agent.jsonString(map[string]interface{}{
				"type":       "object",
				"properties": map[string]interface{}{},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				scenes, err := database.GetScenesByDramaID(db, dramaID)
				if err != nil {
					return "", err
				}
				data, _ := json.Marshal(scenes)
				return string(data), nil
			},
		},

		{
			Name:        "generate_scene_prompt",
			Description: "为场景生成英文 AI 图片提示词",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"scene_id": map[string]interface{}{"type": "integer"},
					"extra":    map[string]interface{}{"type": "string"},
				},
				"required": []string{"scene_id"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					SceneID int64  `json:"scene_id"`
					Extra   string `json:"extra"`
				}
				json.Unmarshal(args, &params)

				var location, time, prompt sql.NullString
				db.QueryRow(
					"SELECT location, time, prompt FROM scenes WHERE id = ?",
					params.SceneID,
				).Scan(&location, &time, &prompt)

				var promptParts []string
				if location.Valid {
					promptParts = append(promptParts, location.String)
				}
				if time.Valid {
					promptParts = append(promptParts, time.String+" lighting")
				}
				if prompt.Valid && prompt.String != "" {
					promptParts = append(promptParts, prompt.String)
				}
				if params.Extra != "" {
					promptParts = append(promptParts, params.Extra)
				}

				promptParts = append(promptParts,
					"cinematic scene", "high quality", "consistent art style", "no text", "no watermark")

				return strings.Join(promptParts, ", "), nil
			},
		},

		{
			Name:        "read_shots_for_grid",
			Description: "读取选中分镜的详细信息（用于宫格图生成）",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"storyboard_ids": map[string]interface{}{
						"type":  "array",
						"items": map[string]interface{}{"type": "integer"},
					},
				},
				"required": []string{"storyboard_ids"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					StoryboardIDs []int64 `json:"storyboard_ids"`
				}
				json.Unmarshal(args, &params)

				type shotInfo struct {
					ID               int64  `json:"id"`
					StoryboardNumber int    `json:"storyboard_number"`
					Title            string `json:"title"`
					Description      string `json:"description"`
					ImagePrompt      string `json:"image_prompt"`
					VideoPrompt      string `json:"video_prompt"`
					FirstFrameImage  string `json:"first_frame_image"`
					LastFrameImage   string `json:"last_frame_image"`
					Dialogue         string `json:"dialogue"`
				}

				var shots []shotInfo
				for _, id := range params.StoryboardIDs {
					var s shotInfo
					var title, desc, imgP, vidP, firstF, lastF, dialogue sql.NullString
					db.QueryRow(
						`SELECT id, storyboard_number, title, description, image_prompt,
						        video_prompt, first_frame_image, last_frame_image, dialogue
						 FROM storyboards WHERE id = ?`, id,
					).Scan(&s.ID, &s.StoryboardNumber, &title, &desc, &imgP, &vidP, &firstF, &lastF, &dialogue)
					s.Title = title.String
					s.Description = desc.String
					s.ImagePrompt = imgP.String
					s.VideoPrompt = vidP.String
					s.FirstFrameImage = firstF.String
					s.LastFrameImage = lastF.String
					s.Dialogue = dialogue.String
					shots = append(shots, s)
				}

				data, _ := json.Marshal(shots)
				return string(data), nil
			},
		},

		{
			Name:        "generate_grid_prompt",
			Description: "生成宫格图的整体提示词和每格提示词（支持 first_frame / first_last / multi_ref 三种模式）",
			Parameters: agent.jsonString(map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"shots": map[string]interface{}{
						"type":  "array",
						"items": map[string]interface{}{"type": "object"},
					},
					"mode": map[string]interface{}{
						"type":        "string",
						"enum":        []string{"first_frame", "first_last", "multi_ref"},
					},
					"rows": map[string]interface{}{"type": "integer"},
					"cols": map[string]interface{}{"type": "integer"},
					"reference_legend": map[string]interface{}{"type": "string"},
				},
				"required": []string{"shots", "mode", "rows", "cols"},
			}),
			Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
				var params struct {
					Shots           []map[string]interface{} `json:"shots"`
					Mode            string                   `json:"mode"`
					Rows            int                      `json:"rows"`
					Cols            int                      `json:"cols"`
					ReferenceLegend string                   `json:"reference_legend"`
				}
				json.Unmarshal(args, &params)

				totalPanels := params.Rows * params.Cols

				var gridPrompt strings.Builder
				gridPrompt.WriteString(fmt.Sprintf(
					"A comic panel grid with exactly %d visible panels arranged in %d rows and %d columns. ",
					totalPanels, params.Rows, params.Cols,
				))
				gridPrompt.WriteString("Consistent art style, cinematic quality, no text, no watermark. ")
				gridPrompt.WriteString("No merged panels, no missing panels. ")

				if params.ReferenceLegend != "" {
					gridPrompt.WriteString(params.ReferenceLegend + " ")
				}

				cellPrompts := make([]string, totalPanels)
				for i := 0; i < totalPanels; i++ {
					if i < len(params.Shots) {
						shot := params.Shots[i]
						switch params.Mode {
						case "first_frame":
							desc, _ := shot["description"].(string)
							if imgP, ok := shot["image_prompt"].(string); ok && imgP != "" {
								cellPrompts[i] = imgP
							} else {
								cellPrompts[i] = fmt.Sprintf("Panel %d: %s, cinematic, high quality", i+1, desc)
							}
						case "first_last":
							desc, _ := shot["description"].(string)
							cellPrompts[i] = fmt.Sprintf("Panel %d: %s, dramatic transition, cinematic", i+1, desc)
						case "multi_ref":
							desc, _ := shot["description"].(string)
							cellPrompts[i] = fmt.Sprintf("Panel %d: %s, multiple angles, cinematic", i+1, desc)
						}
					} else {
						cellPrompts[i] = fmt.Sprintf("Panel %d: continuation scene", i+1)
					}
				}

				result := map[string]interface{}{
					"grid_prompt":  gridPrompt.String(),
					"cell_prompts": cellPrompts,
				}

				data, _ := json.Marshal(result)
				return string(data), nil
			},
		},
	}
}
```

---

## 7. Agent 路由

### 7.1 internal/handler/agent.go

对应 TS 版 `backend/src/routes/agent.ts`。

```go
package handler

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/huobao-drama/backend-go/internal/agent"
	"github.com/huobao-drama/backend-go/internal/util"
)

// POST /api/v1/agent/:type/chat
func (h *Handler) AgentChat(c *gin.Context) {
	agentType := c.Param("type")
	if !agent.IsValidAgentType(agentType) {
		util.BadRequest(c, fmt.Sprintf("Invalid agent type: %s", agentType))
		return
	}

	var body struct {
		Message   string `json:"message"`
		DramaID   int64  `json:"drama_id"`
		EpisodeID int64  `json:"episode_id"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "message, drama_id, episode_id are required")
		return
	}

	if body.Message == "" || body.DramaID == 0 || body.EpisodeID == 0 {
		util.BadRequest(c, "message, drama_id and episode_id are required")
		return
	}

	// 创建 Agent
	a, err := agent.CreateAgent(h.DB, agentType, body.EpisodeID, body.DramaID)
	if err != nil {
		util.BadRequest(c, "Agent creation failed: "+err.Error())
		return
	}

	// 执行
	start := time.Now()
	result, err := a.Run(c.Request.Context(), body.Message)
	elapsed := time.Since(start).Seconds()

	if err != nil {
		util.ServerError(c, fmt.Sprintf("Agent execution failed (%.1fs): %s", elapsed, err.Error()))
		return
	}

	// 标准化 tool calls 和 results
	type toolCallResp struct {
		ToolName string          `json:"tool_name"`
		Args     json.RawMessage `json:"args"`
	}
	type toolResultResp struct {
		ToolName string `json:"tool_name"`
		Result   string `json:"result"`
	}

	normalizedCalls := make([]toolCallResp, 0, len(result.ToolCalls))
	for _, tc := range result.ToolCalls {
		normalizedCalls = append(normalizedCalls, toolCallResp{
			ToolName: tc.ToolName,
			Args:     tc.Args,
		})
	}

	normalizedResults := make([]toolResultResp, 0, len(result.ToolResults))
	for _, tr := range result.ToolResults {
		normalizedResults = append(normalizedResults, toolResultResp{
			ToolName: tr.ToolName,
			Result:   tr.Result,
		})
	}

	util.Success(c, gin.H{
		"type":        "done",
		"text":        result.Text,
		"tool_calls":  normalizedCalls,
		"tool_results": normalizedResults,
	})
}

// GET /api/v1/agent/:type/debug
func (h *Handler) AgentDebug(c *gin.Context) {
	agentType := c.Param("type")
	if !agent.IsValidAgentType(agentType) {
		util.BadRequest(c, fmt.Sprintf("Invalid agent type: %s", agentType))
		return
	}
	util.Success(c, gin.H{
		"agent_type": agentType,
		"valid":      true,
	})
}
```

---

## 8. 依赖关系

### 8.1 Phase 5 依赖

- **Phase 1**：数据库模型（episodes、characters、scenes、storyboards 等）
- **Phase 3**：`service.GetActiveConfig`（获取文本 AI 配置）、`service.GetTextProviderBaseURL`

### 8.2 Phase 5 为后续提供

- Phase 6 的 Agent 配置管理路由依赖 `agent.CreateAgent` 和 `agent.ValidAgentTypes`
- Grid 路由中宫格提示词生成可能调用 Agent（`grid_prompt_generator`）

---

## 9. 关键设计决策

### 9.1 为什么手写 Function Calling 循环

TS 版使用 Mastra 框架封装了 Agent 循环。Go 生态没有等价的 Agent 框架，手写循环有以下优势：

1. **完全可控**：无黑盒，调试方便
2. **无额外依赖**：只需调用 OpenAI Chat Completions API
3. **与现有架构一致**：使用相同的 `database/sql` 查询模式

### 9.2 工具参数 JSON Schema

每个工具的 `Parameters` 字段必须是合法的 JSON Schema 字符串。LLM 根据此 Schema 生成结构化参数。

TS 版使用 Zod 定义 Schema，Go 版直接写 JSON Schema 字符串。

### 9.3 工具 Handler 闭包

工具通过闭包注入 `db`、`episodeID`、`dramaID`，LLM 无需知道这些上下文：

```go
func NewScriptTools(db *sql.DB, episodeID int64) []ToolDef {
    return []ToolDef{
        {
            Handler: func(ctx context.Context, args json.RawMessage) (string, error) {
                // 闭包中可直接使用 db 和 episodeID
                db.QueryRow("SELECT ... WHERE id = ?", episodeID)
            },
        },
    }
}
```

---

## 10. 测试要点

### 10.1 Agent 循环测试

| 测试场景 | 验证内容 |
|----------|----------|
| 无 tool_calls 的单轮对话 | Agent 返回最终文本 |
| 一次 tool call | 正确执行工具并返回结果 |
| 多次 tool call | 按顺序执行所有工具 |
| 超过 maxSteps | 返回超限错误 |
| LLM 返回错误 | Agent 正确传播错误 |
| 工具执行失败 | 错误信息作为 tool result 返回给 LLM |

### 10.2 工具测试

| 工具 | 测试要点 |
|------|---------|
| `read_episode_script` | 无内容时返回提示信息 |
| `save_script` | 正确写入 script_content |
| `read_existing_characters` | 返回含 linked_to_current_episode 标记 |
| `save_dedup_characters` | 同名角色合并而非重复创建 |
| `save_dedup_scenes` | 同地点+时间复用而非重复创建 |
| `save_storyboards` | 全量替换，旧分镜被清除 |
| `save_storyboards` | 无效 scene_id 被忽略 |
| `save_storyboards` | 无效 character_id 被忽略 |
| `assign_voice` | 清除 voice_sample_url |
| `list_voices` | DB 无数据时返回 fallback 列表 |
| `generate_grid_prompt` | 三种模式正确生成提示词 |

### 10.3 SKILL 加载测试

| 测试场景 | 验证内容 |
|----------|----------|
| SKILL.md 存在 | 正确加载并注入到 instructions |
| SKILL.md 不存在 | 不影响 instructions |
| 有 frontmatter | 正确去除 YAML frontmatter |
| 多个 skill | 全部加载并拼接 |

---

## 11. 与 TS 版的对照表

| TS 文件 | Go 文件 | 说明 |
|---------|---------|------|
| `agents/index.ts` | `agent/agent.go` + `agent/factory.go` + `agent/prompts.go` | Agent 核心 |
| `agents/skills.ts` | `agent/skills.go` | SKILL.md 加载 |
| `agents/tools/script-tools.ts` | `agent/tool/script_tools.go` | 剧本改写工具 |
| `agents/tools/extract-tools.ts` | `agent/tool/extract_tools.go` | 角色/场景提取工具 |
| `agents/tools/storyboard-tools.ts` | `agent/tool/storyboard_tools.go` | 分镜拆解工具 |
| `agents/tools/voice-tools.ts` | `agent/tool/voice_tools.go` | 音色分配工具 |
| `agents/tools/grid-prompt-tools.ts` | `agent/tool/grid_prompt_tools.go` | 宫格提示词工具 |
| `routes/agent.ts` | `handler/agent.go` | Agent 路由 |