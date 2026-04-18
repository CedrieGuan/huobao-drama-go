package adapter

import (
	"testing"
)

// ---------- JoinProviderURL ----------

func TestJoinProviderURL(t *testing.T) {
	tests := []struct {
		name           string
		baseURL        string
		requiredPrefix string
		path           string
		want           string
	}{
		// ---- empty base ----
		{
			name:           "empty base returns prefix + path",
			baseURL:        "",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "/v1/images",
		},
		{
			name:           "empty base with empty prefix returns path only",
			baseURL:        "",
			requiredPrefix: "",
			path:           "/images",
			want:           "/images",
		},
		{
			name:           "empty base and empty path returns prefix only",
			baseURL:        "",
			requiredPrefix: "/v1",
			path:           "",
			want:           "/v1",
		},

		// ---- base without prefix ----
		{
			name:           "base without prefix adds prefix and path",
			baseURL:        "https://api.example.com",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "https://api.example.com/v1/images",
		},
		{
			name:           "base with trailing slash trims then adds prefix",
			baseURL:        "https://api.example.com/",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "https://api.example.com/v1/images",
		},
		{
			name:           "base with multiple trailing slashes",
			baseURL:        "https://api.example.com///",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "https://api.example.com/v1/images",
		},

		// ---- base already ends with prefix (endsWith semantics) ----
		{
			name:           "base path ends with prefix does not duplicate",
			baseURL:        "https://api.example.com/v1",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "https://api.example.com/v1/images",
		},
		{
			name:           "base path with trailing slash ends with prefix",
			baseURL:        "https://api.example.com/v1/",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "https://api.example.com/v1/images",
		},
		{
			name:           "prefix embedded in longer path at end",
			baseURL:        "https://api.example.com/api/v1",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "https://api.example.com/api/v1/images",
		},

		// ---- prefix in middle, not at end (must append) ----
		{
			name:           "prefix at start of path is not duplicated",
			baseURL:        "https://api.example.com/v1/api",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "https://api.example.com/v1/api/images",
		},

		// ---- empty prefix / empty path ----
		{
			name:           "empty prefix only appends path",
			baseURL:        "https://api.example.com",
			requiredPrefix: "",
			path:           "/images",
			want:           "https://api.example.com/images",
		},
		{
			name:           "empty path only ensures prefix",
			baseURL:        "https://api.example.com",
			requiredPrefix: "/v1",
			path:           "",
			want:           "https://api.example.com/v1",
		},
		{
			name:           "empty prefix and empty path returns base",
			baseURL:        "https://api.example.com",
			requiredPrefix: "",
			path:           "",
			want:           "https://api.example.com",
		},

		// ---- prefix without leading slash (normalizeSegment adds it) ----
		{
			name:           "prefix without leading slash is normalized",
			baseURL:        "https://api.example.com",
			requiredPrefix: "v1",
			path:           "images",
			want:           "https://api.example.com/v1/images",
		},

		// ---- real-world adapter URL patterns ----
		{
			name:           "MiniMax image style",
			baseURL:        "https://api.minimax.chat",
			requiredPrefix: "/v1",
			path:           "/image_generation",
			want:           "https://api.minimax.chat/v1/image_generation",
		},
		{
			name:           "MiniMax image poll style",
			baseURL:        "https://api.minimax.chat",
			requiredPrefix: "/v1",
			path:           "/image_generation/task/task-abc-123",
			want:           "https://api.minimax.chat/v1/image_generation/task/task-abc-123",
		},
		{
			name:           "OpenAI image style",
			baseURL:        "https://api.openai.com",
			requiredPrefix: "/v1",
			path:           "/images/generations",
			want:           "https://api.openai.com/v1/images/generations",
		},
		{
			name:           "Gemini style with v1beta prefix",
			baseURL:        "https://generativelanguage.googleapis.com",
			requiredPrefix: "/v1beta",
			path:           "/models/gemini-2.5-flash-image:generateContent",
			want:           "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent",
		},
		{
			name:           "VolcEngine image style",
			baseURL:        "https://visual.volcengineapi.com",
			requiredPrefix: "/api/v3",
			path:           "/images/generations",
			want:           "https://visual.volcengineapi.com/api/v3/images/generations",
		},
		{
			name:           "VolcEngine video style",
			baseURL:        "https://visual.volcengineapi.com",
			requiredPrefix: "/api/v3",
			path:           "/contents/generations/tasks",
			want:           "https://visual.volcengineapi.com/api/v3/contents/generations/tasks",
		},
		{
			name:           "Vidu video style (empty prefix)",
			baseURL:        "https://api.vidu.com",
			requiredPrefix: "",
			path:           "/ent/v2/img2video",
			want:           "https://api.vidu.com/ent/v2/img2video",
		},
		{
			name:           "Ali DashScope image style",
			baseURL:        "https://dashscope.aliyuncs.com",
			requiredPrefix: "/api/v1",
			path:           "/services/aigc/image-generation/generation",
			want:           "https://dashscope.aliyuncs.com/api/v1/services/aigc/image-generation/generation",
		},
		{
			name:           "Ali DashScope poll task style",
			baseURL:        "https://dashscope.aliyuncs.com",
			requiredPrefix: "/api/v1",
			path:           "/tasks/task-xyz-789",
			want:           "https://dashscope.aliyuncs.com/api/v1/tasks/task-xyz-789",
		},

		// ---- base URL with existing query params ----
		{
			name:           "base with query params preserves them",
			baseURL:        "https://api.example.com?version=2",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "https://api.example.com/v1/images?version=2",
		},

		// ---- base URL with existing query params and prefix already in path ----
		{
			name:           "base with query and prefix in path",
			baseURL:        "https://api.example.com/v1?version=2",
			requiredPrefix: "/v1",
			path:           "/images",
			want:           "https://api.example.com/v1/images?version=2",
		},

		// ---- base URL with port ----
		{
			name:           "base with port number",
			baseURL:        "http://localhost:8080",
			requiredPrefix: "/api/v1",
			path:           "/images",
			want:           "http://localhost:8080/api/v1/images",
		},

		// ---- double slash collapse ----
		{
			name:           "double slashes in result are collapsed",
			baseURL:        "https://api.example.com/",
			requiredPrefix: "/v1/",
			path:           "/images",
			want:           "https://api.example.com/v1/images",
		},

		// ---- base already has full path matching prefix + path ----
		{
			name:           "base path already equals prefix + path",
			baseURL:        "https://api.example.com/v1/images",
			requiredPrefix: "/v1",
			path:           "/other",
			want:           "https://api.example.com/v1/images/other",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := JoinProviderURL(tt.baseURL, tt.requiredPrefix, tt.path)
			if got != tt.want {
				t.Errorf("JoinProviderURL(%q, %q, %q)\n  got:  %q\n  want: %q",
					tt.baseURL, tt.requiredPrefix, tt.path, got, tt.want)
			}
		})
	}
}

// ---------- normalizeSegment ----------

func TestNormalizeSegment(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"", ""},
		{"v1", "/v1"},
		{"/v1", "/v1"},
		{"  /v1  ", "/v1"},
		{"  v1  ", "/v1"},
		{"/api/v3", "/api/v3"},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := normalizeSegment(tt.input)
			if got != tt.want {
				t.Errorf("normalizeSegment(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

// ---------- pathEndsWithPrefix ----------

func TestPathEndsWithPrefix(t *testing.T) {
	tests := []struct {
		name    string
		current string
		prefix  string
		want    bool
	}{
		{"empty prefix always true", "/anything", "", true},
		{"exact match", "/v1", "/v1", true},
		{"prefix at end of longer path", "/api/v1", "/v1", true},
		{"prefix in middle not at end", "/v1/api", "/v1", false},
		{"no match at all", "/api/v2", "/v1", false},
		{"both empty", "", "", true},
		{"path empty prefix non-empty", "", "/v1", false},
		{"trailing slash on path", "/v1/", "/v1", true},
		{"trailing slash on prefix", "/v1", "/v1/", true},
		{"multi-segment prefix at end", "/api/v3/images", "/api/v3", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := pathEndsWithPrefix(tt.current, tt.prefix)
			if got != tt.want {
				t.Errorf("pathEndsWithPrefix(%q, %q) = %v, want %v",
					tt.current, tt.prefix, got, tt.want)
			}
		})
	}
}

// ---------- appendPath ----------

func TestAppendPath(t *testing.T) {
	tests := []struct {
		base   string
		suffix string
		want   string
	}{
		{"", "images", "/images"},
		{"/v1", "images", "/v1/images"},
		{"/v1", "/images", "/v1/images"},
		{"/v1/", "images", "/v1/images"},
		{"/v1/", "/images", "/v1/images"},
		{"/v1", "", "/v1"},
	}
	for _, tt := range tests {
		name := tt.base + "+" + tt.suffix
		t.Run(name, func(t *testing.T) {
			got := appendPath(tt.base, tt.suffix)
			if got != tt.want {
				t.Errorf("appendPath(%q, %q) = %q, want %q",
					tt.base, tt.suffix, got, tt.want)
			}
		})
	}
}

// ---------- collapseSlashes ----------

func TestCollapseSlashes(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"", ""},
		{"/", "/"},
		{"//", "/"},
		{"///", "/"},
		{"/v1//images", "/v1/images"},
		{"/v1///images///gen", "/v1/images/gen"},
		{"/v1/images", "/v1/images"},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := collapseSlashes(tt.input)
			if got != tt.want {
				t.Errorf("collapseSlashes(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

// ---------- buildPathString (non-URL fallback) ----------

func TestBuildPathString(t *testing.T) {
	tests := []struct {
		name   string
		base   string
		prefix string
		path   string
		want   string
	}{
		{
			name:   "base already ends with prefix",
			base:   "not-a-url/v1",
			prefix: "/v1",
			path:   "/images",
			want:   "not-a-url/v1/images",
		},
		{
			name:   "base does not end with prefix",
			base:   "not-a-url",
			prefix: "/v1",
			path:   "/images",
			want:   "not-a-url/v1/images",
		},
		{
			name:   "empty path",
			base:   "not-a-url",
			prefix: "/v1",
			path:   "",
			want:   "not-a-url/v1",
		},
		{
			name:   "empty prefix and path",
			base:   "not-a-url",
			prefix: "",
			path:   "",
			want:   "not-a-url",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := buildPathString(tt.base, tt.prefix, tt.path)
			if got != tt.want {
				t.Errorf("buildPathString(%q, %q, %q) = %q, want %q",
					tt.base, tt.prefix, tt.path, got, tt.want)
			}
		})
	}
}
