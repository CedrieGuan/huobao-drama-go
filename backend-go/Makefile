APP_NAME := huobao-drama-go
BUILD_DIR := bin
MAIN_PKG := ./cmd/server

.PHONY: build run dev test fmt tidy clean lint tools docker

## build: Compile the binary into bin/
build:
	mkdir -p $(BUILD_DIR)
	go build -o $(BUILD_DIR)/$(APP_NAME) $(MAIN_PKG)

## run: Build and run the server
run: build
	./$(BUILD_DIR)/$(APP_NAME)

## dev: Run with go run (auto-reload with air if installed)
dev:
	@if command -v air > /dev/null 2>&1; then \
		air; \
	else \
		go run $(MAIN_PKG); \
	fi

## test: Run all tests
test:
	go test -v -race ./...

## fmt: Format Go source files
fmt:
	gofmt -w ./cmd ./internal

## tidy: Tidy Go module dependencies
tidy:
	go mod tidy

## clean: Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)

## lint: Run golangci-lint
lint:
	@if command -v golangci-lint > /dev/null 2>&1; then \
		golangci-lint run ./...; \
	else \
		echo "golangci-lint not installed. Run: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; \
	fi

## tools: Install development tools
tools:
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
	go install github.com/cosmtrek/air@latest

## docker: Build Docker image
docker:
	docker build -t $(APP_NAME) ..

## vet: Run go vet
vet:
	go vet ./...

## check: Run all static checks (fmt, vet, lint)
check: fmt vet lint

## help: Show this help
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
