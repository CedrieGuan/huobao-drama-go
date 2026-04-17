package util

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"
)

// ANSI color codes for console output.
const (
	colorReset  = "\033[0m"
	colorDim    = "\033[2m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
	colorRed    = "\033[31m"
	colorCyan   = "\033[36m"
	colorGray   = "\033[90m"
)

// Patterns used for sensitive data redaction.
var (
	apiKeyPattern     = regexp.MustCompile(`(?i)(api[_-]?key|token|authorization|secret|password)["']?\s*[:=]\s*["']?[^"',;\s}&]+`)
	urlKeyPattern     = regexp.MustCompile(`(?i)(api[_-]?key|token|access_token|secret)=([^&\s]+)`)
	bearerPattern     = regexp.MustCompile(`(?i)Bearer\s+[^\s]+`)
	base64DataPattern = regexp.MustCompile(`data:[^;]+;base64,[A-Za-z0-9+/=]{20,}`)
)

// formatTime returns the current time in HH:MM:SS format (24-hour).
func formatTime() string {
	return time.Now().Format("15:04:05")
}

// formatMeta formats a map of key-value pairs into "key=value key=value ..." string.
func formatMeta(meta map[string]interface{}) string {
	if meta == nil {
		return ""
	}
	parts := make([]string, 0, len(meta))
	for k, v := range meta {
		parts = append(parts, fmt.Sprintf("%s=%v", k, v))
	}
	return strings.Join(parts, " ")
}

// LogTaskStart logs a task start event: [scope] START action | meta...
func LogTaskStart(scope, action string, meta map[string]interface{}) {
	ts := formatTime()
	metaStr := formatMeta(meta)
	if metaStr != "" {
		metaStr = " | " + metaStr
	}
	//          dim  ts  reset [ cyan scope reset ] green "START " action metaStr reset
	fmt.Printf("%s%s%s [%s%s%s] %sSTART %s%s%s\n",
		colorDim, ts, colorReset,
		colorCyan, scope, colorReset,
		colorGreen, action, metaStr, colorReset,
	)
}

// LogTaskProgress logs a task progress event: [scope] action | meta...
func LogTaskProgress(scope, action string, meta map[string]interface{}) {
	ts := formatTime()
	metaStr := formatMeta(meta)
	if metaStr != "" {
		metaStr = " | " + metaStr
	}
	//          dim  ts  reset [ cyan scope reset ] action metaStr reset
	fmt.Printf("%s%s%s [%s%s%s] %s%s%s\n",
		colorDim, ts, colorReset,
		colorCyan, scope, colorReset,
		action, metaStr, colorReset,
	)
}

// LogTaskSuccess logs a task completion event: [scope] DONE action | meta...
func LogTaskSuccess(scope, action string, meta map[string]interface{}) {
	ts := formatTime()
	metaStr := formatMeta(meta)
	if metaStr != "" {
		metaStr = " | " + metaStr
	}
	//          dim  ts  reset [ cyan scope reset ] green "DONE " action metaStr reset
	fmt.Printf("%s%s%s [%s%s%s] %sDONE %s%s%s\n",
		colorDim, ts, colorReset,
		colorCyan, scope, colorReset,
		colorGreen, action, metaStr, colorReset,
	)
}

// LogTaskWarn logs a task warning: [scope] WARN action | meta...
func LogTaskWarn(scope, action string, meta map[string]interface{}) {
	ts := formatTime()
	metaStr := formatMeta(meta)
	if metaStr != "" {
		metaStr = " | " + metaStr
	}
	//          dim  ts  reset [ cyan scope reset ] yellow "WARN " action metaStr reset
	fmt.Printf("%s%s%s [%s%s%s] %sWARN %s%s%s\n",
		colorDim, ts, colorReset,
		colorCyan, scope, colorReset,
		colorYellow, action, metaStr, colorReset,
	)
}

// LogTaskError logs a task error: [scope] ERROR action | meta...
func LogTaskError(scope, action string, meta map[string]interface{}) {
	ts := formatTime()
	metaStr := formatMeta(meta)
	if metaStr != "" {
		metaStr = " | " + metaStr
	}
	//          dim  ts  reset [ cyan scope reset ] red "ERROR " action metaStr reset
	fmt.Printf("%s%s%s [%s%s%s] %sERROR %s%s%s\n",
		colorDim, ts, colorReset,
		colorCyan, scope, colorReset,
		colorRed, action, metaStr, colorReset,
	)
}

// LogTaskPayload pretty-prints a JSON payload with sensitive data redacted.
// It serializes the payload, applies redaction, and prints it indented.
func LogTaskPayload(scope, action string, payload interface{}) {
	raw, err := json.Marshal(payload)
	if err != nil {
		fmt.Printf("%s%s%s [%s%s%s] %s payload: <marshal error: %v>\n",
			colorDim, formatTime(), colorReset,
			colorCyan, scope, colorReset,
			action, err,
		)
		return
	}

	sanitized := sanitizeValue(string(raw))

	// Try to pretty-print if it's valid JSON after sanitization.
	var indented bytes.Buffer
	if json.Indent(&indented, []byte(sanitized), "  ", "  ") == nil {
		sanitized = indented.String()
	}

	fmt.Printf("%s%s%s [%s%s%s] %s payload:\n  %s%s%s\n",
		colorDim, formatTime(), colorReset,
		colorCyan, scope, colorReset,
		action,
		colorDim, sanitized, colorReset,
	)
}

// RedactURL removes sensitive query parameters (api_key, token, etc.) from a URL string.
func RedactURL(urlStr string) string {
	result := urlKeyPattern.ReplaceAllString(urlStr, "${1}=[REDACTED]")
	result = bearerPattern.ReplaceAllString(result, "Bearer [REDACTED]")
	return result
}

// sanitizeValue recursively redacts known sensitive keys and truncates long values.
func sanitizeValue(input string) string {
	result := apiKeyPattern.ReplaceAllString(input, "${1}: [REDACTED]")
	result = base64DataPattern.ReplaceAllString(result, "data:[redacted_base64]")

	// Truncate very long strings (over 2000 chars) that are not redacted.
	if len(result) > 2000 {
		result = result[:2000] + "... [truncated]"
	}

	return result
}
