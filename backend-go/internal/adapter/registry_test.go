package adapter

import (
	"strings"
	"testing"
)

// ---------- Registration: verify all adapters self-registered via init() ----------

func TestImageAdaptersRegistered(t *testing.T) {
	expected := []string{"minimax", "openai", "gemini", "volcengine", "ali", "chatfire"}
	for _, name := range expected {
		adp := GetImageAdapter(name)
		if adp == nil {
			t.Errorf("GetImageAdapter(%q) returned nil, want non-nil", name)
		} else if adp.Provider() != name {
			// chatfire embeds OpenAIImageAdapter so Provider() must return "chatfire"
			t.Errorf("GetImageAdapter(%q).Provider() = %q, want %q", name, adp.Provider(), name)
		}
	}
}

func TestVideoAdaptersRegistered(t *testing.T) {
	expected := []string{"minimax", "volcengine", "vidu", "ali"}
	for _, name := range expected {
		adp := GetVideoAdapter(name)
		if adp == nil {
			t.Errorf("GetVideoAdapter(%q) returned nil, want non-nil", name)
		} else if adp.Provider() != name {
			t.Errorf("GetVideoAdapter(%q).Provider() = %q, want %q", name, adp.Provider(), name)
		}
	}
}

func TestTTSAdaptersRegistered(t *testing.T) {
	adp := GetTTSAdapter("minimax")
	if adp == nil {
		t.Fatal("GetTTSAdapter(\"minimax\") returned nil, want non-nil")
	}
	if adp.Provider() != "minimax" {
		t.Errorf("GetTTSAdapter(\"minimax\").Provider() = %q, want \"minimax\"", adp.Provider())
	}
}

// ---------- Fallback to minimax for unknown provider ----------

func TestGetImageAdapterFallback(t *testing.T) {
	adp := GetImageAdapter("nonexistent_provider_xyz")
	if adp == nil {
		t.Fatal("GetImageAdapter(\"nonexistent_provider_xyz\") returned nil, want minimax fallback")
	}
	if adp.Provider() != "minimax" {
		t.Errorf("fallback adapter.Provider() = %q, want \"minimax\"", adp.Provider())
	}
}

func TestGetVideoAdapterFallback(t *testing.T) {
	adp := GetVideoAdapter("nonexistent_provider_xyz")
	if adp == nil {
		t.Fatal("GetVideoAdapter(\"nonexistent_provider_xyz\") returned nil, want minimax fallback")
	}
	if adp.Provider() != "minimax" {
		t.Errorf("fallback adapter.Provider() = %q, want \"minimax\"", adp.Provider())
	}
}

func TestGetTTSAdapterFallback(t *testing.T) {
	adp := GetTTSAdapter("nonexistent_provider_xyz")
	if adp == nil {
		t.Fatal("GetTTSAdapter(\"nonexistent_provider_xyz\") returned nil, want minimax fallback")
	}
	if adp.Provider() != "minimax" {
		t.Errorf("fallback adapter.Provider() = %q, want \"minimax\"", adp.Provider())
	}
}

// ---------- Duplicate registration panics ----------

func TestRegisterImageAdapterPanicsOnDuplicate(t *testing.T) {
	defer func() {
		r := recover()
		if r == nil {
			t.Error("RegisterImageAdapter on duplicate did not panic, want panic")
		} else {
			msg, ok := r.(string)
			if !ok || !strings.Contains(msg, "already registered") {
				t.Errorf("panic message = %v, want substring 'already registered'", r)
			}
		}
	}()
	// minimax is already registered by init()
	RegisterImageAdapter("minimax", &MiniMaxImageAdapter{})
}

func TestRegisterVideoAdapterPanicsOnDuplicate(t *testing.T) {
	defer func() {
		r := recover()
		if r == nil {
			t.Error("RegisterVideoAdapter on duplicate did not panic, want panic")
		}
	}()
	RegisterVideoAdapter("minimax", &MiniMaxVideoAdapter{})
}

func TestRegisterTTSAdapterPanicsOnDuplicate(t *testing.T) {
	defer func() {
		r := recover()
		if r == nil {
			t.Error("RegisterTTSAdapter on duplicate did not panic, want panic")
		}
	}()
	RegisterTTSAdapter("minimax", &MiniMaxTTSAdapter{})
}

// ---------- GetProviderList: dynamic generation from registry ----------

func TestGetProviderListNotEmpty(t *testing.T) {
	list := GetProviderList()
	if len(list) == 0 {
		t.Fatal("GetProviderList() returned empty list")
	}
}

func TestGetProviderListCoversAllImageAdapters(t *testing.T) {
	list := GetProviderList()
	imageProviders := map[string]bool{}
	for _, entry := range list {
		if st, _ := entry["service_type"].(string); st == "image" {
			name, _ := entry["name"].(string)
			imageProviders[name] = true
		}
	}
	expected := []string{"minimax", "openai", "gemini", "volcengine", "ali", "chatfire"}
	for _, name := range expected {
		if !imageProviders[name] {
			t.Errorf("GetProviderList() missing image provider %q", name)
		}
	}
}

func TestGetProviderListCoversAllVideoAdapters(t *testing.T) {
	list := GetProviderList()
	videoProviders := map[string]bool{}
	for _, entry := range list {
		if st, _ := entry["service_type"].(string); st == "video" {
			name, _ := entry["name"].(string)
			videoProviders[name] = true
		}
	}
	expected := []string{"minimax", "volcengine", "vidu", "ali"}
	for _, name := range expected {
		if !videoProviders[name] {
			t.Errorf("GetProviderList() missing video provider %q", name)
		}
	}
}

func TestGetProviderListCoversTTS(t *testing.T) {
	list := GetProviderList()
	found := false
	for _, entry := range list {
		if name, _ := entry["name"].(string); name == "minimax" {
			if st, _ := entry["service_type"].(string); st == "audio" {
				found = true
			}
		}
	}
	if !found {
		t.Error("GetProviderList() missing minimax/audio TTS entry")
	}
}

func TestGetProviderListEntryFields(t *testing.T) {
	list := GetProviderList()
	for _, entry := range list {
		// Every entry must have the four required keys
		for _, key := range []string{"name", "display_name", "service_type", "provider"} {
			if _, ok := entry[key]; !ok {
				t.Errorf("GetProviderList() entry missing key %q: %v", key, entry)
			}
		}
		// name must equal provider
		if name, _ := entry["name"].(string); name != entry["provider"] {
			t.Errorf("entry name=%q != provider=%q", name, entry["provider"])
		}
	}
}

func TestGetProviderListDisplayNameLookup(t *testing.T) {
	list := GetProviderList()
	for _, entry := range list {
		name, _ := entry["name"].(string)
		dn, _ := entry["display_name"].(string)
		if dn == "" {
			t.Errorf("provider %q has empty display_name", name)
		}
		// Verify it comes from the displayName map when present
		if expected, ok := displayName[name]; ok && dn != expected {
			t.Errorf("provider %q display_name = %q, want %q", name, dn, expected)
		}
	}
}

func TestGetProviderListNoStaticDrift(t *testing.T) {
	// The total entry count must equal sum of all registered adapters.
	list := GetProviderList()
	wantCount := len(imageAdapters) + len(videoAdapters) + len(ttsAdapters)
	if len(list) != wantCount {
		t.Errorf("GetProviderList() returned %d entries, want %d (= %d image + %d video + %d tts)",
			len(list), wantCount, len(imageAdapters), len(videoAdapters), len(ttsAdapters))
	}
}

// ---------- Adapter concrete types ----------

func TestAdapterConcreteTypes(t *testing.T) {
	// Verify that the correct concrete types are returned for each provider.
	cases := []struct {
		provider string
		getter   func(string) ImageProviderAdapter
		want     string // concrete type name fragment
	}{
		{"minimax", GetImageAdapter, "MiniMaxImageAdapter"},
		{"openai", GetImageAdapter, "OpenAIImageAdapter"},
		{"gemini", GetImageAdapter, "GeminiImageAdapter"},
		{"volcengine", GetImageAdapter, "VolcEngineImageAdapter"},
		{"ali", GetImageAdapter, "AliImageAdapter"},
		{"chatfire", GetImageAdapter, "ChatfireImageAdapter"},
	}
	for _, tc := range cases {
		adp := tc.getter(tc.provider)
		if adp == nil {
			t.Errorf("%s adapter is nil", tc.provider)
			continue
		}
		// adp.Provider() must match the requested provider name
		if adp.Provider() != tc.provider {
			t.Errorf("GetImageAdapter(%q).Provider() = %q, want %q",
				tc.provider, adp.Provider(), tc.provider)
		}
	}
}
