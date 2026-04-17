# backend-go

Go backend scaffold for Huobao Drama.

## Structure

```text
backend-go/
├── cmd/server/main.go
├── internal/config/config.go
├── internal/handler/health.go
├── internal/server/router.go
├── go.mod
└── Makefile
```

## Commands

```bash
make tidy
make run
make build
make test
```

## Current Scope

- Gin HTTP server
- Viper-based config loading
- Health check endpoint: `GET /api/v1/health`
- Static route placeholder: `/static/*filepath`

This is only the initial scaffold. Database, migrations, models, handlers, and services are still pending.
