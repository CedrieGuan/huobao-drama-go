APP_NAME := huobao-drama-go
BUILD_DIR := bin
MAIN_PKG := ./cmd/server

.PHONY: build run dev test fmt tidy clean

build:
	mkdir -p $(BUILD_DIR)
	go build -o $(BUILD_DIR)/$(APP_NAME) $(MAIN_PKG)

run:
	go run $(MAIN_PKG)

dev:
	go run $(MAIN_PKG)

test:
	go test ./...

fmt:
	gofmt -w ./cmd ./internal

tidy:
	go mod tidy

clean:
	rm -rf $(BUILD_DIR)
