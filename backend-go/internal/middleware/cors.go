package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

// CORS returns a Gin middleware that handles Cross-Origin Resource Sharing.
// It checks the request Origin against the allowedOrigins list and sets the
// appropriate response headers. If allowedOrigins is empty, all origins are allowed.
func CORS(allowedOrigins []string) gin.HandlerFunc {
	// Build a set for fast lookup.
	originSet := make(map[string]bool, len(allowedOrigins))
	for _, o := range allowedOrigins {
		originSet[strings.TrimSpace(o)] = true
	}

	// If no origins configured, allow all (*).
	allowAll := len(allowedOrigins) == 0

	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")

		var allowOrigin string
		if allowAll {
			allowOrigin = "*"
		} else if origin != "" && originSet[origin] {
			allowOrigin = origin
		}

		if allowOrigin != "" {
			c.Header("Access-Control-Allow-Origin", allowOrigin)
			c.Header("Access-Control-Allow-Credentials", "true")
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, PATCH, OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization, X-Requested-With")
			c.Header("Access-Control-Max-Age", "86400")
		}

		// Handle preflight requests.
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}
