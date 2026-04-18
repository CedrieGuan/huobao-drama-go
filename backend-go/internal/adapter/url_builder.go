// Package adapter provides AI provider adapter interfaces, URL building utilities,
// a provider registry, and helper functions for image/video/TTS generation.
package adapter

import (
	"net/url"
	"strings"
)

// JoinProviderURL safely joins a provider base URL with a required prefix and endpoint path.
// It ensures the requiredPrefix exists in the final URL path and handles edge cases like
// trailing slashes, embedded prefixes, and empty segments.
//
// This mirrors the TypeScript implementation in backend/src/services/adapters/url.ts.
func JoinProviderURL(baseURL, requiredPrefix, path string) string {
	baseURL = strings.TrimRight(baseURL, "/")
	requiredPrefix = normalizeSegment(requiredPrefix)
	path = normalizeSegment(path)

	if baseURL == "" {
		return requiredPrefix + path
	}

	// Try to parse as a proper URL
	parsed, err := url.Parse(baseURL)
	if err != nil {
		// Not a valid URL, fall back to string concatenation
		return buildPathString(baseURL, requiredPrefix, path)
	}

	currentPath := parsed.Path
	currentPath = strings.TrimRight(currentPath, "/")

	// Check if currentPath already contains the requiredPrefix at a segment
	// boundary. pathEndsWithPrefix handles suffix matching and multi-segment
	// path-prefix detection (e.g. "/api/v3/images" has prefix "/api/v3").
	// For single-segment prefixes like "/v1", also check if the path starts
	// with prefix+"/" (e.g. "/v1/images" already contains "/v1").
	prefixNorm := strings.TrimSuffix(requiredPrefix, "/")
	prefixPresent := pathEndsWithPrefix(currentPath, requiredPrefix) ||
		(prefixNorm != "" && strings.HasPrefix(currentPath, prefixNorm+"/"))

	if !prefixPresent {
		currentPath = appendPath(currentPath, requiredPrefix)
	}

	// Append the endpoint path
	if path != "" {
		currentPath = appendPath(currentPath, path)
	}

	// Collapse double slashes
	currentPath = collapseSlashes(currentPath)

	parsed.Path = currentPath
	return parsed.String()
}

// normalizeSegment ensures a non-empty segment starts with "/".
func normalizeSegment(s string) string {
	s = strings.TrimSpace(s)
	if s != "" && !strings.HasPrefix(s, "/") {
		s = "/" + s
	}
	return s
}

// pathEndsWithPrefix checks whether currentPath already contains the required prefix.
// It returns true when any of these hold:
//  1. Exact match (after trimming trailing slashes)
//  2. String suffix — prefix aligns with the end of the path
//  3. Path prefix (multi-segment only) — the path starts with "prefix/" when
//     the prefix itself has multiple segments (e.g. "/api/v3/images" has prefix "/api/v3").
//     Single-segment prefixes like "/v1" only match via suffix to avoid false positives
//     when the segment merely appears at the start of a longer path.
func pathEndsWithPrefix(currentPath, prefix string) bool {
	if prefix == "" {
		return true
	}
	normalized := strings.TrimSuffix(currentPath, "/")
	prefixNorm := strings.TrimSuffix(prefix, "/")

	if normalized == prefixNorm {
		return true
	}
	// String suffix: prefix appears at the end of the path.
	if strings.HasSuffix(normalized, prefixNorm) {
		return true
	}
	// Path prefix (multi-segment only): when the prefix has multiple path
	// segments (at least one "/"), also recognize it as present when the
	// path starts with the prefix — e.g. "/api/v3/images" already has
	// prefix "/api/v3".
	if strings.Count(prefixNorm, "/") >= 2 && strings.HasPrefix(normalized, prefixNorm+"/") {
		return true
	}
	return false
}

// appendPath joins a base path and a suffix, ensuring exactly one "/" between them.
func appendPath(base, suffix string) string {
	base = strings.TrimRight(base, "/")
	suffix = strings.TrimLeft(suffix, "/")
	if suffix == "" {
		return base
	}
	if base == "" {
		return "/" + suffix
	}
	return base + "/" + suffix
}

// buildPathString performs string-based path concatenation when the base is not a valid URL.
// Uses the same path-segment-aware containment check as pathEndsWithPrefix.
func buildPathString(base, prefix, path string) string {
	result := strings.TrimRight(base, "/")

	prefixNorm := strings.TrimSuffix(prefix, "/")
	if result != prefixNorm &&
		!strings.HasSuffix(result, prefixNorm) &&
		!(strings.Count(prefixNorm, "/") >= 2 && strings.HasPrefix(result, prefixNorm+"/")) {
		result += normalizeSegment(prefix)
	}

	if path != "" {
		result += normalizeSegment(path)
	}

	return collapseSlashes(result)
}

// collapseSlashes reduces runs of two or more slashes to a single slash.
func collapseSlashes(s string) string {
	var b strings.Builder
	prev := byte(0)
	for i := 0; i < len(s); i++ {
		if s[i] == '/' && prev == '/' {
			continue
		}
		b.WriteByte(s[i])
		prev = s[i]
	}
	return b.String()
}
