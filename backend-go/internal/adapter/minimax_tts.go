package adapter

import (
	"encoding/json"
	"fmt"
)

// MiniMaxTTSAdapter implements TTSProviderAdapter for MiniMax text-to-speech.
//
// API: POST /v1/t2a_v2
// Response audio is hex-encoded inside data.audio, with metadata in data.extra_info.
//
// Corresponds to TS: backend/src/services/adapters/minimax-tts.ts
type MiniMaxTTSAdapter struct{}

func (a *MiniMaxTTSAdapter) Provider() string { return "minimax" }

// BuildGenerateRequest constructs the TTS generation request for MiniMax.
//
// Expected params keys:
//   - "text"    (string, required) — text to synthesize
//   - "voice"   (string, required) — voice ID
//   - "model"   (string, optional) — model name, defaults to "speech-2.8-hd"
//   - "speed"   (float64, optional) — speech speed, defaults to 1.0
//   - "emotion" (string, optional) — emotion tag, defaults to "happy"
func (a *MiniMaxTTSAdapter) BuildGenerateRequest(config *AIConfig, params map[string]interface{}) (*ProviderRequest, error) {
	url := JoinProviderURL(config.BaseURL, "/v1", "/t2a_v2")

	text, _ := params["text"].(string)
	voice, _ := params["voice"].(string)

	model, _ := params["model"].(string)
	if model == "" {
		model = "speech-2.8-hd"
	}

	speed := 1.0
	if v, ok := params["speed"].(float64); ok && v > 0 {
		speed = v
	}

	emotion := "happy"
	if v, ok := params["emotion"].(string); ok && v != "" {
		emotion = v
	}

	body := map[string]interface{}{
		"model":  model,
		"text":   text,
		"stream": false,
		"voice_setting": map[string]interface{}{
			"voice_id": voice,
			"speed":    speed,
			"vol":      1,
			"pitch":    0,
			"emotion":  emotion,
		},
		"audio_setting": map[string]interface{}{
			"sample_rate": 32000,
			"bitrate":     128000,
			"format":      "mp3",
			"channel":     1,
		},
		"subtitle_enable": false,
	}

	return &ProviderRequest{
		URL:    url,
		Method: "POST",
		Headers: map[string]string{
			"Authorization": "Bearer " + config.APIKey,
			"Content-Type":  "application/json",
		},
		Body: body,
	}, nil
}

// ParseResponse parses the MiniMax TTS response.
//
// Expected JSON structure:
//
//	{
//	  "base_resp": { "status_code": 0 },
//	  "data": {
//	    "audio": "<hex-encoded-audio>",
//	    "extra_info": {
//	      "audio_length": 5000,
//	      "audio_sample_rate": 32000,
//	      "bitrate": 128000,
//	      "audio_format": "mp3",
//	      "audio_channel": 1
//	    }
//	  }
//	}
func (a *MiniMaxTTSAdapter) ParseResponse(body json.RawMessage) (*TTSResponse, error) {
	var resp struct {
		BaseResp struct {
			StatusCode int    `json:"status_code"`
			StatusMsg  string `json:"status_msg"`
		} `json:"base_resp"`
		Data struct {
			Audio     string `json:"audio"`
			ExtraInfo struct {
				AudioLength     int    `json:"audio_length"`
				AudioSampleRate int    `json:"audio_sample_rate"`
				Bitrate         int    `json:"bitrate"`
				AudioFormat     string `json:"audio_format"`
				AudioChannel    int    `json:"audio_channel"`
			} `json:"extra_info"`
		} `json:"data"`
	}

	if err := json.Unmarshal(body, &resp); err != nil {
		return nil, fmt.Errorf("adapter/minimax-tts: unmarshal response: %w", err)
	}

	if resp.BaseResp.StatusCode != 0 {
		msg := resp.BaseResp.StatusMsg
		if msg == "" {
			msg = "TTS generation failed"
		}
		return nil, fmt.Errorf("adapter/minimax-tts: %s (status_code=%d)", msg, resp.BaseResp.StatusCode)
	}

	if resp.Data.Audio == "" {
		return nil, fmt.Errorf("adapter/minimax-tts: no audio data in response")
	}

	sampleRate := resp.Data.ExtraInfo.AudioSampleRate
	if sampleRate == 0 {
		sampleRate = 32000
	}
	bitrate := resp.Data.ExtraInfo.Bitrate
	if bitrate == 0 {
		bitrate = 128000
	}
	format := resp.Data.ExtraInfo.AudioFormat
	if format == "" {
		format = "mp3"
	}
	channel := resp.Data.ExtraInfo.AudioChannel
	if channel == 0 {
		channel = 1
	}

	return &TTSResponse{
		AudioHex:    resp.Data.Audio,
		AudioLength: resp.Data.ExtraInfo.AudioLength,
		SampleRate:  sampleRate,
		Bitrate:     bitrate,
		Format:      format,
		Channel:     channel,
	}, nil
}

func init() {
	RegisterTTSAdapter("minimax", &MiniMaxTTSAdapter{})
}
