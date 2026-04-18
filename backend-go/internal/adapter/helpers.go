package adapter

import (
	"encoding/json"
	"strconv"
	"strings"
)

// parseSize 将 "1920x1080" 或 "1920*1080" 解析为 (width, height)。
// 如果 size 为空或格式不合法，返回默认值。
func parseSize(size string, defaultW, defaultH int) (int, int) {
	if size == "" {
		return defaultW, defaultH
	}

	// 优先按 "x" 分割，再尝试 "*"
	parts := strings.SplitN(strings.ToLower(size), "x", 2)
	if len(parts) != 2 {
		parts = strings.SplitN(size, "*", 2)
	}
	if len(parts) != 2 {
		return defaultW, defaultH
	}

	w, errW := strconv.Atoi(strings.TrimSpace(parts[0]))
	h, errH := strconv.Atoi(strings.TrimSpace(parts[1]))
	if errW != nil || errH != nil {
		return defaultW, defaultH
	}
	return w, h
}

// simplifyRatio 使用最大公约数简化宽高比（如 1920:1080 → 16:9）。
func simplifyRatio(w, h int) (int, int) {
	g := gcd(w, h)
	return w / g, h / g
}

// gcd 计算两个非负整数的最大公约数（欧几里得算法）。
func gcd(a, b int) int {
	for b != 0 {
		a, b = b, a%b
	}
	return a
}

// parseJSONStringArray 安全地解析 JSON 字符串数组。
// 输入空字符串或非法 JSON 时返回 nil。
func parseJSONStringArray(jsonStr string) []string {
	if jsonStr == "" {
		return nil
	}
	var arr []string
	if err := json.Unmarshal([]byte(jsonStr), &arr); err != nil {
		return nil
	}
	return arr
}

// firstNonEmpty returns the first non-empty string from the given candidates.
// Shared across adapter implementations for concise field selection.
func firstNonEmpty(ss ...string) string {
	for _, s := range ss {
		s = strings.TrimSpace(s)
		if s != "" {
			return s
		}
	}
	return ""
}

// normalizePollStatus maps provider-specific status strings to the canonical
// set used across all adapters: pending / processing / completed / failed.
// Unknown values default to "processing".
func normalizePollStatus(status string) string {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "pending", "queued":
		return "pending"
	case "processing", "running", "in_progress", "in-progress":
		return "processing"
	case "completed", "succeeded", "done", "success":
		return "completed"
	case "failed", "error", "cancelled", "canceled":
		return "failed"
	default:
		return "processing"
	}
}
