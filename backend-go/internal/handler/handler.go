package handler

import (
	"gorm.io/gorm"
)

// Handler is the base handler struct that holds shared dependencies.
// All route handler methods are attached to this struct via receiver functions
// in their respective files (drama.go, episode.go, etc.).
type Handler struct {
	DB *gorm.DB
}

// New creates a new Handler instance with the given GORM database connection.
// This is the single point of dependency injection for all handlers.
func New(db *gorm.DB) *Handler {
	return &Handler{DB: db}
}
