package util

import (
	"regexp"
	"strings"
)

// camelCase to snake_case regex: insert underscore before each uppercase letter
var camelToSnakeRe = regexp.MustCompile("([a-z0-9])([A-Z])")

// ToSnakeCase converts a camelCase or PascalCase string to snake_case.
// Example: "dramaId" → "drama_id", "CreatedAt" → "created_at"
func ToSnakeCase(s string) string {
	result := camelToSnakeRe.ReplaceAllString(s, "${1}_${2}")
	return strings.ToLower(result)
}

// ToSnakeCaseMap converts all keys in a map from camelCase to snake_case.
// Values are left unchanged. Nil maps return nil.
func ToSnakeCaseMap(m map[string]interface{}) map[string]interface{} {
	if m == nil {
		return nil
	}
	result := make(map[string]interface{}, len(m))
	for k, v := range m {
		result[ToSnakeCase(k)] = v
	}
	return result
}

// ToSnakeCaseSlice converts all keys in each map within a slice from camelCase to snake_case.
func ToSnakeCaseSlice(items []map[string]interface{}) []map[string]interface{} {
	if items == nil {
		return nil
	}
	result := make([]map[string]interface{}, len(items))
	for i, item := range items {
		result[i] = ToSnakeCaseMap(item)
	}
	return result
}
