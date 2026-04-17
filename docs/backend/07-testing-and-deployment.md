# Phase 7 — 集成测试 + Docker + 上线

> 对应总览文档 Phase 7  
> 目标：验证 Go 后端与前端完全兼容，完成 Docker 化，上线替换
>
> 修订说明（2026-04）：
> 数据库主方案已调整为 PostgreSQL + GORM + 版本化 migration。
> 下文若仍出现 SQLite / `go-sqlite3` / `CGO_ENABLED=1` 示例，均视为历史草案；测试、部署、切换流程以本文新增修订说明为准。

---

## 1. 测试策略

### 1.1 测试分层

```
┌─────────────────────────────────┐
│  E2E 兼容性测试（TS vs Go 响应对比）  │
├─────────────────────────────────┤
│  API 集成测试（HTTP → DB 全链路）     │
├─────────────────────────────────┤
│  Service 单元测试（业务逻辑）         │
├─────────────────────────────────┤
│  Adapter 单元测试（Mock HTTP）       │
├─────────────────────────────────┤
│  Util 单元测试（纯函数）             │
└─────────────────────────────────┘
```

### 1.2 测试目录结构

```
backend-go/
├── internal/
│   ├── adapter/
│   │   └── adapter_test.go        # Adapter 单元测试
│   ├── service/
│   │   └── service_test.go        # Service 单元测试
│   ├── agent/
│   │   └── agent_test.go          # Agent 循环测试
│   └── util/
│       └── util_test.go           # 工具函数测试
├── tests/
│   ├── integration/               # 集成测试（需要真实 DB）
│   │   ├── crud_test.go           # 基础 CRUD 集成测试
│   │   ├── pipeline_test.go       # 生成流水线集成测试
│   │   └── testhelpers.go         # 测试辅助（建表/清理/断言）
│   └── compatibility/             # TS vs Go 兼容性测试
│       ├── compat_test.go         # 响应格式对比
│       └── endpoints.json         # 端点清单
├── Makefile                       # 测试命令
└── go.mod
```

### 1.3 单元测试

#### Adapter 测试

每个 Adapter 需要测试：
- `BuildGenerateRequest` 构建正确的 URL、Headers、Body
- `ParseGenerateResponse` 正确解析同步/异步响应
- `BuildPollRequest` 构建正确的轮询请求
- `ParsePollResponse` 正确解析轮询状态

使用 `httptest.Server` 模拟远端 API：

```go
// internal/adapter/minimax_image_test.go
func TestMiniMaxImageAdapter_SyncResponse(t *testing.T) {
    // 1. 模拟 MiniMax API
    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        assert.Equal(t, "POST", r.Method)
        assert.Contains(t, r.URL.Path, "/v1/image_generation")
        assert.Equal(t, "Bearer test-key", r.Header.Get("Authorization"))

        json.NewEncoder(w).Encode(map[string]interface{}{
            "data": map[string]interface{}{
                "image_url": "https://example.com/image.png",
            },
        })
    }))
    defer server.Close()

    // 2. 构建请求
    adapter := &MiniMaxImageAdapter{}
    config := &AIConfig{
        Provider: "minimax",
        BaseURL:  server.URL,
        APIKey:   "test-key",
        Model:    "test-model",
    }
    record := ImageGenRecord{
        ID:     1,
        Prompt: "a beautiful sunset",
        Size:   "1920x1080",
    }

    req, err := adapter.BuildGenerateRequest(config, record)
    require.NoError(t, err)
    assert.Equal(t, server.URL+"/v1/image_generation", req.URL)

    // 3. 发送请求并解析响应
    resp, err := http.Do(req)
    require.NoError(t, err)
    body, _ := io.ReadAll(resp.Body)
    
    genResp, err := adapter.ParseGenerateResponse(json.RawMessage(body))
    require.NoError(t, err)
    assert.False(t, genResp.IsAsync)
    assert.Equal(t, "https://example.com/image.png", genResp.ImageURL)
}
```

#### URL Builder 测试

```go
func TestJoinProviderURL(t *testing.T) {
    tests := []struct {
        name       string
        baseURL    string
        prefix     string
        path       string
        wantSuffix string
    }{
        {"normal", "https://api.minimax.chat", "/v1", "/image_generation", "/v1/image_generation"},
        {"base_has_prefix", "https://api.minimax.chat/v1", "/v1", "/image_generation", "/v1/image_generation"},
        {"base_trailing_slash", "https://api.minimax.chat/", "/v1", "/image_generation", "/v1/image_generation"},
        {"gemini_key", "https://generativelanguage.googleapis.com", "/v1beta", "/models/gemini:generateContent", "/v1beta/models/gemini:generateContent"},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := JoinProviderURL(tt.baseURL, tt.prefix, tt.path)
            assert.True(t, strings.HasSuffix(got, tt.wantSuffix))
        })
    }
}
```

#### Transform 测试

```go
func TestToSnakeCase(t *testing.T) {
    assert.Equal(t, "storyboard_number", toSnakeCase("storyboardNumber"))
    assert.Equal(t, "composed_video_url", toSnakeCase("composedVideoUrl"))
    assert.Equal(t, "is_active", toSnakeCase("isActive"))
    assert.Equal(t, "id", toSnakeCase("id"))
}
```

### 1.4 集成测试

修订说明（2026-04）：
数据库方案改为 PostgreSQL + GORM 后，集成测试不再建议使用 SQLite 内存库伪装生产环境。
这里应改成“真实 PostgreSQL 测试库 + 运行正式 migration”的链路验证。

推荐做法：

- 本地或 CI 启动临时 PostgreSQL 实例
- 执行 `golang-migrate up`
- 再跑 HTTP → Handler → Service → DB 的完整测试

这样才能尽早暴露：

- PostgreSQL 类型差异
- 索引与默认值问题
- 事务行为差异
- GORM 模型标签与真实表结构不一致的问题

```go
// tests/integration/crud_test.go
func setupTestDB(t *testing.T) *gorm.DB {
    dsn := os.Getenv("TEST_DATABASE_DSN")
    db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
    require.NoError(t, err)

    require.NoError(t, runMigrations(dsn))
    return db
}

func setupTestRouter(db *gorm.DB) *gin.Engine {
    h := handler.New(db)
    return SetupRouter(h)
}

func TestDramaCRUD(t *testing.T) {
    db := setupTestDB(t)
    sqlDB, err := db.DB()
    require.NoError(t, err)
    defer sqlDB.Close()
    r := setupTestRouter(db)

    // Create
    body := `{"title":"测试剧集","description":"描述","genre":"爱情","total_episodes":3}`
    w := httptest.NewRecorder()
    req, _ := http.NewRequest("POST", "/api/v1/dramas", strings.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    r.ServeHTTP(w, req)

    assert.Equal(t, 200, w.Code)
    var resp map[string]interface{}
    json.Unmarshal(w.Body.Bytes(), &resp)
    assert.Equal(t, float64(200), resp["code"])

    data := resp["data"].(map[string]interface{})
    dramaID := data["id"]

    // Get
    w = httptest.NewRecorder()
    req, _ = http.NewRequest("GET", fmt.Sprintf("/api/v1/dramas/%v", dramaID), nil)
    r.ServeHTTP(w, req)
    assert.Equal(t, 200, w.Code)

    // List
    w = httptest.NewRecorder()
    req, _ = http.NewRequest("GET", "/api/v1/dramas", nil)
    r.ServeHTTP(w, req)
    assert.Equal(t, 200, w.Code)

    // Delete (soft)
    w = httptest.NewRecorder()
    req, _ = http.NewRequest("DELETE", fmt.Sprintf("/api/v1/dramas/%v", dramaID), nil)
    r.ServeHTTP(w, req)
    assert.Equal(t, 200, w.Code)
}
```

### 1.5 兼容性测试

对比 TS 版和 Go 版对相同请求的响应格式。这是最关键的测试，确保前端零改动。

#### 端点清单文件

```json
// tests/compatibility/endpoints.json
[
  {"method": "GET",  "path": "/api/v1/health"},
  {"method": "GET",  "path": "/api/v1/dramas"},
  {"method": "GET",  "path": "/api/v1/dramas/stats"},
  {"method": "POST", "path": "/api/v1/dramas", "body": {"title": "测试", "total_episodes": 1}},
  {"method": "GET",  "path": "/api/v1/dramas/1"},
  {"method": "PUT",  "path": "/api/v1/dramas/1", "body": {"title": "更新"}},
  {"method": "DELETE","path": "/api/v1/dramas/1"},
  {"method": "POST", "path": "/api/v1/episodes", "body": {"drama_id": 1, "title": "第1集"}},
  {"method": "GET",  "path": "/api/v1/episodes/1/pipeline-status"},
  {"method": "GET",  "path": "/api/v1/episodes/1/storyboards"},
  {"method": "GET",  "path": "/api/v1/agent-configs"},
  {"method": "GET",  "path": "/api/v1/ai-configs"},
  {"method": "GET",  "path": "/api/v1/ai-providers"},
  {"method": "GET",  "path": "/api/v1/skills"}
]
```

#### 兼容性测试脚本

```go
// tests/compatibility/compat_test.go
// 对同一个 SQLite 数据库文件，分别请求 TS 和 Go 后端，对比响应

const (
    tsBaseURL = "http://localhost:5679"
    goBaseURL = "http://localhost:5680"
)

func TestResponseCompatibility(t *testing.T) {
    endpoints := loadEndpoints(t, "endpoints.json")

    for _, ep := range endpoints {
        t.Run(fmt.Sprintf("%s %s", ep.Method, ep.Path), func(t *testing.T) {
            tsResp := doRequest(t, tsBaseURL, ep)
            goResp := doRequest(t, goBaseURL, ep)

            // 对比响应 code
            assert.Equal(t, tsResp.Code, goResp.Code, "response code mismatch")

            // 对比响应 data 的 key 集合
            tsKeys := getSortedKeys(tsResp.Data)
            goKeys := getSortedKeys(goResp.Data)
            assert.Equal(t, tsKeys, goKeys, "response data keys mismatch")
        })
    }
}
```

### 1.6 兼容性测试补强

只比较 `code` 和 key 集合不足以支撑生产替换，必须继续补齐以下验证：

- **字段类型一致**：字符串、数字、布尔、数组、对象、`null` 语义一致
- **列表排序一致**：默认排序、分页行为、过滤条件返回顺序一致
- **错误体一致**：HTTP status、`code`、`message` 格式一致
- **状态流转一致**：图片、视频、合成、拼接任务的状态集合与转换路径一致
- **静态资源一致**：上传返回路径、`/static/*` 映射、前端 fallback 行为一致
- **真实链路一致**：从创建剧集到最终合成至少跑通一条全链路

建议兼容测试拆成三层：

1. **Schema 对比**：比较字段名、字段类型、可空性
2. **Golden 对比**：关键端点保存 TS 基线响应，Go 逐字段比较
3. **Workflow 冒烟**：真实执行“创建 → 提取 → 分镜 → 生成 → 合成 → 拼接”

### 1.7 测试命令

```makefile
# Makefile

.PHONY: test test-unit test-integration test-compat test-all

# 单元测试（不需要外部依赖）
test-unit:
	go test ./internal/... -v -count=1 -short

# 集成测试（需要 SQLite，使用内存数据库）
test-integration:
	go test ./tests/integration/... -v -count=1

# 兼容性测试（需要 TS 和 Go 后端同时运行）
test-compat:
	go test ./tests/compatibility/... -v -count=1

# 全部测试
test-all: test-unit test-integration

# 带覆盖率
test-coverage:
	go test ./internal/... -coverprofile=coverage.out -covermode=atomic
	go tool cover -html=coverage.out -o coverage.html
```

---

## 2. Docker 构建

### 2.1 多阶段 Dockerfile

Go 版的 Docker 镜像比 TS 版小很多。关键区别：
- Go 编译为单个静态二进制
- 不需要 node_modules
- 运行时只需要 ffmpeg

```dockerfile
# ── Stage 1: Build frontend ──────────────────────────────────
FROM node:20-slim AS frontend-build

WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run generate

# ── Stage 2: Build Go binary ─────────────────────────────────
FROM golang:1.23-bookworm AS backend-build

# go-sqlite3 需要 CGO
ENV CGO_ENABLED=1

WORKDIR /app/backend-go

# 先复制依赖文件，利用 Docker 层缓存
COPY backend-go/go.mod backend-go/go.sum ./
RUN go mod download

# 复制源码并编译
COPY backend-go/ ./
RUN go build -ldflags="-s -w -X main.Version=$(cat VERSION 2>/dev/null || echo dev)" \
    -o /app/server ./cmd/server/

# ── Stage 3: Production image ────────────────────────────────
FROM node:20-slim

# 安装 ffmpeg（运行时需要）+ ca-certificates（HTTPS 请求）
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Go 二进制
COPY --from=backend-build /app/server ./server

# 前端静态输出
COPY --from=frontend-build /app/frontend/.output/public ./frontend/dist

# Skills 文件
COPY skills/ ./skills/

# 配置文件
COPY configs/config.example.yaml ./configs/config.yaml

# 数据目录
RUN mkdir -p data/static

ENV NODE_ENV=production
ENV PORT=5679
ENV GIN_MODE=release

EXPOSE 5679
VOLUME ["/app/data"]

CMD ["./server"]
```

### 2.2 关键优化点

| 优化 | 说明 |
|------|------|
| `-ldflags="-s -w"` | 去掉调试符号和 DWARF 信息，减小二进制体积 |
| `go mod download` 单独层 | 依赖不变时复用缓存 |
| `CGO_ENABLED=1` | go-sqlite3 必需 |
| `ca-certificates` | HTTPS 调用外部 AI API 必需 |
| `GIN_MODE=release` | Gin 框架生产模式，禁用 debug 日志 |

### 2.3 镜像体积对比

| 版本 | 预计镜像大小 |
|------|-------------|
| TS 版（当前） | ~500MB |
| Go 版 | ~200MB（ffmpeg 占 ~100MB） |

Go 二进制本身约 20-30MB，剩余主要是 ffmpeg 和基础镜像。

### 2.4 docker-compose.yml 更新

```yaml
services:
  huobao-drama:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "5679:5679"
    volumes:
      - ./data:/app/data
      - ./configs/config.yaml:/app/configs/config.yaml
      - ./skills:/app/skills
    environment:
      - NODE_ENV=production
      - PORT=5679
      - GIN_MODE=release
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5679/api/v1/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
```

### 2.5 docker-compose.dev.yml（开发环境）

同时运行 TS 和 Go，用于兼容性对比测试：

```yaml
services:
  # TS 后端（旧版）
  backend-ts:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "5679:5679"
    volumes:
      - ./data:/app/data
      - ./configs/config.yaml:/app/configs/config.yaml

  # Go 后端（新版）
  backend-go:
    build:
      context: .
      dockerfile: backend-go/Dockerfile
    ports:
      - "5680:5679"
    volumes:
      - ./data:/app/data
      - ./configs/config.yaml:/app/configs/config.yaml
      - ./skills:/app/skills

  # 前端（开发模式）
  frontend:
    build:
      context: ./frontend
    ports:
      - "3013:3013"
    volumes:
      - ./frontend:/app
      - /app/node_modules
    environment:
      - NUXT_PROXY_GO=http://backend-go:5679
```

### 2.6 生产镜像补充要求

为了满足“可安全替换生产”，镜像与运行时还要满足：

- **继续托管前端静态产物**：Go 服务负责 `frontend/dist` 与 SPA fallback
- **启动恢复异步任务**：容器启动后执行 `ResumePendingTasks()`
- **分层健康检查**：
  - `liveness`：进程仍然存活
  - `readiness`：DB 可用、静态目录可读、配置加载成功
- **统一时区**：容器内显式设置 `TZ`
- **结构化日志**：stdout 输出 JSON，便于采集与告警
- **只读代码目录**：运行时仅 `data/`、日志目录可写

---

## 3. Makefile

```makefile
# Go 后端 Makefile

APP_NAME     := huobao-drama-server
VERSION      := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
BUILD_DIR    := ./build
MAIN_PKG     := ./cmd/server

# Go 编译 flags
LDFLAGS := -ldflags="-s -w -X main.Version=$(VERSION)"

.PHONY: all build run dev clean test lint docker

# 默认目标
all: build

# 编译
build:
	@echo "Building $(APP_NAME) v$(VERSION)..."
	CGO_ENABLED=1 go build $(LDFLAGS) -o $(BUILD_DIR)/$(APP_NAME) $(MAIN_PKG)

# 开发运行（热重载需要 air）
dev:
	@which air > /dev/null 2>&1 || (echo "Installing air..."; go install github.com/air-verse/air@latest)
	CGO_ENABLED=1 air -c .air.toml

# 直接运行
run:
	CGO_ENABLED=1 go run $(MAIN_PKG)

# 清理
clean:
	rm -rf $(BUILD_DIR)

# 单元测试
test:
	CGO_ENABLED=1 go test ./internal/... -v -count=1

# 集成测试
test-integration:
	CGO_ENABLED=1 go test ./tests/integration/... -v -count=1

# 全部测试
test-all:
	CGO_ENABLED=1 go test ./... -v -count=1

# 覆盖率
test-coverage:
	CGO_ENABLED=1 go test ./internal/... -coverprofile=coverage.out -covermode=atomic
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report: coverage.html"

# 类型检查
lint:
	golangci-lint run ./...

# 格式化
fmt:
	gofmt -w .
	goimports -w .

# 依赖整理
tidy:
	go mod tidy

# Docker 构建
docker:
	docker build -f backend-go/Dockerfile -t $(APP_NAME):$(VERSION) .

# 安装开发工具
tools:
	go install github.com/air-verse/air@latest
	go install golangci-lint/cmd/golangci-lint@latest
	go install golang.org/x/tools/cmd/goimports@latest
```

---

## 4. 热重载开发配置（Air）

```toml
# .air.toml — Go 热重载开发配置
root = "."
tmp_dir = "tmp"

[build]
  bin = "./tmp/server"
  cmd = "CGO_ENABLED=1 go build -o ./tmp/server ./cmd/server/"
  delay = 1000
  exclude_dir = ["tmp", "vendor", "data", "skills", "frontend"]
  exclude_regex = ["_test\\.go$"]
  include_ext = ["go", "yaml", "yml"]
  kill_delay = "0.5s"
  send_interrupt = true

[log]
  time = true

[misc]
  clean_on_exit = true
```

---

## 5. 配置文件兼容

Go 版必须能读取现有 `configs/config.yaml`：

```go
// internal/config/config.go
type Config struct {
    App struct {
        Name     string `mapstructure:"name"`
        Version  string `mapstructure:"version"`
        Debug    bool   `mapstructure:"debug"`
        Language string `mapstructure:"language"`
    } `mapstructure:"app"`

    Server struct {
        Port         int      `mapstructure:"port"`
        Host         string   `mapstructure:"host"`
        CorsOrigins  []string `mapstructure:"cors_origins"`
        ReadTimeout  int      `mapstructure:"read_timeout"`
        WriteTimeout int      `mapstructure:"write_timeout"`
    } `mapstructure:"server"`

    Database struct {
        Type    string `mapstructure:"type"`
        Path    string `mapstructure:"path"`
        MaxIdle int    `mapstructure:"max_idle"`
        MaxOpen int    `mapstructure:"max_open"`
    } `mapstructure:"database"`

    Storage struct {
        Type     string `mapstructure:"type"`
        LocalPath string `mapstructure:"local_path"`
        BaseURL  string `mapstructure:"base_url"`
    } `mapstructure:"storage"`

    AI struct {
        DefaultTextProvider  string `mapstructure:"default_text_provider"`
        DefaultImageProvider string `mapstructure:"default_image_provider"`
        DefaultVideoProvider string `mapstructure:"default_video_provider"`
    } `mapstructure:"ai"`
}
```

同时支持环境变量覆盖（Docker 部署场景）：

```go
func Load() *Config {
    viper.SetConfigName("config")
    viper.SetConfigType("yaml")
    viper.AddConfigPath("./configs")
    viper.AddConfigPath(".")

    // 环境变量覆盖
    viper.SetEnvPrefix("HUOBAO")
    viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
    viper.AutomaticEnv()

    // 环境变量绑定
    viper.BindEnv("server.port", "PORT")
    viper.BindEnv("database.path", "DB_PATH")
    viper.BindEnv("storage.local_path", "STORAGE_PATH")

    if err := viper.ReadInConfig(); err != nil {
        log.Warn().Err(err).Msg("No config file found, using defaults")
    }

    var cfg Config
    viper.Unmarshal(&cfg)

    // 默认值
    if cfg.Server.Port == 0 {
        cfg.Server.Port = 5679
    }
    if cfg.Database.Path == "" {
        cfg.Database.Path = "./data/huobao_drama.db"
    }

    return &cfg
}
```

---

## 6. 上线切换流程

### 6.1 灰度切换方案

```
Step 1: 准备 PostgreSQL，执行首版 migration
         ↓
Step 2: 将当前 SQLite 全量导入 PostgreSQL
         ↓
Step 3: Go 后端在 5680 端口运行，连接 PostgreSQL，完成兼容性测试
         ↓
Step 4: 前端代理临时指向 5680，人工走一遍完整流程
         ↓
Step 5: 切换窗口暂停 TS 写流量，执行最后一次增量补录并正式切流
         ↓
Step 6: 观察日志 1-2 天，确认稳定后移除 TS 版代码
```

补充要求：

- 阶段 1-3 为**影子验证**，Go 仅接测试流量
- 阶段 4 为**灰度切换**，只放少量真实流量进入 Go
- 阶段 5 才是**正式切换**，TS 保留热备一段观察期
- 每个阶段都必须完成一次“创建任务后重启 Go”的恢复演练

### 6.2 回滚方案

如果 Go 版出现问题，可以秒级回滚：

```yaml
# docker-compose.yml — 切换后端只需改 build target
services:
  huobao-drama:
    # Go 版
    build:
      context: .
      dockerfile: backend-go/Dockerfile
    # 如需回滚到 TS 版
    # build:
    #   context: .
    #   dockerfile: Dockerfile
```

回滚的前提不再是“共享同一个 SQLite 文件”，而是：

- 切换前保留 SQLite 只读备份
- 切换前生成 PostgreSQL dump
- 切换窗口内记录 Go 新增写入的任务范围，便于人工核对

也就是说，回滚仍然优先做“切流量”，但不能再假设两个版本天然共享同一份主库。

回滚原则：

1. 回滚是**切流量**，不是改库
2. 不手工删除 Go 已写入的记录
3. 不用脚本批量篡改任务状态
4. 回滚后先核对灰度期间新增任务，再决定是否重新灰度

### 6.3 数据安全

- PostgreSQL 数据目录使用 Docker Volume 挂载，不随容器销毁
- `data/static/` 同样挂载
- 切换前建议同时备份 `data/huobao_drama.db` 和 PostgreSQL dump
- 对 `processing` 状态任务做切换前快照，便于恢复核对

### 6.4 生产准入门槛

只有满足以下条件，才允许 Go 替换 TS：

- [ ] CRUD、设置页、工作台关键端点兼容测试全部通过
- [ ] `/static/*` 与 SPA fallback 行为验证通过
- [ ] 至少 1 条完整生产链路在 Go 环境跑通
- [ ] 图片/视频处理中重启恢复测试通过
- [ ] 回滚演练通过
- [ ] 24 小时观测内无异常增长的失败任务、连接池耗尽、锁等待异常或慢 SQL

---

## 7. 性能基准测试

### 7.1 基准测试脚本

```go
// tests/benchmark/bench_test.go
func BenchmarkListDramas(b *testing.B) {
    db := setupBenchDB(b)
    defer db.Close()
    r := setupRouter(db)

    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        w := httptest.NewRecorder()
        req, _ := http.NewRequest("GET", "/api/v1/dramas", nil)
        r.ServeHTTP(w, req)
    }
}

func BenchmarkGetDrama(b *testing.B) {
    db := setupBenchDB(b)
    defer db.Close()
    // 预插入数据
    insertTestDrama(db, 1)
    
    r := setupRouter(db)
    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        w := httptest.NewRecorder()
        req, _ := http.NewRequest("GET", "/api/v1/dramas/1", nil)
        r.ServeHTTP(w, req)
    }
}
```

### 7.2 对比指标

| 指标 | 测试方法 | 目标 |
|------|---------|------|
| QPS（列表接口） | `go test -bench=BenchmarkList` | ≥ 3000 QPS |
| QPS（详情接口） | `go test -bench=BenchmarkGet` | ≥ 5000 QPS |
| P99 延迟 | wrk 压测 | ≤ 10ms（无外部 API 调用） |
| 内存占用 | `pprof` | ≤ 50MB 常驻 |
| Goroutine 数 | `pprof` | ≤ 100（空闲时） |

### 7.3 pprof 集成

```go
// cmd/server/main.go — 开发模式启用 pprof
import _ "net/http/pprof"

func main() {
    if cfg.App.Debug {
        go http.ListenAndServe(":6060", nil) // pprof 端口
    }
    // ... 正常启动
}
```

---

## 8. 交付检查清单

### 8.1 功能完整性

- [ ] 所有 17 个路由文件的 ~60 个端点全部实现
- [ ] 17 张数据库表全部兼容
- [ ] 10 个 AI Provider 适配器全部实现
- [ ] 5 个 Agent 类型全部可运行
- [ ] FFmpeg 合成/拼接正常工作
- [ ] 宫格图切割正常工作
- [ ] Vidu Webhook 回调正常
- [ ] SKILL.md 文件读写正常
- [ ] 一键预设配置正常

### 8.2 兼容性验证

- [ ] 所有 API 响应格式与 TS 版一致
- [ ] snake_case 字段名正确
- [ ] 前端所有页面功能正常
- [ ] 文件上传/下载正常
- [ ] 错误响应格式与状态码一致
- [ ] 静态资源路径与前端 fallback 一致
- [ ] 任务状态流转与 TS 版一致

### 8.3 运维就绪

- [ ] Dockerfile 构建成功
- [ ] docker-compose 启动正常
- [ ] 健康检查端点工作
- [ ] 日志输出格式统一（zerolog JSON）
- [ ] 配置文件兼容（config.yaml）
- [ ] 环境变量覆盖正常
- [ ] 优雅关闭（signal handling）
- [ ] 启动恢复挂起任务（ResumePendingTasks）
- [ ] 有明确灰度与回滚 SOP

### 8.4 优雅关闭

```go
// cmd/server/main.go
func main() {
    // ... 初始化
    
    srv := &http.Server{
        Addr:    fmt.Sprintf(":%d", cfg.Server.Port),
        Handler: router,
    }
    
    go func() {
        log.Info().Int("port", cfg.Server.Port).Msg("Server starting")
        if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
            log.Fatal().Err(err).Msg("Server failed")
        }
    }()
    
    // 等待中断信号
    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit
    
    log.Info().Msg("Shutting down server...")
    ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
    defer cancel()
    
    if err := srv.Shutdown(ctx); err != nil {
        log.Error().Err(err).Msg("Server forced to shutdown")
    }
    
    // 关闭数据库连接
    db.Close()
    log.Info().Msg("Server exited")
}
```
