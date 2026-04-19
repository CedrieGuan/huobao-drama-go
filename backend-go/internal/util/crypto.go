package util

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"io"
	"os"
	"sync"
)

var (
	encryptionKey     []byte
	encryptionKeyOnce sync.Once
)

// GetEncryptionKey returns the AES-256 encryption key derived from ENCRYPTION_KEY
// environment variable. Returns nil if not set (plaintext mode).
func GetEncryptionKey() []byte {
	encryptionKeyOnce.Do(func() {
		key := os.Getenv("ENCRYPTION_KEY")
		if key == "" {
			return
		}
		decoded, err := base64.StdEncoding.DecodeString(key)
		if err != nil || len(decoded) != 32 {
			// If not valid base64 or not 32 bytes, use first 32 bytes of the string
			if len(key) >= 32 {
				encryptionKey = []byte(key[:32])
			}
			return
		}
		encryptionKey = decoded
	})
	return encryptionKey
}

// Encrypt encrypts plaintext using AES-GCM and returns a base64-encoded string.
// Returns the plaintext unchanged if no encryption key is configured.
func Encrypt(plaintext string) (string, error) {
	key := GetEncryptionKey()
	if key == nil {
		return plaintext, nil
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("crypto: create cipher: %w", err)
	}

	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("crypto: create GCM: %w", err)
	}

	nonce := make([]byte, aesGCM.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("crypto: generate nonce: %w", err)
	}

	sealed := aesGCM.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(sealed), nil
}

// Decrypt decrypts a base64-encoded AES-GCM ciphertext.
// Returns the ciphertext unchanged if no encryption key is configured.
// Returns the input unchanged if decryption fails (assumes plaintext).
func Decrypt(ciphertext string) string {
	key := GetEncryptionKey()
	if key == nil {
		return ciphertext
	}

	data, err := base64.StdEncoding.DecodeString(ciphertext)
	if err != nil {
		return ciphertext // not base64, assume plaintext
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return ciphertext
	}

	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return ciphertext
	}

	nonceSize := aesGCM.NonceSize()
	if len(data) < nonceSize {
		return ciphertext // too short, assume plaintext
	}

	nonce, sealed := data[:nonceSize], data[nonceSize:]
	plaintext, err := aesGCM.Open(nil, nonce, sealed, nil)
	if err != nil {
		return ciphertext // decryption failed, assume plaintext
	}

	return string(plaintext)
}
