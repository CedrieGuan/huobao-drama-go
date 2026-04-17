package handler

import "errors"

// Sentinel errors for handler validation.
// These are used by various route handlers to return consistent error messages
// that match the TypeScript backend's error responses.

var (
	// errSceneNotInEpisode is returned when a scene_id is provided that does not
	// belong to the episode's linked scenes (via episode_scenes join table).
	errSceneNotInEpisode = errors.New("scene_id 必须来自当前集已关联场景")

	// errCharacterNotInEpisode is returned when a character_id is provided that
	// does not belong to the episode's linked characters (via episode_characters
	// join table).
	errCharacterNotInEpisode = errors.New("character_ids 必须来自当前集已关联角色")

	// errDramaNotFound is returned when a drama is not found by ID.
	errDramaNotFound = errors.New("剧本不存在")

	// errEpisodeNotFound is returned when an episode is not found by ID.
	errEpisodeNotFound = errors.New("Episode not found")

	// errStoryboardNotFound is returned when a storyboard is not found by ID.
	errStoryboardNotFound = errors.New("镜头不存在")

	// errCharacterNotFound is returned when a character is not found by ID.
	errCharacterNotFound = errors.New("Character not found")

	// errVoiceStyleRequired is returned when trying to generate a voice sample
	// for a character that has no voice_style assigned.
	errVoiceStyleRequired = errors.New("请先分配音色")
)
