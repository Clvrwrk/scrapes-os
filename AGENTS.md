# AGENTS.md

Shared project instructions for Agentic OS.

`AGENTS.md` is the canonical instruction file for this repository. Codex reads it directly. Claude Code reads it through `CLAUDE.md` via `@AGENTS.md`.

---

## What This Project Is

Agentic OS is a Claude Code project template that turns Claude into an intelligent business assistant. It is **agent-first**: personality lives in `context/SOUL.md`, user preferences in `context/USER.md`, session continuity in `context/memory/`, accumulated learnings in `context/learnings.md`, brand memory in `brand_context/`, and functionality in `.claude/skills/`.

Claude remains the primary runtime interface. `AGENTS.md` exists so the shared operating rules, registries, and project conventions also work cleanly in Codex and other tools that support the standard file.

The full specification lives in `PRD.md`. Read it when building any new component.

---

## Operating Rules

### Skill & MCP Reconciliation

Compare what is on disk against what is registered in this file. Fix additions silently. Confirm removals with the user.

**Skills — compare `.claude/skills/` folders vs the Skill Registry and Context Matrix tables in `AGENTS.md`:**

1. **New skill on disk, not in AGENTS.md?**
   - Read its YAML frontmatter and full `SKILL.md`
   - Add a row to the **Skill Registry**
   - Add a row to the **Context Matrix**
   - Add a `## {folder-name}` section to `context/learnings.md` under `# Individual Skills`
   - Add the skill to README skill tables and the file structure diagram
   - Scan for external service dependencies
   - Tell the user: "Registered `{skill-name}` — added to AGENTS.md, README.md, and context/learnings.md."

2. **Skill in AGENTS.md but folder missing from disk?**
   - Ask the user: "`{skill-name}` is registered in AGENTS.md but the folder is gone. Remove it from AGENTS.md, README.md, and context/learnings.md?"

**MCPs — compare `.claude/settings.json` MCP server entries vs README documentation:**

3. **New MCP server in settings.json, not documented?**
   - Add it to README.md under a Connected Tools section
   - Tell the user what was added

4. **Documented MCP removed from settings.json?**
   - Ask the user: "`{mcp-name}` is documented but no longer in settings.json. Remove it from README.md?"

**External service detection — runs during new skill registration:**

5. Scan the new skill's `SKILL.md` and `references/` for:
   - Environment variable references like `*_API_KEY` or `*_SECRET`
   - API endpoint URLs
   - SDK imports
   - Explicit mentions of API keys or external services

6. For each new external service:
   - Add it to the **Service Registry** below if missing
   - Add the key to `.env.example` if missing
   - Add the service to README.md if missing
   - Tell the user what was added and what fallback exists

7. If a skill is removed and it was the last consumer of a service:
   - Ask the user whether to remove that service from `AGENTS.md`, `.env.example`, and README.md

### Task Routing

When the user asks a question or requests a task:
1. Check system operations first. If the request matches a built-in operation, execute it directly.
2. Search installed skills by checking `.claude/skills/` frontmatter for a matching skill.
3. If a skill exists, invoke it. Always prefer the dedicated skill over base knowledge.
4. If no skill matches, say so explicitly and offer either:
   - Find or build a skill so the system handles the task well every time
   - Handle it now with base knowledge

Never silently fall back to base knowledge when a skill exists. Never silently handle a task without making the skill gap explicit.

### Built-in Operations

These are core system functions handled by scripts. Check them before searching skills.

| User says | Action |
|-----------|--------|
| "add a client", "new client", "set up a client" | See **Add Client Flow** below |
| "remove a skill", "uninstall {skill}" | Run `bash scripts/remove-skill.sh {skill-name}` |
| "add a skill", "install {skill}" | Run `bash scripts/add-skill.sh {skill-name}` |
| "list skills", "what skills are installed" | Run `bash scripts/list-skills.sh` |
| "start crons", "start scheduled jobs" | Run `bash scripts/start-crons.sh` |
| "stop crons", "stop scheduled jobs" | Run `bash scripts/stop-crons.sh` |
| "cron status", "status crons" | Run `bash scripts/status-crons.sh` |
| "cron logs", "logs crons" | Run `bash scripts/logs-crons.sh` |

### Add Client Flow

When the user asks to add a client:
1. Ask for the client name if it was not provided.
2. Run `bash scripts/add-client.sh "{name}"`.
3. Explain the resulting structure:
   - `clients/{slug}/AGENTS.md` stores client-specific instructions
   - `clients/{slug}/CLAUDE.md` imports the client `AGENTS.md` for Claude Code
   - `brand_context/`, `context/`, `projects/`, and `cron/` stay client-specific
   - Skills, scripts, and shared methodology stay rooted at the main install
4. Tell them exactly how to switch using the full absolute path:
   - `cd {absolute path}/clients/{slug} && claude`
5. Link to `docs/multi-client-guide.md`.

### Branching Policy

Three zones control how changes flow through the dev/main branching model.

| Zone | Paths | On `dev` | On `feature/*` |
|------|-------|----------|----------------|
| **Content** | `projects/`, `brand_context/`, `context/`, `cron/jobs/`, `clients/*/` | Commit directly | Commit directly |
| **Config** | `.claude/skills/*/SKILL.md`, `AGENTS.md`, `CLAUDE.md`, `.env.example`, `scripts/*.sh` | Advisory: consider feature branch | Commit directly |
| **Code** | `command-centre/src/**`, `.claude/hooks/*.js`, runtime JS/TS | Strong nudge: use `/new-feature` | Commit directly |

**`main` is always protected:**
- Requires a PR to merge (no direct push)
- CI status checks must pass
- No force pushes, no deletions

**`dev` is the working branch.** Content changes go directly here. Config and code changes should use feature branches that merge back to `dev`.

**Release flow:** Tag on `dev` with `/release`, then promote to `main` via PR. CI runs automatically on the PR.

**Solo defaults:** No PR approval required, auto-merge available on release PRs. Teams can tighten by requiring 1 approval on `main` PRs and disabling auto-merge.

**Quick fixes:** Use `/new-feature --quick` for trivial one-file fixes — creates a branch, makes the change, merges, and cleans up in one flow.

### Before Major Deliverables

- Load the relevant `brand_context/` files per the Context Matrix below
- Check `context/learnings.md` for the current skill's section
- If brand context is missing, offer to build it; never block work because context is incomplete

### After Major Deliverables

- Ask: "How did this land? Any adjustments?"
- Log feedback to `context/learnings.md` under the skill's section
- If gaps were spotted, mention once with opportunity framing

---

## Memory System

Layered memory architecture. Different files serve different roles, with explicit caps on the ones loaded at session start to keep the prefix cache stable.

### File Roles

| File | Purpose | Cap | Loaded when |
|------|---------|-----|-------------|
| `context/SOUL.md` | Agent identity | ~3 KB | Session start (silent) |
| `context/USER.md` | User profile and preferences | ~1.5 KB | Session start (silent) |
| `context/MEMORY.md` | Curated working scratchpad — durable facts, active threads, environment notes, pending decisions | **2,500 chars** | Session start (silent) |
| `context/memory/{YYYY-MM-DD}.md` | Daily session log (chronological, per-session blocks) | unbounded | Session start (today's only) |
| `context/learnings.md` | Skill-specific learnings | unbounded | Per-skill (lazy) |

### Memory Budget

`context/MEMORY.md` is capped at **2,500 characters**. Before any write:

1. Read the file in full
2. Check character count:
   - Bash: `wc -c < context/MEMORY.md`
   - PowerShell: `(Get-Item context/MEMORY.md).Length`
3. If the new content would push over the cap, consolidate existing entries first — merge similar lines, remove stale ones, tighten verbose entries. Only then add.
4. If still over after consolidation, ask the user which entry to drop.

**Mid-session writes persist to disk but only take effect on the next session.** This is intentional: it preserves the prefix cache (lower cost, faster startup). Always tell the user this in confirmation messages so they know why a just-saved fact isn't immediately visible.

### Memory Write

Triggered by phrases like "remember this", "remember that", "note that", "save this to memory", "update memory", "log this", "forget about", "remove from memory". Routes to the `meta-memory-write` skill.

Three actions:

- **add** — append under the appropriate section (after a substring dedup check)
- **replace** — find substring + swap
- **remove** — show the line to the user and confirm before deleting

Sections in `context/MEMORY.md`:

- `## Active Threads` — current work, open questions
- `## Environment Notes` — URLs, configs, tool versions, project structure quirks
- `## Pending Decisions` — decisions waiting on input

Do not create new sections. If a fact doesn't fit, ask the user where it belongs.

After a write, confirm with: `Saved — will be active from next session.`

Never store secret values in `context/MEMORY.md` — reference env var names only (e.g., `FIRECRAWL_API_KEY in .env`).

### Memory Retrieval

When the user asks about past context, decisions, or facts:

1. **Tier 0** — Check `context/MEMORY.md` and today's daily log. Already in context, zero cost. Covers most durable-fact lookups.
2. **Fallback** — If Tier 0 has nothing: "I don't have a record of that. The detail may be in an older daily log under `context/memory/`."

Tiers 1-3 (semantic search via `memsearch`, expanded chunks, raw transcripts) are deferred to a future phase. Until they ship, do not fabricate sources.

---

## Multi-Client Architecture

Agentic OS supports multiple clients from a single install. The root folder holds shared methodology, shared skills, and shared scripts. Each client gets a subfolder under `clients/` with its own brand context, memory, projects, and learnings.

```text
agentic-os/
├── AGENTS.md                     <- canonical shared instructions
├── CLAUDE.md                     <- Claude wrapper that imports AGENTS.md
├── clients/
│   ├── abc-client/
│   │   ├── AGENTS.md             <- client-specific instructions
│   │   ├── CLAUDE.md             <- Claude wrapper importing local AGENTS.md
│   │   ├── brand_context/
│   │   ├── context/
│   │   ├── projects/
│   │   └── .claude/skills/
│   └── xyz-agency/
│       └── ...
├── brand_context/
├── context/
└── .claude/skills/
```

**How it works:**
- `bash scripts/add-client.sh "Client Name"` creates the client workspace
- The root `AGENTS.md` is the shared source of truth
- Claude reads the same shared guidance through the root `CLAUDE.md`
- Codex reads the root and client `AGENTS.md` files directly when working inside a client folder
- Each client has its own `brand_context/`, `context/memory/`, `context/learnings.md`, `USER.md`, `projects/`, and `cron/jobs/`
- One managed cron runtime per workspace schedules the root plus every `clients/*` job, with a shared leader lock in `.command-centre/`
- Shared skills are edited at the root level; client-only skills live in that client's `.claude/skills/`

Full guide: [docs/multi-client-guide.md](docs/multi-client-guide.md)

---

## Three-Layer Architecture

| Layer | Files | Purpose |
|-------|-------|---------|
| **Agent Identity** | `AGENTS.md`, `CLAUDE.md`, `context/SOUL.md`, `context/USER.md` | Shared operating rules plus Claude-specific runtime behavior |
| **Skills Pack** | `.claude/skills/{category}-{skill-name}/` | Capabilities that grow over time |
| **Brand Context** | `brand_context/` | Client brand data |

`.env`, `.mcp.json`, `installed.json`, user data dirs (`context/memory/`, `projects/`, `brand_context/*.md`) are gitignored. See `.gitignore` for the full list.

---

## Skill Categories

Every skill and its output folder uses a category prefix.

| Prefix | Domain | Examples |
|--------|--------|----------|
| `mkt` | Marketing | `mkt-brand-voice`, `mkt-positioning`, `mkt-icp`, `mkt-email-sequence` |
| `str` | Strategy | `str-keyword-plan`, `str-competitor-analysis` |
| `ops` | Operations / File Mgmt | `ops-client-onboarding`, `ops-gdrive-sync` |
| `viz` | Visual / Video | `viz-thumbnail-creator`, `viz-ugc-generator` |
| `acc` | Accounting | `acc-invoice-generator`, `acc-expense-tracker` |
| `meta` | System / Meta | `meta-skill-creator`, `meta-wrap-up` |
| `tool` | Utility / Integration | `tool-firecrawl-scraper` |

**Rules:**
- Skill folder name = `{category}-{skill-name}` in kebab-case
- YAML frontmatter `name` field must match the folder name exactly
- Output folders use the same category prefix: `projects/{category}-{output-type}/`
- Learnings sections in `context/learnings.md` use `## {folder-name}`
- Add new categories only when the first skill in a new domain is built

---

## Skill Registry

*Auto-populated as skills are installed. Each entry includes its name and trigger conditions.*

### Meta Skills

| Skill | Triggers on |
|-------|-------------|
| `meta-skill-creator` | "create a skill", "build a skill", "new skill", "make a skill", "optimize skill description" |
| `meta-wrap-up` | "wrap up", "close session", "end session", "we're done", "session done" |
| `meta-goal-breakdown` | "break this down", "plan this out", "subtasks", "scope this work", "task breakdown", goal bar submissions |
| `meta-memory-write` | "remember this", "remember that", "note that", "save this to memory", "update memory", "log this", "forget about", "remove from memory" |

### Foundation Skills

| Skill | Triggers on | Writes to |
|-------|-------------|-----------|
| `mkt-brand-voice` | "tone", "writing style", "brand voice", "how we sound" | `voice-profile.md`, `samples.md` |
| `mkt-positioning` | "differentiation", "angle", "hooks", "USP" | `positioning.md` |
| `mkt-icp` | "target audience", "buyer persona", "ideal customer" | `icp.md` |

### Strategy Skills

| Skill | Triggers on |
|-------|-------------|
| `str-ai-seo` | "AI SEO", "AEO", "GEO", "LLMO", "answer engine optimization", "AI citations", "AI visibility", "optimize for ChatGPT/Perplexity/Claude", "show up in AI answers" |

### Visual Skills

| Skill | Triggers on |
|-------|-------------|
| `viz-stitch-design` | "design a UI", "create a screen", "stitch design", "UI mockup", "app design", "landing page design", "mobile screen", "web layout", "wireframe to UI", "design this page" |
| `viz-interface-design` | "dashboard", "admin panel", "SaaS UI", "data interface", "metrics display", "control panel", "monitoring UI", "analytics view", "settings page", "interactive tool interface" |

### Operations Skills

| Skill | Triggers on |
|-------|-------------|
| `ops-new-feature` | "new feature", "start feature", "add feature", "begin work on", "start working on", "finish feature", "done with feature", "merge feature", "feature done", "merge this" |
| `ops-release` | "release", "cut a release", "bump version", "ship it", "new version", "tag a release" |

### Utility Skills

| Skill | Triggers on |
|-------|-------------|
| `tool-stitch` | "fetch stitch design", "get stitch screens", "stitch project", "pull from stitch", "stitch code", "export stitch" |

### Operations Skills

| Skill | Triggers on |
|-------|-------------|
| `ops-cron` | "schedule a job", "cron job", "run this every morning", "automate daily", "recurring task", "scheduled job", "check scheduled jobs", "list jobs", "run job manually", "start crons", "stop crons", "cron status", "cron logs" |

*Optional skills are auto-registered by reconciliation when their folders appear on disk. Install optional skills with `bash scripts/add-skill.sh <name>`. See `.claude/skills/_catalog/catalog.json` for the full list.*

---

## Context Matrix

Load only the `brand_context/` files listed for each skill.

| Skill | voice-profile | positioning | icp | samples | assets | learnings |
|-------|:---:|:---:|:---:|:---:|:---:|:---:|
| `mkt-brand-voice` | **writes** | summary | — | **writes** | **writes** (via firecrawl branding) | `## mkt-brand-voice` |
| `mkt-positioning` | — | **writes** | full | — | — | `## mkt-positioning` |
| `mkt-icp` | — | summary | **writes** | — | — | `## mkt-icp` |
| `meta-wrap-up` | — | — | — | — | — | `## meta-wrap-up` |
| `meta-goal-breakdown` | — | summary | summary | — | — | `## meta-goal-breakdown` |
| `meta-memory-write` | — | — | — | — | — | `## meta-memory-write` |
| `str-ai-seo` | tone only | summary | full | — | — | `## str-ai-seo` |
| `tool-stitch` | — | — | — | — | — | `## tool-stitch` |
| `viz-stitch-design` | tone only | summary | language section | — | — | `## viz-stitch-design` |
| `viz-interface-design` | tone only | summary | language section | — | — | `## viz-interface-design` |
| `ops-cron` | — | — | — | — | — | `## ops-cron` |
| `ops-new-feature` | — | — | — | — | — | `## ops-new-feature` |
| `ops-release` | — | — | — | — | — | `## ops-release` |

**Matrix key:** `writes` = creates file | `full` = entire file | `summary` = 1-2 sentences | `tone only` = tone + vocabulary | `language section` = words-they-use section | `## skill-name` = read only that section from `context/learnings.md`

**Learnings rule:** Every skill reads and writes to its own section in `context/learnings.md`. Cross-skill insights go under `# General`. Skill-specific entries go under `# Individual Skills` → `## {folder-name}`.

---

## Output Standards

- **Single tasks (Level 1):** Save to `projects/{category}-{output-type}/`
- **Planned/GSD projects (Level 2/3):** Save all outputs inside `projects/briefs/{project-name}/`
- Filename format: `{YYYY-MM-DD}_{descriptive-name}.md`
- Folders are created on first use by the skill
- Default format: markdown unless the user specifies otherwise
- After major deliverables: ask for feedback and log it to `context/learnings.md`
- **Auto-download binary outputs:** after saving a non-markdown file, copy it to `~/Downloads/`
- **Show clickable file paths:** always show the full absolute path after saving output

### Projects

| Level | Name | When | Where |
|-------|------|------|-------|
| **1** | Single task | One or a few small deliverables | `projects/{category}-{type}/` |
| **2** | Planned project | Multi-deliverable work that benefits from a brief | `projects/briefs/{project-name}/` |
| **3** | GSD project | Complex multi-phase work with dependencies | `projects/briefs/{project-name}/` + `.planning/` |

**Level 2 brief requirements:** goal, deliverables, acceptance criteria, constraints, and dependencies. Keep it to one page.

**Level 3 rule:** Each Level 3 project owns its own `.planning/` inside `projects/briefs/{slug}/`. Multiple GSD projects can be active in parallel. Archive finished GSD work with `/archive-gsd` (flips the brief's status — nothing moves).

**Project containment rule:** The Agentic OS root is the operating system, not a place for project outputs. All project source code, configs, manifests, build artifacts, and data files must live inside the project folder.

**Brief frontmatter:**

```yaml
---
project: q2-product-launch
status: active
level: 2
created: 2026-03-24
---
```

### Humanizer Gate

Every skill that produces publishable text must run its output through `tool-humanizer` before saving.

- Use `deep` mode when `brand_context/voice-profile.md` exists, otherwise `standard`
- Only show the score summary if the delta is significant
- Research briefs, ICP profiles, and positioning docs can skip this step

---

## Building New Skills

Always ask for reference skills first. Never guess at methodology.

### Skill structure

```text
.claude/skills/{category}-{skill-name}/
├── SKILL.md
├── references/
├── scripts/
└── assets/
```

### Auto-Setup Convention

Skills that need external binaries must include a `scripts/setup.sh` that:
- checks `command -v` first
- uses `brew` on macOS when available, with other fallbacks when needed
- reports clear success or failure
- runs only when dependencies are missing
- avoids user interaction unless absolutely necessary

### YAML frontmatter rules

- About 100 words, under 1024 characters
- Include trigger phrases and negative triggers
- Do not use XML angle brackets

### Skill Dependencies

Declare dependencies in a `## Dependencies` section in `SKILL.md`.

| Skill | Required? | What it provides | Without it |
|-------|-----------|------------------|------------|
| `tool-youtube` | Optional | YouTube transcript fetching | Ask the user to paste content manually |

**Rules:**
- Required dependencies must be installed for the skill to function
- Optional dependencies must declare their fallback
- If a required dependency is missing, tell the user which skill to install
- Utility (`tool-`) skills never depend on execution skills

### Registration checklist

- [ ] Folder name matches `{category}-{skill-name}`
- [ ] Frontmatter `name` matches the folder name exactly
- [ ] Add the skill to the Skill Registry above
- [ ] Add a row to the Context Matrix above
- [ ] Frontmatter stays under 1024 chars
- [ ] `SKILL.md` stays under 200 lines
- [ ] References are self-contained
- [ ] Dependencies are declared when needed
- [ ] Output folders use the same category prefix
- [ ] External services are registered in `AGENTS.md`, `.env.example`, and README.md
- [ ] Publishable text skills include the humanizer gate

### Folder naming

- Format: `{category}-{skill-name}` in kebab-case
- Cannot contain "claude" or "anthropic"

---

## Graceful Degradation

Skills work at all context levels:
- **No `brand_context/`:** ask what is needed and produce solid generic output
- **Partial context:** use what exists and default the rest
- **Full context:** personalise fully

Brand context enhances output. It never gates functionality.

---

## External Services & API Keys

Some skills use external services for enhanced functionality. API keys are stored in `.env` (gitignored). `.env.example` documents all available keys.

### Service Registry

| Service | API Key | Used by | What it enables | Without it |
|---------|---------|---------|-----------------|------------|
| Firecrawl | `FIRECRAWL_API_KEY` | `tool-firecrawl-scraper`, `mkt-brand-voice` (Auto-Scrape) | JS-heavy site scraping, anti-bot bypass, brand asset extraction | Falls back to WebFetch and then manual paste |
| OpenAI | `OPENAI_API_KEY` | `str-trending-research` | Reddit search via Responses API with `web_search` | Falls back to WebSearch without engagement metrics |
| xAI | `XAI_API_KEY` | `str-trending-research` | X/Twitter search via xAI API with `x_search` | Falls back to WebSearch without engagement metrics |
| YouTube Data API v3 | `YOUTUBE_API_KEY` | `tool-youtube` | Channel video listing, handle resolution, search | Direct URL transcript mode still works |
| Google Gemini | `GEMINI_API_KEY` | `viz-nano-banana` | Image generation via Gemini 3 Pro Image | No fallback |
| HeyGen | `HEYGEN_API_KEY` | `viz-ugc-heygen` | AI avatar video generation | No fallback |
| Google Stitch | gcloud auth | `tool-stitch`, `viz-stitch-design` | UI design generation and export | No fallback |

### Rules for Skills Using External Services

1. Check for the required key before using any external API
2. Tell the user clearly what the service does, what they lose without it, where to sign up, and where to put the key
3. Always define a fallback whenever possible
4. Do not block work when the fallback produces usable output
5. Update `.env.example` when adding a new external service

---

## Permissions

`.claude/settings.json` allows: `cat`, `ls`, `npm run *`, basic git commands, and edits to `/src/**`

Denied: package installs, `rm`/`curl`/`wget`/`ssh`, reading `.env`/`.env.local` or credential files. `.env.example` is readable and editable.
