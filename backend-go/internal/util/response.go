// Package util provides shared response helpers, transformers, and logging utilities
// used across all HTTP handlers in the backend-go application.
package util

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// APIResponse is the unified JSON envelope returned by all handlers.
// It matches the TypeScript backend's { code, data, message } format exactly.
type APIResponse struct {
	Code    int         `json:"code"`
	Data    interface{} `json:"data,omitempty"`
	Message string      `json:"message"`
}

// Success responds with HTTP 200 and the standard success envelope.
// If data is nil, the "data" field is still included as null.
func Success(c *gin.Context, data interface{}) {
	c.JSON(http.StatusOK, APIResponse{
		Code:    200,
		Data:    data,
		Message: "success",
	})
}

// Created responds with HTTP 201 and the standard created envelope.
func Created(c *gin.Context, data interface{}) {
	c.JSON(http.StatusCreated, APIResponse{
		Code:    201,
		Data:    data,
		Message: "created",
	})
}

// BadRequest responds with HTTP 400 and an error message.
func BadRequest(c *gin.Context, msg string) {
	c.JSON(http.StatusBadRequest, APIResponse{
		Code:    400,
		Message: msg,
	})
}

// NotFound responds with HTTP 404 and an error message.
func NotFound(c *gin.Context, msg string) {
	c.JSON(http.StatusNotFound, APIResponse{
		Code:    404,
		Message: msg,
	})
}

// ServerError responds with HTTP 500 and an error message.
func ServerError(c *gin.Context, msg string) {
	c.JSON(http.StatusInternalServerError, APIResponse{
		Code:    500,
		Message: msg,
	})
}
