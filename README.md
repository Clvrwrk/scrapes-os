# Agentic OS

Turn Claude Code into your Agentic Operating System.

Agentic OS gives Claude Code personality, memory, and skills so it works like a team member, not a chatbot. It remembers your brand voice, learns your preferences over time, and runs proven methodologies instead of winging it every session.

---

## Quickstart

```bash
git clone https://<YOUR-TOKEN>@github.com/simonc602/agentic-os.git
cd agentic-os
bash scripts/centre.sh
```

**Test edit**: Added this line to test file editing permissions at 2026-04-16.

Replace `<YOUR-TOKEN>` with the access token from the [Agentic Academy classroom](https://www.skool.com/scrapes/classroom/d1cfafed?md=552b0ba753df4c738843913fb3eb8312).

On first launch, `centre.sh` runs the guided bootstrap automatically. It checks your system, prepares the local files Agentic OS needs, repairs missing dependencies when needed, and asks the one-time setup questions.

When it finishes, open Claude Code. It automatically detects you're new and walks you through building your brand foundation -- voice, positioning, and ideal customer profile.

On Windows, use:

```powershell
powershell -File scripts\centre.ps1
```

### Launching the command centre

After the first guided launch, you can keep using:

```bash
centre
```

That's it. The `centre` command reuses the saved launcher state, repairs missing bootstrap files silently when needed, starts the Next.js dev server, and opens `http://localhost:3000` in your browser.

`install.sh` and `setup.sh` still exist for manual maintenance:
- `bash scripts/install.sh` runs the guided installer directly.
- `bash scripts/install.sh --repair` repairs only the local bootstrap files.
- `bash scripts/setup.sh` refreshes dependency checks without launching the UI.

On Windows, the guided install can optionally add `centre` to both Windows PowerShell and PowerShell 7 profiles. If you prefer not to install the shortcut, keep using `powershell -File scripts\centre.ps1`.

Compatibility note: Agentic OS remains Claude-first, but the shared project instructions now live in `AGENTS.md`. Claude reads them through `CLAUDE.md`, and Codex can read `AGENTS.md` directly.

---

## What You Get

Agentic OS is built on three layers:

1. **Agent Identity** -- Personality (SOUL.md), your profile (USER.md), and session memory. This is what makes it feel like working with someone who knows your business.

2. **Skills** -- Modular capabilities that can be added or removed. Each skill follows a tested methodology and self-improves as you give feedback -- corrections go directly into the skill, not just a note.

3. **Brand Context** -- Your voice, positioning, and ideal customer profile. Skills load only what they need, so output stays focused and on-brand.

---

## Core Skills (always installed)

| Skill | What it does |
|-------|-------------|
| `meta-skill-creator` | Build custom skills for your business |
| `meta-wrap-up` | End-of-session memory and learning capture |
| `mkt-brand-voice` | Extract your brand voice from content or build it from scratch |
| `mkt-positioning` | Find angles that make your offer stand out |
| `mkt-icp` | Define your ideal customer so every skill speaks to them |

---

## Optional Skills

| Skill | What it does | API key needed |
|-------|-------------|----------------|
| `tool-humanizer` | Strip AI patterns from any output | -- |
| `tool-firecrawl-scraper` | Scrape JS-heavy websites | `FIRECRAWL_API_KEY` |
| `tool-youtube` | Pull YouTube transcripts and channel listings | `YOUTUBE_API_KEY` (channel mode only) |
| `str-trending-research` | Research trending topics across Reddit, X, and the web | `OPENAI_API_KEY` + `XAI_API_KEY` |
| `mkt-copywriting` | Sales copy with 7-dimension scoring | -- |
| `mkt-content-repurposing` | Turn one piece of content into posts for 8 platforms | -- |
| `mkt-ugc-scripts` | Short-form video scripts with hook library | -- |
| `viz-excalidraw-diagram` | Architecture and workflow diagrams | -- |
| `viz-nano-banana` | AI image generation in 5 visual styles | `GEMINI_API_KEY` |
| `viz-ugc-heygen` | AI avatar videos via HeyGen | `HEYGEN_API_KEY` |
| `str-ai-seo` | Optimize content for AI search engines and LLM citations | -- |
| `viz-interface-design` | Design dashboards, admin panels, and SaaS UIs | -- |
| `ops-cron` | Schedule recurring Claude Code tasks | -- |
| `tool-stitch` | Fetch UI designs from Google Stitch projects | gcloud auth |
| `viz-stitch-design` | Design and iterate on UI screens with Google Stitch | gcloud auth |

---

## GSD (Get Stuff Done)

GSD is a project management framework for Claude Code. It's a separate install (not bundled with Agentic OS) that adds structured planning, execution, and verification for complex multi-step projects.

**Install GSD:**
```bash
npx get-shit-done-cc@latest
```

Use it when you're building something with multiple phases -- a product launch, a new feature, a migration. It handles planning, execution, verification, and session continuity.

**Key commands:**

| Command | What it does |
|---------|-------------|
| `/gsd:new-project` | Start a new project with deep context gathering |
| `/gsd:plan-phase` | Plan a phase with research, task breakdown, and verification |
| `/gsd:execute-phase` | Execute a plan with atomic commits and state tracking |
| `/gsd:progress` | Check where you are and what's next |
| `/gsd:debug` | Systematic debugging with persistent state |
| `/gsd:quick` | Quick task with GSD guarantees (commits, tracking) |
| `/gsd:verify-work` | Validate features through conversational testing |
| `/gsd:pause-work` | Save context for resuming later |
| `/gsd:resume-work` | Pick up where you left off |
| `/gsd:help` | See all available commands |

GSD and Agentic OS complement each other. Agentic OS handles brand context and skill-driven content production. GSD handles structured project execution when you're building something with phases and milestones.

---

## Managing Skills

```bash
bash scripts/list-skills.sh                  # See what's installed and available
bash scripts/add-skill.sh mkt-copywriting    # Add a skill
bash scripts/remove-skill.sh viz-nano-banana # Remove a skill
```

Dependencies are resolved automatically. If you add a skill that needs another skill, both get installed.

---

## Updating

```bash
bash scripts/update.sh
```

This pulls the latest changes from upstream -- new skills, improved methodologies, bug fixes. Your brand context, memory, projects, and API keys are never overwritten.

If you've customised any skills (via feedback, Rules additions, or direct edits), the update script detects this and shows you a diff for each changed skill. You choose per skill: accept our upstream changes, or keep your version. Either way, your version is backed up.

If new skills are available, the script tells you what was added and how to install them.

**If the update fails with an authentication error**, the access token has been rotated. Grab the latest token from the [Agentic Academy classroom](https://www.skool.com/scrapes/classroom/d1cfafed?md=552b0ba753df4c738843913fb3eb8312) and update your remote:

```bash
git remote set-url origin https://<NEW-TOKEN>@github.com/simonc602/agentic-os.git
bash scripts/update.sh
```

---

## Semantic Memory (optional)

Agentic OS includes a semantic recall layer (Tier 1) that lets Claude search across all your past sessions, transcripts, and brand context — not just today's log.

Activation requires two steps, done once after cloning or updating:

**Step 1 — Install the Claude Code plugin**

In Claude Code:
```
/plugin marketplace add zilliztech/memsearch
/plugin install memsearch
```

Restart Claude Code to activate the plugin.

**Step 2 — Install the CLI and index your files**

Mac / Linux / Windows (Git Bash):
```bash
bash scripts/setup-memsearch.sh
```

The script installs the `memsearch` CLI, configures the vector backend, and runs the initial index. On macOS/Linux it works zero-config (local Milvus Lite). On Windows it requires a free [Zilliz Cloud](https://cloud.zilliz.com) cluster — add `ZILLIZ_URI` and `ZILLIZ_TOKEN` to your `.env` before running.

Once both steps are done, Claude indexes every session automatically and keeps the index fresh via a nightly cron. Just ask naturally: "What did we decide about X?" or "What was the positioning angle we used last month?"

Semantic recall is **optional**. Without it, Tier 0 recall (MEMORY.md + today's log) still works as before.

---

## API Keys

Most skills work without any API keys. Some are enhanced with external services (web scraping, image generation, video creation). All keys go in your `.env` file.

To see every available key with descriptions and signup links:

```bash
cat .env.example
```

Skills will tell you when they could use a key you haven't added yet, and they always offer a fallback so your work isn't blocked.

---

## Scheduled Jobs (Cron)

Run tasks automatically through a managed runtime shared by the Command Centre and the CLI daemon. Drop a markdown file into `cron/jobs/`, then choose which host should keep the scheduler alive.

### How it works

1. The same cron core discovers jobs from the root workspace and every `clients/*` workspace
2. It evaluates schedules, catch-up windows, dedupe, retries, heartbeat, and leadership in one place
3. Matching jobs enqueue tasks and execute them headlessly via `claude -p`
4. Per-job status still lands in `cron/status/`, logs still land in `cron/logs/`, and runtime state lives in `.command-centre/`
5. Only one runtime host becomes leader at a time, so the UI and daemon never double-fire the same minute

### Choose the host

**Command Centre UI**
- The scheduler runs in-process while the Command Centre server is running
- It stops with the server
- It always starts the queue watcher, but only schedules jobs if it wins the leader lock

**CLI daemon**
- Use this when you want scheduling to continue while the UI is closed
- Start and stop it manually
- It writes PID, lock, heartbeat, and logs to `.command-centre/`

### Manage the daemon

**Mac/Linux**
```bash
bash scripts/start-crons.sh
bash scripts/status-crons.sh
bash scripts/logs-crons.sh
bash scripts/stop-crons.sh
```

**Windows (PowerShell)**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-crons.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\status-crons.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\logs-crons.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\stop-crons.ps1
```

Compatibility note: `install-crons` and `uninstall-crons` still exist, but they are deprecated wrappers around `start-crons` and `stop-crons`. They no longer register anything with Task Scheduler, launchd, or crontab.

The managed runtime uses your Claude plan credits. Each run costs roughly $0.01-0.05 (haiku), $0.05-0.25 (sonnet), or $0.25-2.00 (opus) depending on the model and task complexity.

### Create a job

Each job is a markdown file in `cron/jobs/` with YAML frontmatter and a prompt body:

```markdown
---
name: "My Daily Research"
time: "09:00"
days: "weekdays"
active: "true"
model: "sonnet"
# Optional
# notify: "on_finish"
# description: "Researches trending topics and saves a daily briefing"
# timeout: "30m"
# retry: "0"
---

You are running as a scheduled job for Agentic OS.

Read CLAUDE.md for system context.

Task: [Your task here]

Save output to: projects/[folder]/{today's date}_[name].md
```

Or just ask Claude: "schedule a job to [do something] every morning" -- the `ops-cron` skill handles the rest.

### Schedule options

| Setting | Examples |
|---------|----------|
| **Exact time** | `time: "09:00"` or `time: "09:00,13:00,17:00"` |
| **Every N minutes** | `time: "every_5m"`, `"every_10m"`, `"every_30m"` |
| **Every N hours** | `time: "every_1h"`, `"every_2h"`, `"every_4h"` |
| **Days** | `days: "daily"`, `"weekdays"`, `"weekends"`, `"mon,wed,fri"` |
| **Model** | `model: "haiku"` (cheap), `"sonnet"` (default), `"opus"` (powerful) |

Full reference: `cron/templates/schedule-reference.md`

### Notifications & status

- **OS notifications** -- jobs send a native notification when they finish. Control this with the `notify` field: `"on_finish"` (default, notifies on success and failure), `"on_failure"` (errors and timeouts only), or `"silent"` (never notify).
- **Smart silence** -- monitoring jobs that find nothing to report can suppress their notification automatically. The job's prompt tells Claude to end with `[SILENT]` when there's nothing actionable. The job still logs normally -- you just don't get pinged for "all clear" results.
- **No duplicate runs** -- if a job is still running when the next scheduled trigger fires, the new run is skipped. This prevents slow jobs from piling up. If a previous run crashed without cleaning up, the system detects the stale state and recovers automatically.
- **Status tracking** -- each job writes its result to `cron/status/`. The managed runtime also tracks leadership, heartbeat, PID, and daemon logs in `.command-centre/`.
- **Catch-up on wake** -- if your laptop was closed during a scheduled fixed-time job, it runs automatically when the machine wakes up. Interval jobs (`every_Nh`) resume on the next matching interval without catching up.
- **Timeout** -- prevents runaway jobs. Default is 30 minutes. Configure per job with the `timeout` field (e.g., `"5m"`, `"1h"`, `"90s"`). If a job exceeds its timeout, the process is killed and the result is recorded as `timeout`.
- **Retry** -- set `retry: "1"` (or higher) to automatically re-run a job on failure. Each retry gets the full timeout. Default is 0 (no retries).

### Manage jobs

| Action | How |
|--------|-----|
| **Pause a job** | Set `active: "false"` in the job file |
| **Resume a job** | Set `active: "true"` in the job file |
| **Run a job now** | `bash scripts/run-job.sh {job-name}` on macOS/Linux or `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run-job.ps1 {job-name}` on Windows |
| **Check logs** | `cat cron/logs/{job-name}.log` |
| **List all jobs** | `ls cron/jobs/` or ask Claude "what's scheduled?" |
| **Start the daemon** | `bash scripts/start-crons.sh` or `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\start-crons.ps1` |
| **Stop the daemon** | `bash scripts/stop-crons.sh` or `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\stop-crons.ps1` |
| **Check runtime status** | `bash scripts/status-crons.sh` or `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\status-crons.ps1` |
| **Show daemon logs** | `bash scripts/logs-crons.sh` or `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\logs-crons.ps1` |

Stopping the daemon only stops automatic scheduling. Your job files in `cron/jobs/` are never deleted.

### Important notes

- **No OS scheduler fallback** -- automatic scheduling no longer depends on Task Scheduler, launchd, or crontab.
- **UI behavior** -- if you rely on the Command Centre host, scheduling stops when the server stops.
- **CLI behavior** -- the daemon is manual. Start it when you want background scheduling and stop it explicitly when you do not.
- **Leader lock** -- if the UI and daemon coexist, only one of them schedules jobs. The other host stays passive.
- **Legacy scripts** -- `run-crons` is deprecated and no longer performs scheduling.
- **Existing sessions:** Jobs run as separate headless processes -- they don't interfere with any open Claude Code session.

---

## Windows Notification Theme

Windows notification visuals and default copy live in `scripts/windows-notify.config.json`.

- `app` controls the Windows app identity, display name, Start Menu shortcut name, generated asset cache version, optional attribution, default toast duration, and the default layout (`compact` or `hero`).
- `assets.logoPath` should point to the toast logo image. `assets.shortcutIconPath` should point to the Windows shortcut icon and must be an `.ico` file.
- The repo-tracked asset folder for Windows branding is `scripts/assets/windows-notify/`.
- `assets.heroPaths.*` can point to optional background images for hero mode. If blank or missing, the helper generates the hero background and overlays the event-specific text on top.
- `assets.generatedLogo` controls the fallback logo artwork when the configured toast logo image is missing.
- `assets.variants.*` controls the gradient palette, accent colors, sound, and emoji for each notification variant.
- `copy.interactive.*` and `copy.cron.*` define the default `status`, `subject`, `detail`, `variant`, `duration`, and `layout` for each Windows notification event.
- Supported template placeholders are `{project}`, `{seq}`, `{duration}`, `{rawMessage}`, `{jobName}`, `{timeout}`, `{exitCode}`, and `{catchUpSuffix}`.

Preview the default compact toast with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-windows-notify.ps1 -Variant success
```

Preview hero mode explicitly with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-windows-notify.ps1 -Variant success -Layout hero
```

If you change generated colors, layout, or badge text, either bump `app.assetVersion` in `scripts/windows-notify.config.json` or delete the cached folder under `%LOCALAPPDATA%\AgenticOS\notifications\` so Windows rebuilds the generated assets.

---

## Multiple Clients

If you work with more than one client or brand, just tell Claude: **"add a client called [name]"**. It creates the workspace, and offers to switch you into it.

You can also do it manually:

```bash
bash scripts/add-client.sh "Client Name"
cd clients/client-name
claude
```

Each client has its own brand context, memory, and output. Shared methodology now lives in `AGENTS.md` at the root, with `CLAUDE.md` importing it for Claude Code. Skills and scripts sync automatically when you run `update.sh`.

For the full setup guide, see [docs/multi-client-guide.md](docs/multi-client-guide.md).
For how projects work (single tasks, planned projects, GSD), see [docs/projects-guide.md](docs/projects-guide.md).
For a quick reference, see [docs/cheat-sheet.md](docs/cheat-sheet.md).

---

## File Structure

```
├── context/
│   ├── SOUL.md            <- Agent personality and behaviour rules
│   ├── USER.md            <- Your preferences and working style
│   ├── learnings.md       <- Accumulated skill feedback (gets smarter over time)
│   └── memory/            <- Daily session logs (auto-links to active projects)
├── brand_context/         <- Your brand data (voice, positioning, ICP)
├── .claude/skills/        <- Installed skill packs
├── command-centre/        <- Local UI and runtime app (versioned with the repo)
├── cron/jobs/             <- Scheduled job definitions
├── projects/              <- All generated output
│   ├── mkt-copywriting/   <- Single task category folders (Level 1)
│   └── briefs/            <- Multi-deliverable projects (Level 2/3)
│       └── q2-launch/     <- Project folder with brief.md
│           └── .planning/ <- GSD artifacts (Level 3, per project)
├── scripts/               <- Install, update, manage skills, watchdog
├── AGENTS.md              <- Canonical shared instructions
└── CLAUDE.md              <- Claude wrapper that imports AGENTS.md
```

---

## Quality of Life

A few things baked in to make the day-to-day smoother:

- **CC Notify** -- native OS notifications (Mac & Windows) when Claude finishes a task, needs permission, or is waiting for input. No more checking back every 30 seconds.
- **Auto-download** -- binary outputs (images, videos, PDFs) auto-copy to your Downloads folder.
- **Humanizer gate** -- every skill that produces publishable text automatically strips AI writing patterns before saving.
- **Clickable file paths** -- every saved file shows the full path so you can click to open it.
- **Graceful degradation** -- no skill breaks because something is missing. No API key? Free fallback. No brand context? Solid generic output.

---

## Your Data is Safe

These are yours and are never overwritten by updates:

- **brand_context/** -- your voice profile, positioning, ICP
- **context/** -- your memory, learnings, session history
- **projects/** -- everything the system generates for you
- **.env** -- your API keys (gitignored, never leaves your machine)

---

## Need Help?

Head to the Agentic Academy Skool community. Post your question and the team or another member will help you out.

---

Built by Simon Scrapes @ Agentic Academy
