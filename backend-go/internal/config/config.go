package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Config holds all application configuration.
type Config struct {
	App      AppConfig      `mapstructure:"app"`
	Server   ServerConfig   `mapstructure:"server"`
	Database DatabaseConfig `mapstructure:"database"`
	Storage  StorageConfig  `mapstructure:"storage"`
	AI       AIConfig       `mapstructure:"ai"`
}

// AppConfig holds application-level settings.
type AppConfig struct {
	Name    string `mapstructure:"name"`
	Version string `mapstructure:"version"`
	Env     string `mapstructure:"env"`
	Debug   bool   `mapstructure:"debug"`
}

// ServerConfig holds HTTP server settings.
type ServerConfig struct {
	Host         string        `mapstructure:"host"`
	Port         int           `mapstructure:"port"`
	CORSOrigins  []string      `mapstructure:"cors_origins"`
	ReadTimeout  time.Duration `mapstructure:"read_timeout"`
	WriteTimeout time.Duration `mapstructure:"write_timeout"`
}

// Address returns the host:port listen address string.
func (c ServerConfig) Address() string {
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

// DatabaseConfig holds database connection settings.
type DatabaseConfig struct {
	Driver  string `mapstructure:"driver"`
	DSN     string `mapstructure:"dsn"`
	MaxIdle int    `mapstructure:"max_idle"`
	MaxOpen int    `mapstructure:"max_open"`
}

// StorageConfig holds file storage settings.
type StorageConfig struct {
	Type      string `mapstructure:"type"`
	Path      string `mapstructure:"path"`
	BaseURL   string `mapstructure:"base_url"`
	StaticDir string `mapstructure:"static_dir"`
}

// AIConfig holds default AI provider settings.
type AIConfig struct {
	DefaultTextProvider  string `mapstructure:"default_text_provider"`
	DefaultImageProvider string `mapstructure:"default_image_provider"`
	DefaultVideoProvider string `mapstructure:"default_video_provider"`
}

// Load reads configuration from config.yaml and environment variables.
// Environment variables use the HUOBAO_ prefix (e.g. HUOBAO_SERVER_PORT).
func Load() (*Config, error) {
	v := viper.New()
	v.SetConfigName("config")
	v.SetConfigType("yaml")
	v.AddConfigPath("../configs")
	v.AddConfigPath("../../configs")
	v.AddConfigPath("./configs")
	v.AddConfigPath("/etc/huobao")

	v.SetEnvPrefix("HUOBAO")
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	setDefaults(v)

	if err := v.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, fmt.Errorf("read config: %w", err)
		}
	}

	cfg := &Config{}
	if err := v.Unmarshal(cfg); err != nil {
		return nil, fmt.Errorf("unmarshal config: %w", err)
	}

	// Override from individual env vars
	if v.IsSet("PORT") {
		cfg.Server.Port = v.GetInt("PORT")
	}
	if v.IsSet("DB_PATH") {
		cfg.Database.DSN = v.GetString("DB_PATH")
	}
	if v.IsSet("STORAGE_PATH") {
		cfg.Storage.Path = v.GetString("STORAGE_PATH")
	}

	return cfg, nil
}

func setDefaults(v *viper.Viper) {
	// App defaults
	v.SetDefault("app.name", "huobao-drama-go")
	v.SetDefault("app.version", "1.0.0")
	v.SetDefault("app.env", "development")
	v.SetDefault("app.debug", true)

	// Server defaults
	v.SetDefault("server.host", "0.0.0.0")
	v.SetDefault("server.port", 5680)
	v.SetDefault("server.cors_origins", []string{
		"http://localhost:3013",
		"http://localhost:5679",
	})
	v.SetDefault("server.read_timeout", 600)
	v.SetDefault("server.write_timeout", 600)

	// Database defaults
	v.SetDefault("database.driver", "sqlite")
	v.SetDefault("database.dsn", "../data/huobao_drama.db")
	v.SetDefault("database.max_idle", 10)
	v.SetDefault("database.max_open", 100)

	// Storage defaults
	v.SetDefault("storage.type", "local")
	v.SetDefault("storage.path", "../data/storage")
	v.SetDefault("storage.base_url", "http://localhost:5680/static")

	// AI defaults
	v.SetDefault("ai.default_text_provider", "openai")
	v.SetDefault("ai.default_image_provider", "openai")
	v.SetDefault("ai.default_video_provider", "doubao")
}
