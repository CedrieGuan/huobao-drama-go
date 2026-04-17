// Package database defines GORM v2 models that map exactly to the existing SQLite schema
// used by the TypeScript backend. All timestamps are stored as ISO 8601 strings,
// boolean-like fields (is_default, is_active, is_favorite) are stored as int,
// and JSON payloads are stored as string.
package database

import "time"

// Now returns the current UTC time as an ISO 8601 formatted string,
// e.g. "2024-01-15T10:30:00.000Z".
func Now() string {
	return time.Now().UTC().Format("2006-01-02T15:04:05.000Z")
}

// ---------------------------------------------------------------------------
// 1. Drama
// ---------------------------------------------------------------------------

// Drama represents a drama project.
type Drama struct {
	ID            int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	Title         string  `json:"title" gorm:"column:title;not null"`
	Description   *string `json:"description" gorm:"column:description"`
	Genre         *string `json:"genre" gorm:"column:genre"`
	Style         *string `json:"style" gorm:"column:style;default:realistic"`
	TotalEpisodes *int    `json:"total_episodes" gorm:"column:total_episodes;default:1"`
	TotalDuration *int    `json:"total_duration" gorm:"column:total_duration;default:0"`
	Status        string  `json:"status" gorm:"column:status;not null;default:draft"`
	Thumbnail     *string `json:"thumbnail" gorm:"column:thumbnail"`
	Tags          *string `json:"tags" gorm:"column:tags"`
	Metadata      *string `json:"metadata" gorm:"column:metadata"`
	CreatedAt     string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt     string  `json:"updated_at" gorm:"column:updated_at;not null"`
	DeletedAt     *string `json:"deleted_at" gorm:"column:deleted_at"`
}

func (Drama) TableName() string { return "dramas" }

// ---------------------------------------------------------------------------
// 2. Episode
// ---------------------------------------------------------------------------

// Episode represents an episode within a drama.
type Episode struct {
	ID            int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	DramaID       int     `json:"drama_id" gorm:"column:drama_id;not null"`
	EpisodeNumber int     `json:"episode_number" gorm:"column:episode_number;not null"`
	Title         string  `json:"title" gorm:"column:title;not null"`
	Content       *string `json:"content" gorm:"column:content"`
	ScriptContent *string `json:"script_content" gorm:"column:script_content"`
	Description   *string `json:"description" gorm:"column:description"`
	Duration      *int    `json:"duration" gorm:"column:duration;default:0"`
	Status        *string `json:"status" gorm:"column:status;default:draft"`
	VideoURL      *string `json:"video_url" gorm:"column:video_url"`
	Thumbnail     *string `json:"thumbnail" gorm:"column:thumbnail"`
	ImageConfigID *int    `json:"image_config_id" gorm:"column:image_config_id"`
	VideoConfigID *int    `json:"video_config_id" gorm:"column:video_config_id"`
	AudioConfigID *int    `json:"audio_config_id" gorm:"column:audio_config_id"`
	CreatedAt     string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt     string  `json:"updated_at" gorm:"column:updated_at;not null"`
	DeletedAt     *string `json:"deleted_at" gorm:"column:deleted_at"`
}

func (Episode) TableName() string { return "episodes" }

// ---------------------------------------------------------------------------
// 3. Character
// ---------------------------------------------------------------------------

// Character represents a character in a drama.
type Character struct {
	ID              int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	DramaID         int     `json:"drama_id" gorm:"column:drama_id;not null"`
	Name            string  `json:"name" gorm:"column:name;not null"`
	Role            *string `json:"role" gorm:"column:role"`
	Description     *string `json:"description" gorm:"column:description"`
	Appearance      *string `json:"appearance" gorm:"column:appearance"`
	Personality     *string `json:"personality" gorm:"column:personality"`
	VoiceStyle      *string `json:"voice_style" gorm:"column:voice_style"`
	ImageURL        *string `json:"image_url" gorm:"column:image_url"`
	ReferenceImages *string `json:"reference_images" gorm:"column:reference_images"`
	SeedValue       *string `json:"seed_value" gorm:"column:seed_value"`
	SortOrder       *int    `json:"sort_order" gorm:"column:sort_order"`
	LocalPath       *string `json:"local_path" gorm:"column:local_path"`
	VoiceSampleURL  *string `json:"voice_sample_url" gorm:"column:voice_sample_url"`
	VoiceProvider   *string `json:"voice_provider" gorm:"column:voice_provider"`
	CreatedAt       string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt       string  `json:"updated_at" gorm:"column:updated_at;not null"`
	DeletedAt       *string `json:"deleted_at" gorm:"column:deleted_at"`
}

func (Character) TableName() string { return "characters" }

// ---------------------------------------------------------------------------
// 4. Scene
// ---------------------------------------------------------------------------

// Scene represents a scene within a drama.
type Scene struct {
	ID              int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	DramaID         int     `json:"drama_id" gorm:"column:drama_id;not null"`
	EpisodeID       *int    `json:"episode_id" gorm:"column:episode_id"`
	Location        string  `json:"location" gorm:"column:location;not null"`
	Time            string  `json:"time" gorm:"column:time;not null"`
	Prompt          string  `json:"prompt" gorm:"column:prompt;not null"`
	StoryboardCount *int    `json:"storyboard_count" gorm:"column:storyboard_count;default:1"`
	ImageURL        *string `json:"image_url" gorm:"column:image_url"`
	Status          *string `json:"status" gorm:"column:status;default:pending"`
	LocalPath       *string `json:"local_path" gorm:"column:local_path"`
	CreatedAt       string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt       string  `json:"updated_at" gorm:"column:updated_at;not null"`
	DeletedAt       *string `json:"deleted_at" gorm:"column:deleted_at"`
}

func (Scene) TableName() string { return "scenes" }

// ---------------------------------------------------------------------------
// 5. Storyboard
// ---------------------------------------------------------------------------

// Storyboard represents a single storyboard frame within a scene.
type Storyboard struct {
	ID               int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	EpisodeID        int     `json:"episode_id" gorm:"column:episode_id;not null"`
	SceneID          *int    `json:"scene_id" gorm:"column:scene_id"`
	StoryboardNumber int     `json:"storyboard_number" gorm:"column:storyboard_number;not null"`
	Title            *string `json:"title" gorm:"column:title"`
	Location         *string `json:"location" gorm:"column:location"`
	Time             *string `json:"time" gorm:"column:time"`
	ShotType         *string `json:"shot_type" gorm:"column:shot_type"`
	Angle            *string `json:"angle" gorm:"column:angle"`
	Movement         *string `json:"movement" gorm:"column:movement"`
	Action           *string `json:"action" gorm:"column:action"`
	Result           *string `json:"result" gorm:"column:result"`
	Atmosphere       *string `json:"atmosphere" gorm:"column:atmosphere"`
	ImagePrompt      *string `json:"image_prompt" gorm:"column:image_prompt"`
	VideoPrompt      *string `json:"video_prompt" gorm:"column:video_prompt"`
	BGMPrompt        *string `json:"bgm_prompt" gorm:"column:bgm_prompt"`
	SoundEffect      *string `json:"sound_effect" gorm:"column:sound_effect"`
	Dialogue         *string `json:"dialogue" gorm:"column:dialogue"`
	Description      *string `json:"description" gorm:"column:description"`
	Duration         *int    `json:"duration" gorm:"column:duration;default:0"`
	ComposedImage    *string `json:"composed_image" gorm:"column:composed_image"`
	FirstFrameImage  *string `json:"first_frame_image" gorm:"column:first_frame_image"`
	LastFrameImage   *string `json:"last_frame_image" gorm:"column:last_frame_image"`
	ReferenceImages  *string `json:"reference_images" gorm:"column:reference_images"`
	VideoURL         *string `json:"video_url" gorm:"column:video_url"`
	TTSAudioURL      *string `json:"tts_audio_url" gorm:"column:tts_audio_url"`
	SubtitleURL      *string `json:"subtitle_url" gorm:"column:subtitle_url"`
	ComposedVideoURL *string `json:"composed_video_url" gorm:"column:composed_video_url"`
	Status           *string `json:"status" gorm:"column:status;default:pending"`
	CreatedAt        string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt        string  `json:"updated_at" gorm:"column:updated_at;not null"`
	DeletedAt        *string `json:"deleted_at" gorm:"column:deleted_at"`
}

func (Storyboard) TableName() string { return "storyboards" }

// ---------------------------------------------------------------------------
// 6. EpisodeCharacter
// ---------------------------------------------------------------------------

// EpisodeCharacter is a junction table linking episodes to characters.
type EpisodeCharacter struct {
	ID          int    `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	EpisodeID   int    `json:"episode_id" gorm:"column:episode_id;not null"`
	CharacterID int    `json:"character_id" gorm:"column:character_id;not null"`
	CreatedAt   string `json:"created_at" gorm:"column:created_at;not null"`
}

func (EpisodeCharacter) TableName() string { return "episode_characters" }

// ---------------------------------------------------------------------------
// 7. EpisodeScene
// ---------------------------------------------------------------------------

// EpisodeScene is a junction table linking episodes to scenes.
type EpisodeScene struct {
	ID        int    `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	EpisodeID int    `json:"episode_id" gorm:"column:episode_id;not null"`
	SceneID   int    `json:"scene_id" gorm:"column:scene_id;not null"`
	CreatedAt string `json:"created_at" gorm:"column:created_at;not null"`
}

func (EpisodeScene) TableName() string { return "episode_scenes" }

// ---------------------------------------------------------------------------
// 8. StoryboardCharacter
// ---------------------------------------------------------------------------

// StoryboardCharacter is a junction table with a composite primary key linking
// storyboards to characters.
type StoryboardCharacter struct {
	StoryboardID int `json:"storyboard_id" gorm:"column:storyboard_id;primaryKey"`
	CharacterID  int `json:"character_id" gorm:"column:character_id;primaryKey"`
}

func (StoryboardCharacter) TableName() string { return "storyboard_characters" }

// ---------------------------------------------------------------------------
// 9. AIServiceConfig
// ---------------------------------------------------------------------------

// AIServiceConfig stores configuration for an AI service provider instance.
// Note: this table has NO deleted_at column.
type AIServiceConfig struct {
	ID            int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	ServiceType   string  `json:"service_type" gorm:"column:service_type;not null"`
	Provider      *string `json:"provider" gorm:"column:provider"`
	Name          string  `json:"name" gorm:"column:name;not null"`
	BaseURL       string  `json:"base_url" gorm:"column:base_url;not null"`
	APIKey        string  `json:"api_key" gorm:"column:api_key;not null"`
	Model         *string `json:"model" gorm:"column:model"`
	Endpoint      *string `json:"endpoint" gorm:"column:endpoint"`
	QueryEndpoint *string `json:"query_endpoint" gorm:"column:query_endpoint"`
	Priority      *int    `json:"priority" gorm:"column:priority;default:0"`
	IsDefault     int     `json:"is_default" gorm:"column:is_default;default:0"`
	IsActive      int     `json:"is_active" gorm:"column:is_active;default:1"`
	Settings      *string `json:"settings" gorm:"column:settings"`
	CreatedAt     string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt     string  `json:"updated_at" gorm:"column:updated_at;not null"`
}

func (AIServiceConfig) TableName() string { return "ai_service_configs" }

// ---------------------------------------------------------------------------
// 10. AIServiceProvider
// ---------------------------------------------------------------------------

// AIServiceProvider stores preset AI provider definitions.
type AIServiceProvider struct {
	ID           int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	Name         string  `json:"name" gorm:"column:name;not null"`
	DisplayName  *string `json:"display_name" gorm:"column:display_name"`
	ServiceType  string  `json:"service_type" gorm:"column:service_type;not null"`
	Provider     string  `json:"provider" gorm:"column:provider;not null"`
	DefaultURL   *string `json:"default_url" gorm:"column:default_url"`
	PresetModels *string `json:"preset_models" gorm:"column:preset_models"`
	Description  *string `json:"description" gorm:"column:description"`
	IsActive     int     `json:"is_active" gorm:"column:is_active;default:1"`
	CreatedAt    string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt    string  `json:"updated_at" gorm:"column:updated_at;not null"`
}

func (AIServiceProvider) TableName() string { return "ai_service_providers" }

// ---------------------------------------------------------------------------
// 11. AIVoice
// ---------------------------------------------------------------------------

// AIVoice stores available AI voice definitions.
type AIVoice struct {
	ID          int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	VoiceID     string  `json:"voice_id" gorm:"column:voice_id;not null;unique"`
	VoiceName   string  `json:"voice_name" gorm:"column:voice_name;not null"`
	Description *string `json:"description" gorm:"column:description"`
	Language    *string `json:"language" gorm:"column:language"`
	Provider    string  `json:"provider" gorm:"column:provider;not null"`
	CreatedAt   string  `json:"created_at" gorm:"column:created_at;not null"`
}

func (AIVoice) TableName() string { return "ai_voices" }

// ---------------------------------------------------------------------------
// 12. AgentConfig
// ---------------------------------------------------------------------------

// AgentConfig stores configuration for AI agents (script_rewriter, extractor, etc.).
type AgentConfig struct {
	ID            int      `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	AgentType     string   `json:"agent_type" gorm:"column:agent_type;not null"`
	Name          string   `json:"name" gorm:"column:name;not null"`
	Description   *string  `json:"description" gorm:"column:description"`
	Model         *string  `json:"model" gorm:"column:model"`
	SystemPrompt  *string  `json:"system_prompt" gorm:"column:system_prompt"`
	Temperature   *float64 `json:"temperature" gorm:"column:temperature"`
	MaxTokens     *int     `json:"max_tokens" gorm:"column:max_tokens"`
	MaxIterations *int     `json:"max_iterations" gorm:"column:max_iterations"`
	IsActive      int      `json:"is_active" gorm:"column:is_active;default:1"`
	CreatedAt     string   `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt     string   `json:"updated_at" gorm:"column:updated_at;not null"`
	DeletedAt     *string  `json:"deleted_at" gorm:"column:deleted_at"`
}

func (AgentConfig) TableName() string { return "agent_configs" }

// ---------------------------------------------------------------------------
// 13. ImageGeneration
// ---------------------------------------------------------------------------

// ImageGeneration tracks an image generation task and its result.
type ImageGeneration struct {
	ID              int      `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	StoryboardID    *int     `json:"storyboard_id" gorm:"column:storyboard_id"`
	DramaID         *int     `json:"drama_id" gorm:"column:drama_id"`
	SceneID         *int     `json:"scene_id" gorm:"column:scene_id"`
	CharacterID     *int     `json:"character_id" gorm:"column:character_id"`
	PropID          *int     `json:"prop_id" gorm:"column:prop_id"`
	ImageType       *string  `json:"image_type" gorm:"column:image_type"`
	FrameType       *string  `json:"frame_type" gorm:"column:frame_type"`
	Provider        *string  `json:"provider" gorm:"column:provider"`
	Prompt          *string  `json:"prompt" gorm:"column:prompt"`
	NegativePrompt  *string  `json:"negative_prompt" gorm:"column:negative_prompt"`
	Model           *string  `json:"model" gorm:"column:model"`
	Size            *string  `json:"size" gorm:"column:size"`
	Quality         *string  `json:"quality" gorm:"column:quality"`
	Style           *string  `json:"style" gorm:"column:style"`
	Steps           *int     `json:"steps" gorm:"column:steps"`
	CFGScale        *float64 `json:"cfg_scale" gorm:"column:cfg_scale"`
	Seed            *int     `json:"seed" gorm:"column:seed"`
	ImageURL        *string  `json:"image_url" gorm:"column:image_url"`
	MinioURL        *string  `json:"minio_url" gorm:"column:minio_url"`
	LocalPath       *string  `json:"local_path" gorm:"column:local_path"`
	Status          *string  `json:"status" gorm:"column:status;default:pending"`
	TaskID          *string  `json:"task_id" gorm:"column:task_id"`
	ErrorMsg        *string  `json:"error_msg" gorm:"column:error_msg"`
	Width           *int     `json:"width" gorm:"column:width"`
	Height          *int     `json:"height" gorm:"column:height"`
	ReferenceImages *string  `json:"reference_images" gorm:"column:reference_images"`
	CreatedAt       string   `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt       string   `json:"updated_at" gorm:"column:updated_at;not null"`
	CompletedAt     *string  `json:"completed_at" gorm:"column:completed_at"`
}

func (ImageGeneration) TableName() string { return "image_generations" }

// ---------------------------------------------------------------------------
// 14. VideoGeneration
// ---------------------------------------------------------------------------

// VideoGeneration tracks a video generation task and its result.
type VideoGeneration struct {
	ID                 int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	StoryboardID       *int    `json:"storyboard_id" gorm:"column:storyboard_id"`
	DramaID            *int    `json:"drama_id" gorm:"column:drama_id"`
	Provider           *string `json:"provider" gorm:"column:provider"`
	Prompt             *string `json:"prompt" gorm:"column:prompt"`
	Model              *string `json:"model" gorm:"column:model"`
	ImageGenID         *int    `json:"image_gen_id" gorm:"column:image_gen_id"`
	ReferenceMode      *string `json:"reference_mode" gorm:"column:reference_mode"`
	ImageURL           *string `json:"image_url" gorm:"column:image_url"`
	FirstFrameURL      *string `json:"first_frame_url" gorm:"column:first_frame_url"`
	LastFrameURL       *string `json:"last_frame_url" gorm:"column:last_frame_url"`
	ReferenceImageURLs *string `json:"reference_image_urls" gorm:"column:reference_image_urls"`
	Duration           *int    `json:"duration" gorm:"column:duration"`
	FPS                *int    `json:"fps" gorm:"column:fps"`
	Resolution         *string `json:"resolution" gorm:"column:resolution"`
	AspectRatio        *string `json:"aspect_ratio" gorm:"column:aspect_ratio"`
	Style              *string `json:"style" gorm:"column:style"`
	MotionLevel        *int    `json:"motion_level" gorm:"column:motion_level"`
	CameraMotion       *string `json:"camera_motion" gorm:"column:camera_motion"`
	Seed               *int    `json:"seed" gorm:"column:seed"`
	VideoURL           *string `json:"video_url" gorm:"column:video_url"`
	MinioURL           *string `json:"minio_url" gorm:"column:minio_url"`
	LocalPath          *string `json:"local_path" gorm:"column:local_path"`
	Status             *string `json:"status" gorm:"column:status;default:pending"`
	TaskID             *string `json:"task_id" gorm:"column:task_id"`
	ErrorMsg           *string `json:"error_msg" gorm:"column:error_msg"`
	Width              *int    `json:"width" gorm:"column:width"`
	Height             *int    `json:"height" gorm:"column:height"`
	CreatedAt          string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt          string  `json:"updated_at" gorm:"column:updated_at;not null"`
	CompletedAt        *string `json:"completed_at" gorm:"column:completed_at"`
	DeletedAt          *string `json:"deleted_at" gorm:"column:deleted_at"`
}

func (VideoGeneration) TableName() string { return "video_generations" }

// ---------------------------------------------------------------------------
// 15. VideoMerge
// ---------------------------------------------------------------------------

// VideoMerge tracks a video merge task that combines multiple scene videos.
type VideoMerge struct {
	ID          int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	EpisodeID   *int    `json:"episode_id" gorm:"column:episode_id"`
	DramaID     *int    `json:"drama_id" gorm:"column:drama_id"`
	Title       *string `json:"title" gorm:"column:title"`
	Provider    string  `json:"provider" gorm:"column:provider;not null"`
	Model       string  `json:"model" gorm:"column:model;not null"`
	Status      *string `json:"status" gorm:"column:status;default:pending"`
	Scenes      *string `json:"scenes" gorm:"column:scenes"`
	MergedURL   *string `json:"merged_url" gorm:"column:merged_url"`
	Duration    *int    `json:"duration" gorm:"column:duration"`
	TaskID      *string `json:"task_id" gorm:"column:task_id"`
	ErrorMsg    *string `json:"error_msg" gorm:"column:error_msg"`
	CreatedAt   string  `json:"created_at" gorm:"column:created_at;not null"`
	CompletedAt *string `json:"completed_at" gorm:"column:completed_at"`
	DeletedAt   *string `json:"deleted_at" gorm:"column:deleted_at"`
}

func (VideoMerge) TableName() string { return "video_merges" }

// ---------------------------------------------------------------------------
// 16. Prop
// ---------------------------------------------------------------------------

// Prop represents a prop used in a drama production.
type Prop struct {
	ID              int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	DramaID         int     `json:"drama_id" gorm:"column:drama_id;not null"`
	Name            string  `json:"name" gorm:"column:name;not null"`
	Type            *string `json:"type" gorm:"column:type"`
	Description     *string `json:"description" gorm:"column:description"`
	Prompt          *string `json:"prompt" gorm:"column:prompt"`
	ImageURL        *string `json:"image_url" gorm:"column:image_url"`
	ReferenceImages *string `json:"reference_images" gorm:"column:reference_images"`
	LocalPath       *string `json:"local_path" gorm:"column:local_path"`
	CreatedAt       string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt       string  `json:"updated_at" gorm:"column:updated_at;not null"`
	DeletedAt       *string `json:"deleted_at" gorm:"column:deleted_at"`
}

func (Prop) TableName() string { return "props" }

// ---------------------------------------------------------------------------
// 17. Asset
// ---------------------------------------------------------------------------

// Asset represents a generated or uploaded media asset.
type Asset struct {
	ID            int     `json:"id" gorm:"column:id;primaryKey;autoIncrement"`
	DramaID       *int    `json:"drama_id" gorm:"column:drama_id"`
	EpisodeID     *int    `json:"episode_id" gorm:"column:episode_id"`
	StoryboardID  *int    `json:"storyboard_id" gorm:"column:storyboard_id"`
	StoryboardNum *int    `json:"storyboard_num" gorm:"column:storyboard_num"`
	Name          *string `json:"name" gorm:"column:name"`
	Description   *string `json:"description" gorm:"column:description"`
	Type          *string `json:"type" gorm:"column:type"`
	Category      *string `json:"category" gorm:"column:category"`
	URL           *string `json:"url" gorm:"column:url"`
	ThumbnailURL  *string `json:"thumbnail_url" gorm:"column:thumbnail_url"`
	LocalPath     *string `json:"local_path" gorm:"column:local_path"`
	FileSize      *int    `json:"file_size" gorm:"column:file_size"`
	MimeType      *string `json:"mime_type" gorm:"column:mime_type"`
	Width         *int    `json:"width" gorm:"column:width"`
	Height        *int    `json:"height" gorm:"column:height"`
	Duration      *int    `json:"duration" gorm:"column:duration"`
	Format        *string `json:"format" gorm:"column:format"`
	ImageGenID    *int    `json:"image_gen_id" gorm:"column:image_gen_id"`
	VideoGenID    *int    `json:"video_gen_id" gorm:"column:video_gen_id"`
	IsFavorite    int     `json:"is_favorite" gorm:"column:is_favorite;default:0"`
	ViewCount     *int    `json:"view_count" gorm:"column:view_count;default:0"`
	CreatedAt     string  `json:"created_at" gorm:"column:created_at;not null"`
	UpdatedAt     string  `json:"updated_at" gorm:"column:updated_at;not null"`
	DeletedAt     *string `json:"deleted_at" gorm:"column:deleted_at"`
}

func (Asset) TableName() string { return "assets" }
