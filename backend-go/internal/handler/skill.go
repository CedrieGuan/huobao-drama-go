package handler

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// skillsDir returns the absolute path to the skills directory.
func skillsDir() string {
	wd, _ := os.Getwd()
	return filepath.Join(wd, "skills")
}

// skillEntry represents a skill in the list API response.
type skillEntry struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

// ---------------------------------------------------------------------------
// GET /api/v1/skills — List all skills
// ---------------------------------------------------------------------------

func (h *Handler) ListSkills(c *gin.Context) {
	dir := skillsDir()
	var skills []skillEntry
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		util.Success(c, skills)
		return
	}

	scanSkillDir(dir, "", &skills)
	util.Success(c, skills)
}

func scanSkillDir(dir, prefix string, skills *[]skillEntry) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		fullPath := filepath.Join(dir, entry.Name())
		skillPath := filepath.Join(fullPath, "SKILL.md")
		id := entry.Name()
		if prefix != "" {
			id = prefix + "/" + entry.Name()
		}

		if _, err := os.Stat(skillPath); err == nil {
			content, err := os.ReadFile(skillPath)
			name := entry.Name()
			desc := ""
			if err == nil {
				name = extractYAMLField(string(content), "name", entry.Name())
				desc = extractYAMLField(string(content), "description", "")
			}
			*skills = append(*skills, skillEntry{
				ID:          id,
				Name:        name,
				Description: desc,
			})
		}

		scanSkillDir(fullPath, id, skills)
	}
}

// ---------------------------------------------------------------------------
// GET /api/v1/skills/*id — Get skill content
// ---------------------------------------------------------------------------

func (h *Handler) GetSkill(c *gin.Context) {
	id := strings.TrimPrefix(c.Param("id"), "/")

	skillPath := filepath.Join(skillsDir(), id, "SKILL.md")
	if _, err := os.Stat(skillPath); os.IsNotExist(err) {
		util.BadRequest(c, "Skill not found")
		return
	}

	content, err := os.ReadFile(skillPath)
	if err != nil {
		util.ServerError(c, err.Error())
		return
	}

	util.Success(c, gin.H{"id": id, "content": string(content)})
}

// ---------------------------------------------------------------------------
// POST /api/v1/skills — Create new skill
// ---------------------------------------------------------------------------

func (h *Handler) CreateSkill(c *gin.Context) {
	var body struct {
		ID          string `json:"id"`
		Name        string `json:"name"`
		Description string `json:"description"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}
	if body.ID == "" {
		util.BadRequest(c, "Skill id is required")
		return
	}

	skillDir := filepath.Join(skillsDir(), body.ID)
	if _, err := os.Stat(skillDir); err == nil {
		util.BadRequest(c, "Skill already exists")
		return
	}

	os.MkdirAll(skillDir, 0o755)
	name := body.Name
	if name == "" {
		name = body.ID
	}
	content := fmt.Sprintf("---\nname: %s\ndescription: %s\n---\n\n# %s\n\nWrite your skill content here.\n", name, body.Description, name)
	os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte(content), 0o644)

	util.Success(c, gin.H{"id": body.ID, "name": name, "description": body.Description})
}

// ---------------------------------------------------------------------------
// PUT /api/v1/skills/*id — Update skill content
// ---------------------------------------------------------------------------

func (h *Handler) UpdateSkill(c *gin.Context) {
	id := strings.TrimPrefix(c.Param("id"), "/")

	var body struct {
		Content string `json:"content"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		util.BadRequest(c, "invalid request body")
		return
	}

	skillDir := filepath.Join(skillsDir(), id)
	skillPath := filepath.Join(skillDir, "SKILL.md")
	os.MkdirAll(skillDir, 0o755)
	os.WriteFile(skillPath, []byte(body.Content), 0o644)

	util.Success(c, nil)
}

// ---------------------------------------------------------------------------
// DELETE /api/v1/skills/*id — Delete skill
// ---------------------------------------------------------------------------

func (h *Handler) DeleteSkill(c *gin.Context) {
	id := strings.TrimPrefix(c.Param("id"), "/")

	skillDir := filepath.Join(skillsDir(), id)
	if _, err := os.Stat(skillDir); os.IsNotExist(err) {
		util.BadRequest(c, "Skill not found")
		return
	}

	os.RemoveAll(skillDir)
	util.Success(c, nil)
}

// extractYAMLField extracts a field value from YAML frontmatter.
func extractYAMLField(content, field, fallback string) string {
	re := regexp.MustCompile(`(?m)^` + field + `:\s*(.+)$`)
	match := re.FindStringSubmatch(content)
	if len(match) > 1 {
		return strings.TrimSpace(match[1])
	}
	return fallback
}
