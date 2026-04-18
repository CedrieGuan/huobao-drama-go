package adapter

// ChatfireImageAdapter implements ImageProviderAdapter for Chatfire,
// which reuses the OpenAI-compatible image generation API format.
//
// All request/response handling is delegated to OpenAIImageAdapter.
// Only the provider identifier differs.
//
// Corresponds to TS: backend/src/services/adapters/registry.ts
//
//	chatfire: new OpenAIImageAdapter()
type ChatfireImageAdapter struct {
	// Embed OpenAIImageAdapter to reuse all methods.
	// Only Provider() is overridden to return "chatfire".
	OpenAIImageAdapter
}

func (a *ChatfireImageAdapter) Provider() string { return "chatfire" }

func init() {
	RegisterImageAdapter("chatfire", &ChatfireImageAdapter{})
}
