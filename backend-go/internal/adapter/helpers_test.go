package adapter

import "testing"

// ---------- parseSize ----------

func TestParseSize(t *testing.T) {
	tests := []struct {
		name     string
		size     string
		defaultW int
		defaultH int
		wantW    int
		wantH    int
	}{
		{"standard x", "1920x1080", 0, 0, 1920, 1080},
		{"uppercase X", "1024X768", 0, 0, 1024, 768},
		{"star separator", "1696*960", 0, 0, 1696, 960},
		{"with spaces", " 800 x 600 ", 0, 0, 800, 600},
		{"empty string", "", 100, 200, 100, 200},
		{"no separator", "big", 100, 200, 100, 200},
		{"letters in number", "abcxdef", 50, 60, 50, 60},
		{"partial number", "1920x", 10, 20, 10, 20},
		{"square", "512x512", 0, 0, 512, 512},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotW, gotH := parseSize(tt.size, tt.defaultW, tt.defaultH)
			if gotW != tt.wantW || gotH != tt.wantH {
				t.Errorf("parseSize(%q, %d, %d) = (%d, %d), want (%d, %d)",
					tt.size, tt.defaultW, tt.defaultH, gotW, gotH, tt.wantW, tt.wantH)
			}
		})
	}
}

// ---------- gcd ----------

func TestGcd(t *testing.T) {
	tests := []struct {
		a, b, want int
	}{
		{1920, 1080, 120},
		{16, 9, 1},
		{12, 8, 4},
		{100, 100, 100},
		{7, 0, 7},
		{0, 5, 5},
		{0, 0, 0},
		{17, 13, 1},
	}

	for _, tt := range tests {
		got := gcd(tt.a, tt.b)
		if got != tt.want {
			t.Errorf("gcd(%d, %d) = %d, want %d", tt.a, tt.b, got, tt.want)
		}
	}
}

// ---------- simplifyRatio ----------

func TestSimplifyRatio(t *testing.T) {
	tests := []struct {
		w, h  int
		wantW int
		wantH int
	}{
		{1920, 1080, 16, 9},
		{1280, 720, 16, 9},
		{1024, 1024, 1, 1},
		{1080, 1920, 9, 16},
		{800, 600, 4, 3},
	}

	for _, tt := range tests {
		gotW, gotH := simplifyRatio(tt.w, tt.h)
		if gotW != tt.wantW || gotH != tt.wantH {
			t.Errorf("simplifyRatio(%d, %d) = (%d, %d), want (%d, %d)",
				tt.w, tt.h, gotW, gotH, tt.wantW, tt.wantH)
		}
	}
}

// ---------- parseJSONStringArray ----------

func TestParseJSONStringArray(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  []string
	}{
		{"valid array", `["a","b","c"]`, []string{"a", "b", "c"}},
		{"empty array", `[]`, []string{}},
		{"single element", `["hello"]`, []string{"hello"}},
		{"empty string", "", nil},
		{"invalid JSON", "not json", nil},
		{"JSON object", `{"key":"val"}`, nil},
		{"number array", `[1,2,3]`, nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := parseJSONStringArray(tt.input)
			if len(got) != len(tt.want) {
				t.Fatalf("parseJSONStringArray(%q) = %v (len %d), want %v (len %d)",
					tt.input, got, len(got), tt.want, len(tt.want))
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Errorf("parseJSONStringArray(%q)[%d] = %q, want %q",
						tt.input, i, got[i], tt.want[i])
				}
			}
		})
	}
}

// ---------- firstNonEmpty ----------

func TestFirstNonEmpty(t *testing.T) {
	tests := []struct {
		name  string
		input []string
		want  string
	}{
		{"first wins", []string{"a", "b", "c"}, "a"},
		{"skip empty", []string{"", "b", "c"}, "b"},
		{"skip all empty", []string{"", "", ""}, ""},
		{"nil input", nil, ""},
		{"whitespace trimmed and kept if non-empty after trim", []string{" a ", "b"}, "a"},
		{"single value", []string{"only"}, "only"},
		{"no args", []string{}, ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := firstNonEmpty(tt.input...)
			if got != tt.want {
				t.Errorf("firstNonEmpty(%v) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

// ---------- normalizePollStatus ----------

func TestNormalizePollStatus(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		// pending variants
		{"pending", "pending"},
		{"Pending", "pending"},
		{"PENDING", "pending"},
		{"queued", "pending"},
		{"Queued", "pending"},
		// processing variants
		{"processing", "processing"},
		{"PROCESSING", "processing"},
		{"running", "processing"},
		{"Running", "processing"},
		{"in_progress", "processing"},
		{"IN_PROGRESS", "processing"},
		{"in-progress", "processing"},
		// completed variants
		{"completed", "completed"},
		{"Completed", "completed"},
		{"succeeded", "completed"},
		{"SUCCEEDED", "completed"},
		{"done", "completed"},
		{"Done", "completed"},
		{"success", "completed"},
		{"Success", "completed"},
		// failed variants
		{"failed", "failed"},
		{"Failed", "failed"},
		{"error", "failed"},
		{"Error", "failed"},
		{"cancelled", "failed"},
		{"canceled", "failed"},
		{"Cancelled", "failed"},
		// unknown defaults to processing
		{"", "processing"},
		{"unknown_status", "processing"},
		{"whatever", "processing"},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got := normalizePollStatus(tt.input)
			if got != tt.want {
				t.Errorf("normalizePollStatus(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

// ---------- clampDuration ----------

func TestClampDuration(t *testing.T) {
	tests := []struct {
		name   string
		d      int
		min    int
		max    int
		defVal int
		want   int
	}{
		{"within range", 8, 4, 12, 5, 8},
		{"below min clamped", 2, 4, 12, 5, 4},
		{"above max clamped", 15, 4, 12, 5, 12},
		{"at min boundary", 4, 4, 12, 5, 4},
		{"at max boundary", 12, 4, 12, 5, 12},
		{"zero uses default", 0, 4, 12, 5, 5},
		{"negative uses default", -3, 4, 12, 5, 5},
		{"min equals max", 7, 10, 10, 5, 10},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := clampDuration(tt.d, tt.min, tt.max, tt.defVal)
			if got != tt.want {
				t.Errorf("clampDuration(%d, %d, %d, %d) = %d, want %d",
					tt.d, tt.min, tt.max, tt.defVal, got, tt.want)
			}
		})
	}
}

// ---------- parseDataURL ----------

func TestParseDataURL(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		wantMime string
		wantData string
	}{
		{
			"valid png",
			"data:image/png;base64,abc123XYZ==",
			"image/png",
			"abc123XYZ==",
		},
		{
			"valid jpeg",
			"data:image/jpeg;base64,/9j/4AAQ==",
			"image/jpeg",
			"/9j/4AAQ==",
		},
		{
			"no base64 marker",
			"data:image/png,rawdata",
			"image/png",
			"rawdata",
		},
		{
			"empty data",
			"data:image/png;base64,",
			"image/png",
			"",
		},
		{
			"not a data url",
			"https://example.com/img.png",
			"",
			"https://example.com/img.png",
		},
		{
			"empty string",
			"",
			"",
			"",
		},
		{
			"data: without comma",
			"data:image/png;base64",
			"image/png;base64",
			"data:image/png;base64",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gotMime, gotData := parseDataURL(tt.input)
			if gotMime != tt.wantMime {
				t.Errorf("parseDataURL(%q) mime = %q, want %q", tt.input, gotMime, tt.wantMime)
			}
			if gotData != tt.wantData {
				t.Errorf("parseDataURL(%q) data = %q, want %q", tt.input, gotData, tt.wantData)
			}
		})
	}
}
