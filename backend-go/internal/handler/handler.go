package handler

import (
	"gorm.io/gorm"
)

// Handler is the base handler struct that holds shared dependencies.
// All route handler methods are attached to this struct via receiver functions
// in their respective files (drama.go, episode.go, etc.).
type Handler struct {
	DB         *gorm.DB
	StoragePath string // Absolute path to the data/storage directory
}

// New creates a new Handler instance with the given GORM database connection
// and optional storage path for file uploads.
func New(db *gorm.DB, storagePath ...string) *Handler {
	h := &Handler{DB: db}
	if len(storagePath) > 0 {
		h.StoragePath = storagePath[0]
	}
	return h
}
