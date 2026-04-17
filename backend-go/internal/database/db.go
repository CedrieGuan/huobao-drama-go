package database

import (
	"fmt"
	"log"
	"os"
	"path/filepath"

	"github.com/CedrieGuan/huobao-drama-go/backend-go/internal/config"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

// Init initializes the database connection based on the provided configuration.
// It opens a connection, applies SQLite-specific pragmas (WAL mode, busy timeout),
// configures the connection pool, and runs auto-migration for all models.
func Init(cfg config.DatabaseConfig) (*gorm.DB, error) {
	var dialector gorm.Dialector

	switch cfg.Driver {
	case "sqlite", "":
		// Ensure parent directory exists for the SQLite database file.
		if dir := filepath.Dir(cfg.DSN); dir != "" && dir != "." {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				return nil, fmt.Errorf("failed to create database directory %s: %w", dir, err)
			}
		}
		dialector = sqlite.Open(cfg.DSN)
	default:
		return nil, fmt.Errorf("unsupported database driver: %s", cfg.Driver)
	}

	gormConfig := &gorm.Config{
		Logger: logger.Default.LogMode(logger.Warn),
	}

	db, err := gorm.Open(dialector, gormConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to database (%s): %w", cfg.Driver, err)
	}

	// SQLite-specific setup: enable WAL mode and set busy timeout
	// This matches the existing TypeScript backend behavior.
	if cfg.Driver == "sqlite" || cfg.Driver == "" {
		if result := db.Exec("PRAGMA journal_mode = WAL"); result.Error != nil {
			return nil, fmt.Errorf("failed to set WAL mode: %w", result.Error)
		}
		if result := db.Exec("PRAGMA busy_timeout = 30000"); result.Error != nil {
			return nil, fmt.Errorf("failed to set busy_timeout: %w", result.Error)
		}
		log.Println("[database] SQLite WAL mode enabled, busy_timeout = 30000ms")
	}

	// Configure connection pool settings.
	// These are primarily relevant for PostgreSQL but are harmless for SQLite.
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("failed to get underlying sql.DB: %w", err)
	}
	sqlDB.SetMaxIdleConns(10)
	sqlDB.SetMaxOpenConns(100)

	// Auto-migrate all 17 models.
	if err := autoMigrate(db); err != nil {
		return nil, fmt.Errorf("failed to auto-migrate: %w", err)
	}

	log.Printf("[database] connected to %s at %s", cfg.Driver, cfg.DSN)
	return db, nil
}

// Close gracefully closes the database connection by retrieving the underlying
// sql.DB and calling Close on it.
func Close(db *gorm.DB) {
	if db == nil {
		return
	}

	sqlDB, err := db.DB()
	if err != nil {
		log.Printf("[database] error getting underlying sql.DB for close: %v", err)
		return
	}

	if err := sqlDB.Close(); err != nil {
		log.Printf("[database] error closing database connection: %v", err)
		return
	}

	log.Println("[database] connection closed")
}

// autoMigrate runs GORM auto-migration for all 17 models.
// The models are defined in models.go within the same package.
func autoMigrate(db *gorm.DB) error {
	return db.AutoMigrate(
		// Core drama models (5)
		&Drama{},
		&Episode{},
		&Character{},
		&Scene{},
		&Storyboard{},

		// Junction/association models (3)
		&EpisodeCharacter{},
		&EpisodeScene{},
		&StoryboardCharacter{},

		// AI service models (3)
		&AIServiceConfig{},
		&AIServiceProvider{},
		&AIVoice{},

		// Agent config (1)
		&AgentConfig{},

		// Generation models (2)
		&ImageGeneration{},
		&VideoGeneration{},

		// Video merge (1)
		&VideoMerge{},

		// Props and assets (2)
		&Prop{},
		&Asset{},
	)
}
