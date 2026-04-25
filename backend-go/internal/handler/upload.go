package handler

import (
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/util"
	"github.com/gin-gonic/gin"
)

// ---------------------------------------------------------------------------
// POST /api/v1/upload/image — Upload an image file
// ---------------------------------------------------------------------------

// UploadImage handles single file upload and saves it to the storage directory.
func (h *Handler) UploadImage(c *gin.Context) {
	file, header, err := c.Request.FormFile("file")
	if err != nil {
		util.BadRequest(c, "file is required")
		return
	}
	defer file.Close()

	url, path, err := h.saveUploadedFile(file, header, "uploads")
	if err != nil {
		util.ServerError(c, err.Error())
		return
	}

	util.Success(c, gin.H{
		"url":  url,
		"path": path,
	})
}

// saveUploadedFile persists an uploaded file to the storage directory.
// It creates a subdirectory structure: <storagePath>/<subdir>/<unique-filename>.
// Returns the URL path and the relative file path.
func (h *Handler) saveUploadedFile(file multipart.File, header *multipart.FileHeader, subdir string) (string, string, error) {
	if h.StoragePath == "" {
		return "", "", fmt.Errorf("storage path not configured")
	}

	// Ensure the target directory exists.
	targetDir := filepath.Join(h.StoragePath, subdir)
	if err := os.MkdirAll(targetDir, 0o755); err != nil {
		return "", "", fmt.Errorf("create upload dir: %w", err)
	}

	// Generate a unique filename to avoid collisions.
	ext := strings.ToLower(filepath.Ext(header.Filename))
	if ext == "" {
		ext = ".bin"
	}
	filename := fmt.Sprintf("%d%s", util.TimestampMillis(), ext)

	fullPath := filepath.Join(targetDir, filename)
	dst, err := os.Create(fullPath)
	if err != nil {
		return "", "", fmt.Errorf("create file: %w", err)
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		return "", "", fmt.Errorf("write file: %w", err)
	}

	// Build URL path relative to storage root.
	relPath := filepath.Join(subdir, filename)
	urlPath := "/" + strings.ReplaceAll(relPath, string(filepath.Separator), "/")

	return urlPath, relPath, nil
}
