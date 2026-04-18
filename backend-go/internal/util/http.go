// Package util provides HTTP request helpers used by the adapter layer
// to execute Provider requests with configurable timeouts.
package util

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// HTTPResponse holds the result of an HTTP request.
type HTTPResponse struct {
	StatusCode int
	Body       []byte
	Headers    http.Header
}

// HTTPDoRequest executes an HTTP request with the given timeout.
//
// Parameters:
//   - method: HTTP method (GET, POST, PUT, DELETE, etc.)
//   - url: target URL string
//   - headers: optional request headers (may be nil)
//   - body: optional request body — []byte and string are sent as-is;
//     any other type is JSON-encoded automatically
//   - timeout: request deadline; 0 means no timeout
func HTTPDoRequest(method, url string, headers map[string]string, body interface{}, timeout time.Duration) (*HTTPResponse, error) {
	return HTTPDoRequestWithClient(http.DefaultClient, method, url, headers, body, timeout)
}

// HTTPDoRequestWithClient is like HTTPDoRequest but accepts a custom *http.Client.
// This is useful for tests that inject a mock transport or for tuning pool settings.
func HTTPDoRequestWithClient(client *http.Client, method, url string, headers map[string]string, body interface{}, timeout time.Duration) (*HTTPResponse, error) {
	var reqBody io.Reader
	if body != nil {
		switch v := body.(type) {
		case []byte:
			reqBody = bytes.NewReader(v)
		case string:
			reqBody = bytes.NewReader([]byte(v))
		default:
			jsonBytes, err := json.Marshal(body)
			if err != nil {
				return nil, fmt.Errorf("http: marshal body: %w", err)
			}
			reqBody = bytes.NewReader(jsonBytes)
		}
	}

	ctx := context.Background()
	if timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, timeout)
		defer cancel()
	}

	req, err := http.NewRequestWithContext(ctx, method, url, reqBody)
	if err != nil {
		return nil, fmt.Errorf("http: new request: %w", err)
	}

	for k, v := range headers {
		req.Header.Set(k, v)
	}

	// Default to JSON content type when a body is present and no
	// Content-Type has been set by the caller.
	if body != nil && req.Header.Get("Content-Type") == "" {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("http: do request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("http: read body: %w", err)
	}

	return &HTTPResponse{
		StatusCode: resp.StatusCode,
		Body:       respBody,
		Headers:    resp.Header,
	}, nil
}

// IsHTTPSuccess returns true if the status code is in the 2xx range.
func IsHTTPSuccess(statusCode int) bool {
	return statusCode >= 200 && statusCode < 300
}
