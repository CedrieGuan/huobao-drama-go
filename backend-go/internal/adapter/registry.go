// Package adapter provides a unified abstraction layer over different AI service
// providers (MiniMax, OpenAI, Gemini, VolcEngine, Vidu, Ali, Chatfire).
//
// The registry maps provider names to their adapter implementations. Each adapter
// is responsible for translating the common request/response types defined in
// types.go into the provider-specific wire format.
//
// Adapters self-register via RegisterImageAdapter / RegisterVideoAdapter /
// RegisterTTSAdapter, typically from an init() function in each adapter file.
package adapter

import (
	"fmt"
	"sync"
)

// ========== Adapter registries ==========

var (
	registryMu    sync.RWMutex
	imageAdapters = make(map[string]ImageProviderAdapter)
	videoAdapters = make(map[string]VideoProviderAdapter)
	ttsAdapters   = make(map[string]TTSProviderAdapter)
)

// displayName maps provider identifiers to human-readable names
// for the AI Providers list API.
var displayName = map[string]string{
	"minimax":    "MiniMax",
	"openai":     "OpenAI",
	"gemini":     "Google Gemini",
	"volcengine": "火山引擎",
	"vidu":       "Vidu",
	"ali":        "阿里云通义万相",
	"chatfire":   "ChatFire",
}

// ========== Registration functions ==========

// RegisterImageAdapter registers an image generation adapter under the given name.
func RegisterImageAdapter(name string, adp ImageProviderAdapter) {
	registryMu.Lock()
	defer registryMu.Unlock()
	if _, exists := imageAdapters[name]; exists {
		panic(fmt.Sprintf("adapter: image adapter already registered: %s", name))
	}
	imageAdapters[name] = adp
}

// RegisterVideoAdapter registers a video generation adapter under the given name.
func RegisterVideoAdapter(name string, adp VideoProviderAdapter) {
	registryMu.Lock()
	defer registryMu.Unlock()
	if _, exists := videoAdapters[name]; exists {
		panic(fmt.Sprintf("adapter: video adapter already registered: %s", name))
	}
	videoAdapters[name] = adp
}

// RegisterTTSAdapter registers a TTS adapter under the given name.
func RegisterTTSAdapter(name string, adp TTSProviderAdapter) {
	registryMu.Lock()
	defer registryMu.Unlock()
	if _, exists := ttsAdapters[name]; exists {
		panic(fmt.Sprintf("adapter: tts adapter already registered: %s", name))
	}
	ttsAdapters[name] = adp
}

// ========== Lookup functions ==========

// GetImageAdapter returns the image adapter for the given provider.
// Unknown providers fall back to "minimax".
func GetImageAdapter(provider string) ImageProviderAdapter {
	registryMu.RLock()
	defer registryMu.RUnlock()
	if adp, ok := imageAdapters[provider]; ok {
		return adp
	}
	if adp, ok := imageAdapters["minimax"]; ok {
		return adp
	}
	return nil
}

// GetVideoAdapter returns the video adapter for the given provider.
// Unknown providers fall back to "minimax".
func GetVideoAdapter(provider string) VideoProviderAdapter {
	registryMu.RLock()
	defer registryMu.RUnlock()
	if adp, ok := videoAdapters[provider]; ok {
		return adp
	}
	if adp, ok := videoAdapters["minimax"]; ok {
		return adp
	}
	return nil
}

// GetTTSAdapter returns the TTS adapter for the given provider.
// Unknown providers fall back to "minimax".
func GetTTSAdapter(provider string) TTSProviderAdapter {
	registryMu.RLock()
	defer registryMu.RUnlock()
	if adp, ok := ttsAdapters[provider]; ok {
		return adp
	}
	if adp, ok := ttsAdapters["minimax"]; ok {
		return adp
	}
	return nil
}

// GetProviderList returns metadata for every registered provider.
// Generated dynamically from the three adapter registries so the list
// never drifts from the actual registered adapters.
//
// Used by the AI Providers list API to enumerate available services.
func GetProviderList() []map[string]interface{} {
	registryMu.RLock()
	defer registryMu.RUnlock()

	// Collect unique provider names while preserving insertion order.
	type entry struct{ name, serviceType string }
	var entries []entry

	for name := range imageAdapters {
		entries = append(entries, entry{name, "image"})
	}
	for name := range videoAdapters {
		entries = append(entries, entry{name, "video"})
	}
	for name := range ttsAdapters {
		entries = append(entries, entry{name, "audio"})
	}

	providers := make([]map[string]interface{}, 0, len(entries))
	for _, e := range entries {
		dn, ok := displayName[e.name]
		if !ok {
			dn = e.name
		}
		providers = append(providers, map[string]interface{}{
			"name":         e.name,
			"display_name": dn,
			"service_type": e.serviceType,
			"provider":     e.name,
		})
	}
	return providers
}
