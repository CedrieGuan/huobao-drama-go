# CLAUDE.md

## Project Overview

Huobao Drama — AI-powered drama/video production tool.

Current repo is in a **hybrid migration state**:

- `backend/` is the active Hono + Drizzle + Mastra TypeScript backend
- `frontend/` is the existing Nuxt 3 / Vue 3 web client, used as product and interaction baseline
- `macapp/` is the in-progress macOS Swift native client replacing the web frontend for desktop usage

Do not treat this repo as "full TypeScript stack" anymore.

## Structure

```text
backend/        — Hono + Drizzle ORM + Mastra + better-sqlite3
frontend/       — Nuxt 3 + Vue 3 baseline frontend
macapp/         — Xcode project for HuobaoDrama macOS app
configs/        — config.yaml
data/           — SQLite database + static files
skills/         — Agent SKILL.md definitions
docs/frontend/  — Swift migration analysis, architecture, plan, execution checklist
```

## Commands

### Backend (`backend/`)

- `npm run dev` — start dev server with `tsx watch` on port `5679`
- `npm start` — start production server
- `npm run build` — TypeScript build
- `npm run typecheck` — TypeScript type check

### Frontend Baseline (`frontend/`)

- `npm run dev` — Nuxt dev server on port `3013`
- `npm run build` — Nuxt production build
- `npm run preview` — preview built frontend

### macOS App (`macapp/`)

- Open `macapp/HuobaoDrama.xcodeproj` in Xcode for normal development
- Prefer targeted `xcodebuild` validation when changing Swift code

## Architecture

### Backend

- **HTTP**: Hono with CORS and logger middleware
- **Database**: Drizzle ORM + `better-sqlite3`, WAL mode
- **AI Agents**: Mastra with OpenAI-compatible providers
- **Agent Types**: `script_rewriter`, `extractor`, `storyboard_breaker`
- **Streaming**: SSE for agent chat responses
- **File Storage**: local filesystem under `data/static/`

### Frontend Baseline

- **Nuxt 3** + **Vue 3**
- Used as the functional and interaction reference while migrating to Swift
- Key reference pages:
  - `frontend/app/pages/index.vue`
  - `frontend/app/pages/drama/[id]/index.vue`
  - `frontend/app/pages/drama/[id]/episode/[episodeNumber].vue`
  - `frontend/app/pages/settings.vue`

### macOS Swift App

- Xcode project at `macapp/HuobaoDrama.xcodeproj`
- Main source tree under `macapp/HuobaoDrama/HuobaoDrama/`
- Current module layout includes:
  - `App/`
  - `DesignSystem/`
  - `Models/`
  - `Services/`
  - `ViewModels/`
  - `Views/`

## Migration Docs

Swift migration work should follow these docs in order:

1. `docs/frontend/00-迁移速查版.md`
2. `docs/frontend/01-现状分析.md`
3. `docs/frontend/02-Swift原生架构设计.md`
4. `docs/frontend/03-实施计划.md`
5. `docs/frontend/04-迁移执行清单.md`

`00-迁移速查版.md` is the AI-first quick reference.  
`03-实施计划.md` defines phase goals, batch design, and acceptance criteria.  
`04-迁移执行清单.md` is the execution tracker and current source of truth for progress.

## Migration Execution Rules

When working on Swift migration tasks:

- Default to **one execution batch per run**
- Do not span multiple pages or multiple Agents in one implementation pass
- Prefer reading only:
  - the relevant section in `03-实施计划.md`
  - the matching batch in `04-迁移执行清单.md`
  - the target Swift files
  - at most `1-3` matching Nuxt reference files
- If a task would require:
  - `> 4` file edits, or
  - `> 500` lines of diff, or
  - one pass covering page shell + modal + business actions
  then split it again before implementing

## Database

SQLite database is at `data/drama_generator.db`.

- Schema matches existing tables
- WAL is enabled
- No migration framework is required for the current local DB usage

## Key Config

- `configs/config.yaml` — default AI provider config
- `ai_service_configs` table — AI service configs
- `agent_configs` table — agent configs

## Working Guidance

- Backend remains the runtime source of truth; Swift app should adapt to it rather than redefining APIs casually
- Web frontend is reference material during migration, not the primary target for new feature work
- When docs and code disagree during migration, update the docs after confirming the current implementation reality
